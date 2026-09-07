#!/bin/zsh
# TC-04 Steps 4-10 — ALL FOUR umbrellas on real OpenShift, as unprivileged `developer`.
# Each umbrella gets its own namespace and its own Redis/PostgreSQL, so a failure in one
# cannot be confused with contention from another. The single cross-namespace dependency
# is tyk-data-plane -> the control-plane's MDCB, which is inherent to the topology.
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc04; mkdir -p $E
LIC=$(cat ~/playground/tt17018-owner2/.licence-dashboard)
MDCB=$(cat ~/playground/tt17018-owner2/.licence-mdcb)
PGPW=<REDACTED-PG-PASSWORD>
say(){ echo; echo "########## $* ##########"; }

# ---------- gate ----------
say "S5 PRIVILEGE GATE"
echo "whoami: $(oc whoami)   server: $(oc whoami --show-server)"
for c in anyuid privileged; do
  r=$(oc auth can-i use scc/$c 2>/dev/null | tail -1)
  printf '  can-i use scc/%-11s -> %s\n' "$c" "$r"
  [ "$r" = "yes" ] && { echo "ABORT: holding $c — every SCC result would be worthless"; exit 1; }
done
echo "  can-i '*' '*'             -> $(oc auth can-i '*' '*' 2>/dev/null | tail -1)"

# ---------- helpers ----------
mkns(){ oc get ns $1 >/dev/null 2>&1 || oc new-project $1 >/dev/null 2>&1 || oc create ns $1 >/dev/null 2>&1
        oc project $1 >/dev/null 2>&1
        local u=$(oc get ns $1 -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}')
        echo "  ns $1 uid-range=$u"; }

infra(){ # $1=ns  $2=want_pg  $3=pg_db
  echo "  installing redis in $1..."
  helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n $1 \
    --set auth.enabled=false --set architecture=standalone \
    --set master.podSecurityContext.enabled=false \
    --set master.containerSecurityContext.enabled=false \
    --wait --timeout 10m > $E/infra-redis-$1.log 2>&1
  echo "    redis exit=$?"
  if [ "$2" = "yes" ]; then
    echo "  installing postgresql in $1 (db=$3)..."
    helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n $1 \
      --set auth.postgresPassword=$PGPW --set auth.database=$3 \
      --set primary.podSecurityContext.enabled=false \
      --set primary.containerSecurityContext.enabled=false \
      --wait --timeout 10m > $E/infra-pg-$1.log 2>&1
    echo "    postgres exit=$?"
  fi
}

# install with concurrent bootstrap-log capture (hook Jobs self-delete on success)
install_capture(){ # $1=release $2=chart $3=ns ; rest = extra flags
  local rel=$1 chart=$2 ns=$3; shift 3
  ( helm install $rel ./$chart -n $ns --wait --timeout 20m \
      -f ./$chart/ci/no-securitycontext-values.yaml "$@" \
      > $E/install-$chart.log 2>&1; echo $? > /tmp/rc-$chart ) &
  local pid=$!
  typeset -A seen
  while kill -0 $pid 2>/dev/null; do
    for pod in $(oc get pods -n $ns -o name 2>/dev/null | grep -i bootstrap); do
      local nm=${pod#pod/}
      [ -z "${seen[$nm]:-}" ] && { echo "    [bootstrap pod] $nm"; seen[$nm]=1; }
      oc logs $pod -n $ns --tail=40 > /tmp/bl.txt 2>/dev/null && [ -s /tmp/bl.txt ] && cp /tmp/bl.txt $E/joblog-$chart-$nm.txt
    done
    sleep 2
  done
  wait $pid
  echo "  install exit=$(cat /tmp/rc-$chart 2>/dev/null)"
}

verify(){ # $1=ns $2=chart
  local ns=$1 chart=$2
  local UIDR=$(oc get ns $ns -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}')
  local LO=${UIDR%%/*}; local HI=$(( LO + ${UIDR##*/} - 1 ))
  say "[$chart] Step 5 — SCC + injected fsGroup in band [$LO,$HI]"
  local bad=0
  { printf '%-52s %-16s %-12s %s\n' POD SCC FSGROUP INBAND
    for p in $(oc get pods -n $ns -o name 2>/dev/null); do
      local scc=$(oc get $p -n $ns -o jsonpath='{.metadata.annotations.openshift\.io/scc}')
      local fg=$(oc get $p -n $ns -o jsonpath='{.spec.securityContext.fsGroup}')
      local ib="n/a"
      [ -n "$fg" ] && { { [ "$fg" -ge $LO ] && [ "$fg" -le $HI ]; } && ib=yes || { ib=NO; bad=1; }; }
      [ -n "$scc" ] && [ "$scc" != "restricted-v2" ] && bad=1
      printf '%-52s %-16s %-12s %s\n' "${p#pod/}" "${scc:-<none>}" "${fg:-<none>}" "$ib"
    done; } | tee $E/step5-$chart.txt
  echo "  => $([ $bad -eq 0 ] && echo PASS || echo FAIL)"

  say "[$chart] Step 6 — SCC denials in events (pass = none)"
  oc get events -n $ns --field-selector type=Warning 2>/dev/null \
    | grep -iE 'FailedCreate|forbidden|scc|securityContext' | tee $E/step6-$chart.txt
  [ -s $E/step6-$chart.txt ] || echo "  (none) PASS"

  say "[$chart] Step 7 — bootstrap Jobs, logs captured live"
  ls $E/joblog-$chart-* >/dev/null 2>&1 && { for f in $E/joblog-$chart-*; do echo "--- ${f##*/} ---"; head -12 "$f"; done; echo "  => PASS (real work logged)"; } \
    || echo "  (no bootstrap pods — expected for tyk-oss / tyk-data-plane)"

  say "[$chart] Step 8 — null keys on LIVE objects (pass = none)"
  : > $E/step8-$chart.txt
  for k in deploy sts job sa role rolebinding cm svc secret; do
    oc get $k -n $ns -o yaml 2>/dev/null | grep -nE ':[[:space:]]*null[[:space:]]*$' | sed "s/^/$k: /" >> $E/step8-$chart.txt
  done
  [ -s $E/step8-$chart.txt ] && cat $E/step8-$chart.txt || echo "  (none) PASS"

  say "[$chart] Step 9 — workload readiness"
  oc get pods -n $ns --no-headers 2>/dev/null | tee $E/step9-$chart.txt
  local nr=$(oc get pods -n $ns --no-headers 2>/dev/null | grep -vcE 'Running|Completed')
  echo "  pods not Running/Completed: $nr  => $([ "$nr" -eq 0 ] && echo PASS || echo INVESTIGATE)"
}

# ============================================================================
# 1. tyk-control-plane — gap #2's genuinely-never-installed umbrella, first
# ============================================================================
say "UMBRELLA 1/4 — tyk-control-plane (ns tyk-qa)"
mkns tyk-qa
infra tyk-qa yes tyk_cp
install_capture tyk tyk-control-plane tyk-qa \
  --set global.redis.addrs={redis-master.tyk-qa.svc:6379} \
  --set global.postgres.host=tyk-postgres-postgresql.tyk-qa.svc \
  --set global.postgres.password=$PGPW \
  --set global.postgres.database=tyk_cp \
  --set global.license.dashboard=$LIC \
  --set tyk-mdcb.mdcb.license=$MDCB \
  --set global.components.pump=true
oc get pods -n tyk-qa -o wide | tee $E/pods-tyk-control-plane.txt
verify tyk-qa tyk-control-plane

# harvest the credentials tyk-data-plane needs from the CP bootstrap
say "harvesting MDCB connection details from the control plane"
ORG=$(oc get secret -n tyk-qa tyk-operator-conf -o jsonpath='{.data.TYK_ORG}' 2>/dev/null | base64 -d)
KEY=$(oc get secret -n tyk-qa tyk-operator-conf -o jsonpath='{.data.TYK_AUTH}' 2>/dev/null | base64 -d)
echo "  orgId=${ORG:0:8}...  userApiKey=${KEY:0:8}...  (len ${#ORG}/${#KEY})"

# ============================================================================
# 2. tyk-stack
# ============================================================================
say "UMBRELLA 2/4 — tyk-stack (ns tyk-stack)"
mkns tyk-stack
infra tyk-stack yes tyk_analytics
install_capture tyk tyk-stack tyk-stack \
  --set global.redis.addrs={redis-master.tyk-stack.svc:6379} \
  --set global.postgres.host=tyk-postgres-postgresql.tyk-stack.svc \
  --set global.postgres.password=$PGPW \
  --set global.postgres.database=tyk_analytics \
  --set global.license.dashboard=$LIC \
  --set global.components.pump=true
oc get pods -n tyk-stack -o wide | tee $E/pods-tyk-stack.txt
verify tyk-stack tyk-stack

# ============================================================================
# 3. tyk-data-plane — connects to the control plane's MDCB
# ============================================================================
say "UMBRELLA 3/4 — tyk-data-plane (ns tyk-dp)"
mkns tyk-dp
infra tyk-dp no -
DPFLAGS=(--set global.redis.addrs={redis-master.tyk-dp.svc:6379} --set global.components.pump=true)
if [ -n "${ORG:-}" ] && [ -n "${KEY:-}" ]; then
  echo "  wiring to MDCB at mdcb-svc-tyk-tyk-mdcb.tyk-qa.svc:9091"
  DPFLAGS+=(--set global.remoteControlPlane.connectionString=mdcb-svc-tyk-tyk-mdcb.tyk-qa.svc:9091
            --set global.remoteControlPlane.orgId=$ORG
            --set global.remoteControlPlane.userApiKey=$KEY
            --set global.remoteControlPlane.groupID=qa-group
            --set global.remoteControlPlane.useSSL=false)
else
  echo "  WARNING: no CP credentials harvested — installing data-plane unconnected."
  echo "  Pods may not reach Ready; that is an MDCB wiring issue, NOT an SCC finding."
fi
install_capture tyk tyk-data-plane tyk-dp $DPFLAGS
oc get pods -n tyk-dp -o wide | tee $E/pods-tyk-data-plane.txt
verify tyk-dp tyk-data-plane

# ============================================================================
# 4. tyk-oss — last, per the packet: already covered by CI, cheapest to drop
# ============================================================================
say "UMBRELLA 4/4 — tyk-oss (ns tyk-oss)"
mkns tyk-oss
infra tyk-oss no -
install_capture tyk tyk-oss tyk-oss \
  --set global.redis.addrs={redis-master.tyk-oss.svc:6379} \
  --set global.components.pump=true
oc get pods -n tyk-oss -o wide | tee $E/pods-tyk-oss.txt
verify tyk-oss tyk-oss

# ============================================================================
say "TC-04 Step 10 — per-umbrella grid (this grid IS §6 row 4)"
printf '%-22s %-10s %-14s %-12s %s\n' UMBRELLA PODS ALL-RESTRICTED FSGROUP-BAND NULL-KEYS
for pair in "tyk-qa:tyk-control-plane" "tyk-stack:tyk-stack" "tyk-dp:tyk-data-plane" "tyk-oss:tyk-oss"; do
  ns=${pair%%:*}; ch=${pair##*:}
  n=$(oc get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
  nonr=$(grep -c ' restricted-v2 ' $E/step5-$ch.txt 2>/dev/null)
  bad=$(grep -c ' NO$' $E/step5-$ch.txt 2>/dev/null)
  nk=$(wc -l < $E/step8-$ch.txt 2>/dev/null | tr -d ' ')
  printf '%-22s %-10s %-14s %-12s %s\n' "$ch" "$n" "$nonr on rv2" "$([ "${bad:-0}" -eq 0 ] && echo ok || echo "$bad OUT)" )" "${nk:-0}"
done | tee $E/step10-grid.txt
echo
echo "Evidence: $E"
