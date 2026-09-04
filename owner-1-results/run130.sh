#!/bin/zsh
# Full Owner-1 re-run on kind v1.30.0
set -u
cd ~/playground/tt17018-owner1
E=evidence/k130
mkdir -p $E
LIC=$(cat .licence)
say(){ echo; echo "########## $* ##########"; }

say "S3 create kind v1.30.0"
kind create cluster --name tyk-qa-130 --image kindest/node:v1.30.0 2>&1 | tail -3
kubectl config use-context kind-tyk-qa-130
kubectl version 2>/dev/null | tail -1
kubectl get nodes -o wide

say "S4 Redis + PostgreSQL"
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk --create-namespace \
  --set auth.enabled=false --set architecture=standalone --wait --timeout 10m >/dev/null 2>&1
echo "redis exit=$?"
helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n tyk \
  --set auth.postgresPassword=topsecretpassword --set auth.database=tyk_analytics --wait --timeout 10m >/dev/null 2>&1
echo "postgres exit=$?"
kubectl get pods -n tyk

say "TC-10 Step 1 server-side dry-run leak sweep (1.30)"
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do
  printf '%-20s ' $u
  helm template t ./tyk-charts/$u -f ./tyk-charts/$u/ci/no-securitycontext-values.yaml \
    --set global.components.pump=true --set global.components.devPortal=true --set global.components.operator=true \
    | kubectl apply --dry-run=server -f - 2>&1 | grep -i 'unknown field' && echo "LEAK" || echo "clean (no unknown field)"
done

say "TC-01 Steps 1-2 released tyk-oss 5.3.0 + state (ns tyk)"
helm install tyk-oss tyk-helm/tyk-oss --version 5.3.0 -n tyk --wait --timeout 10m \
  --set global.redis.addrs={redis-master.tyk.svc:6379} >/dev/null 2>&1
kubectl rollout status -n tyk deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
kubectl get pod -n tyk -l app=gateway-tyk-oss-tyk-gateway -o jsonpath='BASELINE POD_SC={.items[0].spec.securityContext}{"\n"}BASELINE CTR_SC={.items[0].spec.containers[0].securityContext}{"\n"}BASELINE INIT_SC={.items[0].spec.initContainers[0].securityContext}{"\n"}BASELINE IMAGE={.items[0].spec.containers[0].image}{"\n"}'
./gw-api.sh tyk tyk-oss create pre1
./gw-api.sh tyk tyk-oss proxy pre1

say "TC-01 Step 3 upgrade to main WITHOUT --reuse-values"
helm upgrade tyk-oss ./tyk-charts/tyk-oss -n tyk --wait --timeout 10m \
  --set global.redis.addrs={redis-master.tyk.svc:6379} 2>&1 | grep -E "STATUS|REVISION|Error"
kubectl rollout status -n tyk deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
kubectl get pods -n tyk
GW=$(kubectl get pod -n tyk -l app=gateway-tyk-oss-tyk-gateway -o name | head -1)
kubectl get -n tyk $GW -o jsonpath='POST POD_SC={.spec.securityContext}{"\n"}POST CTR_SC={.spec.containers[0].securityContext}{"\n"}POST INIT_SC={.spec.initContainers[0].securityContext}{"\n"}POST IMAGE={.spec.containers[0].image}{"\n"}POST INIT_EXIT={.status.initContainerStatuses[0].state.terminated.exitCode}{"\n"}'
say "TC-01 Steps 6-7 init container + state/writes"
kubectl get events -n tyk --sort-by=.lastTimestamp | grep -iE "runAsNonRoot|CreateContainerConfigError|Failed" | tail -5
./gw-api.sh tyk tyk-oss get pre1
./gw-api.sh tyk tyk-oss create post1
./gw-api.sh tyk tyk-oss proxy post1
kubectl logs -n tyk $GW --tail=200 2>/dev/null | grep -iE "permission denied|write error" | tail -3

say "TC-01 Step 4 --reuse-values path (ns tyk-ru)"
helm install tyk-oss tyk-helm/tyk-oss --version 5.3.0 -n tyk-ru --create-namespace --wait --timeout 10m \
  --set global.redis.addrs={redis-master.tyk.svc:6379} >/dev/null 2>&1
kubectl rollout status -n tyk-ru deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
helm upgrade tyk-oss ./tyk-charts/tyk-oss -n tyk-ru --wait --timeout 10m --reuse-values 2>&1 | grep -E "STATUS|REVISION|Error"
kubectl rollout status -n tyk-ru deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
GW2=$(kubectl get pod -n tyk-ru -l app=gateway-tyk-oss-tyk-gateway -o name | head -1)
kubectl get -n tyk-ru $GW2 -o jsonpath='RU CTR_SC={.spec.containers[0].securityContext}{"\n"}RU INIT_SC={.spec.initContainers[0].securityContext}{"\n"}RU IMAGE={.spec.containers[0].image}{"\n"}RU READY={.status.containerStatuses[0].ready}{"\n"}'
./gw-api.sh tyk-ru tyk-oss create ru1
./gw-api.sh tyk-ru tyk-oss proxy ru1
kubectl logs -n tyk-ru $GW2 --tail=200 2>/dev/null | grep -iE "permission denied|write error" | tail -3
say "TC-01 Step 4b workaround --reset-then-reuse-values"
helm upgrade tyk-oss ./tyk-charts/tyk-oss -n tyk-ru --wait --timeout 10m --reset-then-reuse-values 2>&1 | grep -E "STATUS|REVISION"
kubectl rollout status -n tyk-ru deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
./gw-api.sh tyk-ru tyk-oss create ru2
./gw-api.sh tyk-ru tyk-oss proxy ru2

say "TC-11 Steps 1-2 stock fresh install of main (ns tyk-11)"
helm install tyk-oss ./tyk-charts/tyk-oss -n tyk-11 --create-namespace --wait --timeout 10m \
  --set global.redis.addrs={redis-master.tyk.svc:6379} >/dev/null 2>&1
kubectl rollout status -n tyk-11 deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
kubectl get pod -n tyk-11 -l app=gateway-tyk-oss-tyk-gateway -o jsonpath='POD_SC={.items[0].spec.securityContext}{"\n"}INIT_SC={.items[0].spec.initContainers[0].securityContext}{"\n"}INIT_EXIT={.items[0].status.initContainerStatuses[0].state.terminated.exitCode}{"\n"}READY={.items[0].status.containerStatuses[0].ready}{"\n"}'
./gw-api.sh tyk-11 tyk-oss create t11a
./gw-api.sh tyk-11 tyk-oss proxy t11a

say "TC-11 Step 5 PSA restricted"
kubectl label ns tyk-11 pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl rollout restart -n tyk-11 deploy/gateway-tyk-oss-tyk-gateway
kubectl rollout status -n tyk-11 deploy/gateway-tyk-oss-tyk-gateway --timeout=300s | tail -1
kubectl get pods -n tyk-11
kubectl get events -n tyk-11 | grep -iE "forbidden|violate|PodSecurity" | tail -3

say "TC-11 Step 6 helm test x3"
for i in 1 2 3; do echo "-- run $i"; helm test tyk-oss -n tyk-11 --timeout 5m 2>&1 | grep -E "TEST SUITE|Phase|already exists|Error"; done
kubectl get pod,configmap -n tyk-11 | grep -i test

say "TC-11 Step 4 pump extraContainers + securityContext disabled"
helm upgrade tyk-oss ./tyk-charts/tyk-oss -n tyk-11 -f /tmp/pump-sidecar.yaml --wait --timeout 10m >/dev/null 2>&1
kubectl rollout status -n tyk-11 deploy/pump-tyk-oss-tyk-pump --timeout=300s | tail -1
kubectl get pod -n tyk-11 -l app=pump-tyk-oss-tyk-pump -o jsonpath='CONTAINERS={.items[0].spec.containers[*].name}{"\n"}READY={.items[0].status.containerStatuses[*].ready}{"\n"}PUMP_POD_SC={.items[0].spec.securityContext}{"\n"}'

say "TC-01 tyk-stack leg (ns tyk-stk, plain upgrade)"
helm install tyk-stack tyk-helm/tyk-stack --version 5.3.0 -n tyk-stk --create-namespace --wait --timeout 12m \
  --set global.redis.addrs={redis-master.tyk.svc:6379} --set global.postgres.host=tyk-postgres-postgresql.tyk.svc \
  --set global.postgres.password=topsecretpassword --set global.license.dashboard=$LIC >/dev/null 2>&1
echo "install exit=$?"; kubectl get pods -n tyk-stk
helm upgrade tyk-stack ./tyk-charts/tyk-stack -n tyk-stk --wait --timeout 12m \
  --set global.redis.addrs={redis-master.tyk.svc:6379} --set global.postgres.host=tyk-postgres-postgresql.tyk.svc \
  --set global.postgres.password=topsecretpassword --set global.license.dashboard=$LIC 2>&1 | grep -E "STATUS|REVISION|Error"
kubectl rollout status -n tyk-stk deploy/gateway-tyk-stack-tyk-gateway --timeout=300s | tail -1
kubectl rollout status -n tyk-stk deploy/dashboard-tyk-stack-tyk-dashboard --timeout=300s | tail -1
kubectl get pods -n tyk-stk
for p in $(kubectl get pod -n tyk-stk -l app=gateway-tyk-stack-tyk-gateway -o name); do kubectl get -n tyk-stk $p -o jsonpath='STK CTR_SC={.spec.containers[0].securityContext}{"\n"}STK INIT_SC={.spec.initContainers[0].securityContext}{"\n"}STK IMAGE={.spec.containers[0].image}{"\n"}'; done
say "helm test on tyk-stack x2"
for i in 1 2; do echo "-- run $i"; helm test tyk-stack -n tyk-stk --timeout 5m 2>&1 | grep -E "TEST SUITE|Phase|already exists|Error"; done

say "FINAL pod inventory"
kubectl get pods -A | grep -vE "kube-system|local-path|kube-node"
echo "RUN130 DONE"
