#!/bin/zsh
# Complete the P0 matrix on kind v1.26.13: control-plane + data-plane-with-real-MDCB legs
set -u
cd ~/playground/tt17018-owner1
LIC=$(cat .licence); MDCB=$(cat .licence-mdcb)
say(){ echo; echo "########## $* ##########"; }

say "create kind v1.26.13"
kind create cluster --name tyk-qa-126b --image kindest/node:v1.26.13 2>&1 | tail -2
kubectl config use-context kind-tyk-qa-126b
kubectl version 2>/dev/null | tail -1

say "redis + postgres"
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk --create-namespace \
  --set auth.enabled=false --set architecture=standalone --wait --timeout 10m >/dev/null 2>&1; echo "redis=$?"
helm install tyk-postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n tyk \
  --set auth.postgresPassword=topsecretpassword --set auth.database=tyk_cp --wait --timeout 10m >/dev/null 2>&1; echo "postgres=$?"
kubectl exec -n tyk tyk-postgres-postgresql-0 -- env PGPASSWORD=topsecretpassword psql -U postgres -c "CREATE DATABASE tyk_cp_ru;" >/dev/null 2>&1

CPSET=(--set global.redis.addrs={redis-master.tyk.svc:6379}
       --set global.postgres.host=tyk-postgres-postgresql.tyk.svc
       --set global.postgres.password=topsecretpassword
       --set global.license.dashboard=$LIC
       --set tyk-mdcb.mdcb.license=$MDCB)

say "TC-01 control-plane: install released 5.3.0 (ns tyk-cp)"
helm install tyk-cp tyk-helm/tyk-control-plane --version 5.3.0 -n tyk-cp --create-namespace --wait --timeout 12m \
  --set global.postgres.database=tyk_cp $CPSET >/dev/null 2>&1; echo "install=$?"
kubectl get pods -n tyk-cp

say "state: create API via dashboard"
AUTH=$(kubectl get secret -n tyk-cp tyk-operator-conf -o jsonpath='{.data.TYK_AUTH}'|base64 -d)
ORG=$(kubectl get secret -n tyk-cp tyk-operator-conf -o jsonpath='{.data.TYK_ORG}'|base64 -d)
kubectl port-forward -n tyk-cp svc/dashboard-svc-tyk-cp-tyk-dashboard 13000:3000 >/dev/null 2>&1 & PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:13000/hello && break; sleep 1; done
curl -sS -o /dev/null -w 'create API -> HTTP %{http_code}\n' -H "Authorization: $AUTH" -H 'Content-Type: application/json' \
  http://localhost:13000/api/apis -d '{"api_definition":{"name":"cp126","slug":"cp126","auth":{"auth_header_name":"Authorization"},"use_keyless":true,"version_data":{"not_versioned":true,"versions":{"Default":{"name":"Default"}}},"proxy":{"listen_path":"/cp126/","target_url":"http://httpbin.org","strip_listen_path":true},"active":true}}'
kill $PF 2>/dev/null

say "TC-01 data-plane vs real MDCB: install released 5.3.0 (ns tyk-dp)"
DPSET=(--set global.redis.addrs={redis-master.tyk.svc:6379}
       --set global.remoteControlPlane.connectionString=mdcb-svc-tyk-cp-tyk-mdcb.tyk-cp.svc:9091
       --set global.remoteControlPlane.orgId=$ORG
       --set global.remoteControlPlane.userApiKey=$AUTH
       --set global.remoteControlPlane.groupID=dp126
       --set global.remoteControlPlane.useSSL=false)
helm install tyk-dp tyk-helm/tyk-data-plane --version 5.3.0 -n tyk-dp --create-namespace --wait --timeout 8m $DPSET >/dev/null 2>&1; echo "install=$?"
GW=$(kubectl get pod -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway -o name|head -1)
for i in $(seq 1 40); do kubectl logs -n tyk-dp $GW --tail=300 2>/dev/null | grep -qE "Detected [1-9]" && break; sleep 3; done
kubectl logs -n tyk-dp $GW --tail=300 2>/dev/null | grep -E "Detected [0-9]+ APIs" | tail -1
SVC=$(kubectl get svc -n tyk-dp -o name | grep gateway-svc|head -1)
kubectl port-forward -n tyk-dp $SVC 18085:8080 >/dev/null 2>&1 & PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:18085/hello && break; sleep 1; done
curl -sS -o /dev/null -w "DP 5.3.0 proxies CP API: /cp126/get -> HTTP %{http_code}\n" http://localhost:18085/cp126/get
kill $PF 2>/dev/null

say "TC-01 CP plain upgrade to main"
helm upgrade tyk-cp ./tyk-charts/tyk-control-plane -n tyk-cp --wait --timeout 12m \
  --set global.postgres.database=tyk_cp $CPSET 2>&1 | grep -E "STATUS|REVISION|Error"
for d in gateway-tyk-cp-tyk-gateway dashboard-tyk-cp-tyk-dashboard mdcb-tyk-cp-tyk-mdcb; do kubectl rollout status -n tyk-cp deploy/$d --timeout=300s | tail -1; done
kubectl get pods -n tyk-cp
kubectl get pods -n tyk-cp -o jsonpath='{range .items[*]}{.metadata.name}: ctrSC={.spec.containers[0].securityContext}{"\n"}{end}'

say "TC-01 DP plain upgrade to main (real MDCB)"
helm upgrade tyk-dp ./tyk-charts/tyk-data-plane -n tyk-dp --wait --timeout 8m $DPSET 2>&1 | grep -E "STATUS|REVISION|Error"
kubectl rollout status -n tyk-dp deploy/gateway-tyk-dp-tyk-gateway --timeout=300s | tail -1
GW=$(kubectl get pod -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway -o name|head -1)
for i in $(seq 1 40); do kubectl logs -n tyk-dp $GW --tail=300 2>/dev/null | grep -qE "Detected [1-9]" && break; sleep 3; done
kubectl port-forward -n tyk-dp $SVC 18085:8080 >/dev/null 2>&1 & PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:18085/hello && break; sleep 1; done
curl -sS -o /dev/null -w "DP main proxies: /cp126/get -> HTTP %{http_code}\n" http://localhost:18085/cp126/get
kill $PF 2>/dev/null

say "TC-01 DP --reuse-values (real MDCB)"
helm upgrade tyk-dp ./tyk-charts/tyk-data-plane -n tyk-dp --wait --timeout 8m --reuse-values 2>&1 | grep -E "STATUS|REVISION|Error"
kubectl rollout status -n tyk-dp deploy/gateway-tyk-dp-tyk-gateway --timeout=300s | tail -1
GW=$(kubectl get pod -n tyk-dp -l app=gateway-tyk-dp-tyk-gateway -o name|head -1)
kubectl get -n tyk-dp $GW -o jsonpath='CTR_SC={.spec.containers[0].securityContext}{"\n"}INIT_SC={.spec.initContainers[0].securityContext}{"\n"}'
for i in $(seq 1 40); do kubectl logs -n tyk-dp $GW --tail=300 2>/dev/null | grep -qE "Detected [1-9]" && break; sleep 3; done
kubectl port-forward -n tyk-dp $SVC 18085:8080 >/dev/null 2>&1 & PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:18085/hello && break; sleep 1; done
curl -sS -o /dev/null -w "DP reuse-values proxies: /cp126/get -> HTTP %{http_code}\n" http://localhost:18085/cp126/get
kill $PF 2>/dev/null
kubectl logs -n tyk-dp $GW --tail=300 2>/dev/null | grep -icE "permission denied|write error"

say "TC-01 CP --reuse-values (ns tyk-cp-ru)"
helm install tyk-cp tyk-helm/tyk-control-plane --version 5.3.0 -n tyk-cp-ru --create-namespace --wait --timeout 12m \
  --set global.postgres.database=tyk_cp_ru $CPSET >/dev/null 2>&1; echo "install=$?"
helm upgrade tyk-cp ./tyk-charts/tyk-control-plane -n tyk-cp-ru --wait --timeout 12m --reuse-values 2>&1 | grep -E "STATUS|REVISION|Error"
for d in gateway-tyk-cp-tyk-gateway dashboard-tyk-cp-tyk-dashboard mdcb-tyk-cp-tyk-mdcb; do kubectl rollout status -n tyk-cp-ru deploy/$d --timeout=300s | tail -1; done
kubectl get pods -n tyk-cp-ru
kubectl get pods -n tyk-cp-ru -o jsonpath='{range .items[*]}{.metadata.name}: ctrSC={.spec.containers[0].securityContext} initSC={.spec.initContainers[0].securityContext}{"\n"}{end}'
AUTH2=$(kubectl get secret -n tyk-cp-ru tyk-operator-conf -o jsonpath='{.data.TYK_AUTH}'|base64 -d)
kubectl port-forward -n tyk-cp-ru svc/dashboard-svc-tyk-cp-tyk-dashboard 13001:3000 >/dev/null 2>&1 & PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:13001/hello && break; sleep 1; done
curl -sS -o /dev/null -w 'CP-RU dashboard create API -> HTTP %{http_code}\n' -H "Authorization: $AUTH2" -H 'Content-Type: application/json' \
  http://localhost:13001/api/apis -d '{"api_definition":{"name":"ru126","slug":"ru126","auth":{"auth_header_name":"Authorization"},"use_keyless":true,"version_data":{"not_versioned":true,"versions":{"Default":{"name":"Default"}}},"proxy":{"listen_path":"/ru126/","target_url":"http://httpbin.org","strip_listen_path":true},"active":true}}'
kill $PF 2>/dev/null
kubectl port-forward -n tyk-cp-ru svc/gateway-svc-tyk-cp-tyk-gateway 18086:8080 >/dev/null 2>&1 & PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:18086/hello && break; sleep 1; done
for i in $(seq 1 25); do CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18086/ru126/get); [ "$CODE" = "200" ] && break; sleep 2; done
echo "CP-RU gateway serves after --reuse-values: /ru126/get -> HTTP $CODE"
kill $PF 2>/dev/null

say "CP opt-out file live on 1.26"
helm upgrade tyk-cp ./tyk-charts/tyk-control-plane -n tyk-cp-ru --wait --timeout 12m \
  -f ./tyk-charts/tyk-control-plane/ci/no-securitycontext-values.yaml \
  --set global.postgres.database=tyk_cp_ru $CPSET 2>&1 | grep -E "STATUS|REVISION|Error"
for d in gateway-tyk-cp-tyk-gateway dashboard-tyk-cp-tyk-dashboard mdcb-tyk-cp-tyk-mdcb; do kubectl rollout status -n tyk-cp-ru deploy/$d --timeout=300s | tail -1; done
kubectl get pods -n tyk-cp-ru -o jsonpath='{range .items[*]}{.metadata.name}: podSC={.spec.securityContext} ctrSC={.spec.containers[0].securityContext}{"\n"}{end}'

say "FINAL inventory (1.26)"
kubectl get pods -A | grep -vE "kube-system|local-path"
echo "RUN126 DONE"
