#!/bin/zsh
# TC-08 Steps 1, 5, 6 — dev portal LIVE on OpenShift (gap #6: no smoke job installs it at all).
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc08; mkdir -p $E
NS=tyk-portal
LIC=$(cat ~/playground/tt17018-owner2/.licence-dashboard)
PGPW=<REDACTED-PG-PASSWORD>
say(){ echo; echo "########## $* ##########"; }

say "S5 gate"
echo "  whoami=$(oc whoami)  anyuid=$(oc auth can-i use scc/anyuid 2>/dev/null|tail -1)"
[ "$(oc auth can-i use scc/anyuid 2>/dev/null|tail -1)" = "yes" ] && { echo ABORT; exit 1; }

oc get project $NS >/dev/null 2>&1 || oc new-project $NS >/dev/null 2>&1
oc project $NS >/dev/null 2>&1
UIDR=$(oc get ns $NS -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}')
LO=${UIDR%%/*}; HI=$(( LO + ${UIDR##*/} - 1 ))
echo "  ns=$NS band=$LO..$HI"

say "infra"
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n $NS \
  --set auth.enabled=false --set architecture=standalone \
  --set master.podSecurityContext.enabled=false --set master.containerSecurityContext.enabled=false \
  --wait --timeout 10m >/dev/null 2>&1; echo "  redis rc=$?"
helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n $NS \
  --set auth.postgresPassword=$PGPW --set auth.database=tyk_analytics \
  --set primary.podSecurityContext.enabled=false --set primary.containerSecurityContext.enabled=false \
  --wait --timeout 10m >/dev/null 2>&1; echo "  postgres rc=$?"

say "Step 1 prep — a Secret and a ConfigMap for extraEnvs to resolve from"
oc create secret generic portal-extra -n $NS --from-literal=SECRET_VAL=from-secret-tt17018 \
  --dry-run=client -o yaml | oc apply -n $NS -f - >/dev/null 2>&1
oc create configmap portal-extra -n $NS --from-literal=CM_VAL=from-configmap-tt17018 \
  --dry-run=client -o yaml | oc apply -n $NS -f - >/dev/null 2>&1
echo "  secret/portal-extra + configmap/portal-extra created"

say "install tyk-stack with devPortal=true, opt-out file, and TC-08 overrides"
helm install tyk ./tyk-stack -n $NS --wait --timeout 20m \
  -f ./tyk-stack/ci/no-securitycontext-values.yaml \
  --set global.redis.addrs={redis-master.$NS.svc:6379} \
  --set global.postgres.host=tyk-postgres-postgresql.$NS.svc \
  --set global.postgres.password=$PGPW \
  --set global.postgres.database=tyk_analytics \
  --set global.license.dashboard=$LIC \
  --set global.components.devPortal=true \
  --set tyk-dev-portal.license=$LIC \
  --set-json 'tyk-dev-portal.extraEnvs=[{"name":"QA_FROM_SECRET","valueFrom":{"secretKeyRef":{"name":"portal-extra","key":"SECRET_VAL"}}},{"name":"QA_FROM_CM","valueFrom":{"configMapKeyRef":{"name":"portal-extra","key":"CM_VAL"}}},{"name":"QA_PLAIN","value":"plain-still-works"}]' \
  > $E/live-install.log 2>&1
echo "  install rc=$?"; tail -4 $E/live-install.log
oc get pods -n $NS -o wide 2>/dev/null | tee $E/live-pods.txt

PP=$(oc get pods -n $NS -o name 2>/dev/null | grep -i portal | grep -v bootstrap | head -1)
say "Step 1 — extraEnvs resolve AT RUNTIME (render alone does not prove resolution)"
if [ -n "$PP" ]; then
  echo "portal pod: ${PP#pod/}"
  oc exec -n $NS $PP -- sh -c 'echo "QA_FROM_SECRET=$QA_FROM_SECRET"; echo "QA_FROM_CM=$QA_FROM_CM"; echo "QA_PLAIN=$QA_PLAIN"' 2>/dev/null | tee $E/step1-runtime-env.txt \
    || echo "  (no shell in image — falling back to the resolved references)"
  oc get $PP -n $NS -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{.valueFrom.secretKeyRef.name}{.valueFrom.configMapKeyRef.name}/{.valueFrom.secretKeyRef.key}{.valueFrom.configMapKeyRef.key}{"\n"}{end}' 2>/dev/null | grep QA_ | tee -a $E/step1-runtime-env.txt
else echo "  no portal pod found"; fi

say "Step 6 — PVC bound and WRITABLE under the opt-out (fsGroup comes from the SCC)"
oc get pvc -n $NS 2>/dev/null | tee $E/step6-pvc.txt
if [ -n "$PP" ]; then
  echo "  fsGroup on portal pod: $(oc get $PP -n $NS -o jsonpath='{.spec.securityContext.fsGroup}')"
  echo "  scc:                   $(oc get $PP -n $NS -o jsonpath='{.metadata.annotations.openshift\.io/scc}')"
  MP=$(oc get $PP -n $NS -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="tyk-dev-portal-storage")].mountPath}' 2>/dev/null)
  [ -z "$MP" ] && MP=$(oc get $PP -n $NS -o jsonpath='{.spec.containers[0].volumeMounts[0].mountPath}' 2>/dev/null)
  echo "  mount path:            ${MP:-<none>}"
  oc exec -n $NS $PP -- sh -c "touch ${MP:-/tmp}/tt17018-write-probe && echo WRITE_OK && ls -ln ${MP:-/tmp}/tt17018-write-probe && rm -f ${MP:-/tmp}/tt17018-write-probe" 2>&1 | tee -a $E/step6-pvc.txt
fi

say "Step 5 — bootstrapJob: overridden image + securityContext disabled"
oc get jobs -n $NS 2>/dev/null | tee $E/step5-jobs.txt
for j in $(oc get jobs -n $NS -o name 2>/dev/null | grep -i bootstrap); do
  echo "--- $j ---"
  oc get $j -n $NS -o jsonpath='image={.spec.template.spec.containers[0].image}{"\n"}podSC={.spec.template.spec.securityContext}{"\n"}ctrSC={.spec.template.spec.containers[0].securityContext}{"\n"}completions={.status.succeeded}{"\n"}' 2>/dev/null
done | tee -a $E/step5-jobs.txt
echo "portal bootstrap pods and their SCC:"
oc get pods -n $NS -o jsonpath='{range .items[*]}{.metadata.name}{"  scc="}{.metadata.annotations.openshift\.io/scc}{"  phase="}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -i bootstrap | tee -a $E/step5-jobs.txt

say "summary"
oc get pods -n $NS --no-headers 2>/dev/null
echo "not Running/Completed: $(oc get pods -n $NS --no-headers 2>/dev/null | grep -vcE 'Running|Completed')"
