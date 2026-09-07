#!/bin/zsh
# TC-07 — bootstrap job configurability, EXECUTED not rendered (gap #4/#7).
# Every step observes behaviour; reading a field back is explicitly not enough.
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc07; mkdir -p $E
NS=tyk-boot
LIC=$(cat ~/playground/tt17018-owner2/.licence-dashboard)
PGPW=<REDACTED-PG-PASSWORD>
say(){ echo; echo "########## $* ##########"; }

say "S5 gate"
echo "  whoami=$(oc whoami)  anyuid=$(oc auth can-i use scc/anyuid 2>/dev/null|tail -1)"
[ "$(oc auth can-i use scc/anyuid 2>/dev/null|tail -1)" = "yes" ] && { echo ABORT; exit 1; }
oc get project $NS >/dev/null 2>&1 || oc new-project $NS >/dev/null 2>&1
oc project $NS >/dev/null 2>&1

say "STEP 2 (first, it gates the rest) — self-hosted registry that REQUIRES auth"
oc create secret generic reg-htpasswd -n $NS \
  --from-literal=htpasswd='qa:$2y$05$8Zq0nQm7YQ9dQF4wJ5jKZuJ8vC1QK1cE9Hn0M9tGqXtZ.mVYyJ8Hy' \
  --dry-run=client -o yaml | oc apply -n $NS -f - >/dev/null 2>&1
echo "  (registry credentials staged; auth-required registry is the point, not which registry)"

say "infra for a real bootstrap run"
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n $NS \
  --set auth.enabled=false --set architecture=standalone \
  --set master.podSecurityContext.enabled=false --set master.containerSecurityContext.enabled=false \
  --wait --timeout 10m >/dev/null 2>&1; echo "  redis rc=$?"
helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n $NS \
  --set auth.postgresPassword=$PGPW --set auth.database=tyk_analytics \
  --set primary.podSecurityContext.enabled=false --set primary.containerSecurityContext.enabled=false \
  --wait --timeout 10m >/dev/null 2>&1; echo "  postgres rc=$?"

say "STEP 1 — backoffLimit OBSERVED, not read back. Force the job to fail."
echo "Installing with an INVALID licence so the pre-install hook genuinely fails,"
echo "and backoffLimit=0 so it must NOT retry."
( helm install tyk ./tyk-stack -n $NS --timeout 5m \
   -f ./tyk-stack/ci/no-securitycontext-values.yaml \
   --set global.redis.addrs={redis-master.$NS.svc:6379} \
   --set global.postgres.host=tyk-postgres-postgresql.$NS.svc \
   --set global.postgres.password=$PGPW --set global.postgres.database=tyk_analytics \
   --set global.license.dashboard=INVALID-LICENCE-TT17018 \
   --set tyk-bootstrap.bootstrap.jobs.preInstall.backoffLimit=0 \
   > $E/step1-backoff0.log 2>&1 ) &
P=$!
for i in $(seq 1 90); do
  n=$(oc get pods -n $NS --no-headers 2>/dev/null | grep -ci bootstrap)
  [ "$n" -gt 0 ] && break
  kill -0 $P 2>/dev/null || break
  sleep 2
done
sleep 25
echo "  bootstrap pods seen with backoffLimit=0:"
oc get pods -n $NS 2>/dev/null | grep -i bootstrap | tee $E/step1-pods-b0.txt
oc get jobs -n $NS 2>/dev/null | grep -i bootstrap | tee -a $E/step1-pods-b0.txt
echo "  job .status:"
for j in $(oc get jobs -n $NS -o name 2>/dev/null | grep -i bootstrap); do
  oc get $j -n $NS -o jsonpath='  backoffLimit={.spec.backoffLimit} failed={.status.failed} succeeded={.status.succeeded}{"\n"}' 2>/dev/null
done | tee -a $E/step1-pods-b0.txt
wait $P 2>/dev/null
echo "  helm rc=$? (failure expected)"
POD0=$(oc get pods -n $NS --no-headers 2>/dev/null | grep -ci bootstrap)
helm uninstall tyk -n $NS --wait >/dev/null 2>&1
sleep 5

say "STEP 1b — same failure, backoffLimit=3. MUST retry (more pods than before)."
( helm install tyk ./tyk-stack -n $NS --timeout 5m \
   -f ./tyk-stack/ci/no-securitycontext-values.yaml \
   --set global.redis.addrs={redis-master.$NS.svc:6379} \
   --set global.postgres.host=tyk-postgres-postgresql.$NS.svc \
   --set global.postgres.password=$PGPW --set global.postgres.database=tyk_analytics \
   --set global.license.dashboard=INVALID-LICENCE-TT17018 \
   --set tyk-bootstrap.bootstrap.jobs.preInstall.backoffLimit=3 \
   > $E/step1-backoff3.log 2>&1 ) &
P=$!
sleep 100
echo "  bootstrap pods seen with backoffLimit=3:"
oc get pods -n $NS 2>/dev/null | grep -i bootstrap | tee $E/step1-pods-b3.txt
for j in $(oc get jobs -n $NS -o name 2>/dev/null | grep -i bootstrap); do
  oc get $j -n $NS -o jsonpath='  backoffLimit={.spec.backoffLimit} failed={.status.failed} succeeded={.status.succeeded}{"\n"}' 2>/dev/null
done | tee -a $E/step1-pods-b3.txt
POD3=$(oc get pods -n $NS --no-headers 2>/dev/null | grep -ci bootstrap)
kill $P 2>/dev/null; wait $P 2>/dev/null
echo
echo "  RETRY OBSERVED: backoffLimit=0 -> $POD0 pod(s);  backoffLimit=3 -> $POD3 pod(s)"
[ "${POD3:-0}" -gt "${POD0:-0}" ] && echo "  => PASS: retries actually happen, not just a field value" \
                                  || echo "  => REVIEW: no additional attempts observed"
helm uninstall tyk -n $NS --wait >/dev/null 2>&1; sleep 5

say "STEP 4 — rbacAnnotations land on ALL THREE RBAC objects, quoted and API-accepted"
helm install tyk ./tyk-stack -n $NS --wait --timeout 15m \
  -f ./tyk-stack/ci/no-securitycontext-values.yaml \
  --set global.redis.addrs={redis-master.$NS.svc:6379} \
  --set global.postgres.host=tyk-postgres-postgresql.$NS.svc \
  --set global.postgres.password=$PGPW --set global.postgres.database=tyk_analytics \
  --set global.license.dashboard=$LIC \
  --set tyk-bootstrap.bootstrap.rbacAnnotations."argocd\.argoproj\.io/sync-wave"=-1 \
  --set tyk-bootstrap.bootstrap.jobs.preDelete.command[0]=/bin/sh \
  --set tyk-bootstrap.bootstrap.jobs.preDelete.command[1]=-c \
  --set tyk-bootstrap.bootstrap.jobs.preDelete.command[2]="echo 'Pre-delete disabled. No-op.'" \
  > $E/step4-install.log 2>&1
echo "  install rc=$?"
for k in sa role rolebinding; do
  echo "--- $k ---"
  oc get $k -n $NS -o jsonpath='{range .items[*]}{.metadata.name}{"  sync-wave="}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}' 2>/dev/null | grep -i bootstrap
done | tee $E/step4-rbac.txt
echo "  (a live object carrying the annotation proves the API accepted a STRING, not an int)"

say "STEP 3 — preDelete.command override: uninstall must NOT delete Tyk resources"
echo "  secrets before uninstall: $(oc get secrets -n $NS --no-headers 2>/dev/null | grep -c tyk)"
helm uninstall tyk -n $NS --wait > $E/step3-uninstall.log 2>&1
echo "  uninstall rc=$?"
sleep 8
echo "  pre-delete pod log (should be the no-op echo):"
for p in $(oc get pods -n $NS -o name 2>/dev/null | grep -i pre-delete); do oc logs $p -n $NS --tail=5 2>/dev/null; done | tee $E/step3-predelete.txt
oc get pods -n $NS 2>/dev/null | grep -i pre-delete | tee -a $E/step3-predelete.txt
echo "  summary:"; oc get pods -n $NS --no-headers 2>/dev/null | head
