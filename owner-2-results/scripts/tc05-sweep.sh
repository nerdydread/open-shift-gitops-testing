#!/bin/zsh
# TC-05 Steps 1-4 — GitOps render verification, all four umbrellas.
# NOTE: zsh does not word-split unquoted string vars — flags MUST be arrays.
# A string var silently becomes one malformed argument, helm errors, and
# `2>&1 | grep` then reports a FALSE PASS. (Same class as D-07.)
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc05
UMB=(tyk-oss tyk-stack tyk-control-plane tyk-data-plane)
HOOKS=(--set tyk-bootstrap.bootstrap.disableHelmHooks=true)
ALLCOMP=(--set global.components.pump=true --set global.components.devPortal=true --set global.components.operator=true)

pf(){ printf '%-20s %-8s %s\n' "$1" "$2" "$3"; }

# render guard: fail loudly instead of grepping an error message
render(){ # $1=umbrella, rest=flags ; writes to $R, returns helm's exit code
  R=$(helm template t ./$1 "${@:2}" 2>/tmp/helm-err.txt); rc=$?
  if [ $rc -ne 0 ]; then echo "RENDER FAILED: $(head -1 /tmp/helm-err.txt)" >&2; fi
  return $rc
}

echo "########## TC-05 Step 1 — null-key sweep (pass = no output) ##########"
for u in $UMB; do
  render $u $HOOKS || { pf $u "ERROR" "render failed"; continue; }
  out=$(echo "$R" | grep -nE ':[[:space:]]*null[[:space:]]*$')
  echo "$out" > $E/step1-$u.txt
  [ -z "$out" ] && pf $u "PASS" "no null keys  (render ${(f)#R}L)" || { pf $u "FAIL" "$(echo "$out"|wc -l|tr -d ' ') null keys"; echo "$out"|head -5; }
done

echo "\n########## TC-05 Step 1b — same, pump+devPortal+operator enabled ##########"
for u in $UMB; do
  render $u $HOOKS $ALLCOMP || { pf $u "ERROR" "render failed"; continue; }
  out=$(echo "$R" | grep -nE ':[[:space:]]*null[[:space:]]*$')
  echo "$out" > $E/step1b-$u.txt
  [ -z "$out" ] && pf $u "PASS" "no null keys  (render ${(f)#R}L)" || { pf $u "FAIL" "$(echo "$out"|wc -l|tr -d ' ') null keys"; echo "$out"|head -5; }
done

echo "\n########## TC-05 Step 2 — hook annotations (pass = no output) ##########"
for u in $UMB; do
  render $u $HOOKS || { pf $u "ERROR" "render failed"; continue; }
  out=$(echo "$R" | grep -n 'helm.sh/hook')
  echo "$out" > $E/step2-$u.txt
  if [ -z "$out" ]; then pf $u "PASS" "no hook annotations"; else
    nb=$(echo "$out" | grep -vc 'hook: test\|hook-delete-policy')
    pf $u "SEE" "$(echo "$out"|wc -l|tr -d ' ') hits ($nb non-test)"; echo "$out" | sed 's/^/      /'
  fi
done

echo "\n########## TC-05 Step 3 — pre-delete Job (pass = no output) ##########"
for u in $UMB; do
  render $u $HOOKS || { pf $u "ERROR" "render failed"; continue; }
  out=$(echo "$R" | grep -n 'pre-delete')
  echo "$out" > $E/step3-$u.txt
  [ -z "$out" ] && pf $u "PASS" "no pre-delete" || { pf $u "FAIL" "$(echo "$out"|wc -l|tr -d ' ') hits"; echo "$out"|head -5; }
done

echo "\n########## TC-05 Step 4 — annotation quoting (pass = all quoted) ##########"
for u in $UMB; do
  R=$(helm template t ./$u \
    --set tyk-bootstrap.bootstrap.rbacAnnotations."argocd\.argoproj\.io/sync-wave"=-1 \
    --set tyk-bootstrap.bootstrap.jobs.preInstall.annotations."argocd\.argoproj\.io/sync-wave"=-1 2>/tmp/helm-err.txt) \
    || { pf $u "ERROR" "$(head -1 /tmp/helm-err.txt)"; continue; }
  out=$(echo "$R" | grep -n 'sync-wave')
  echo "$out" > $E/step4-$u.txt
  if [ -z "$out" ]; then pf $u "n/a" "no bootstrap in this umbrella"; else
    unq=$(echo "$out" | grep -v '"-1"')
    [ -z "$unq" ] && { pf $u "PASS" "$(echo "$out"|wc -l|tr -d ' ')/$(echo "$out"|wc -l|tr -d ' ') quoted"; echo "$out"|sed 's/^/      /'; } \
                  || { pf $u "FAIL" "unquoted"; echo "$unq"; }
  fi
done
