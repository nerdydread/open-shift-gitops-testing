#!/bin/zsh
# stack-leg.sh <ns> <db> <upgrade-flag>
NS=$1; DB=$2; FLAG=$3
cd ~/playground/tt17018-owner1
LIC=$(cat .licence)
COMMON=(--set global.redis.addrs={redis-master.tyk.svc:6379}
        --set global.postgres.host=tyk-postgres-postgresql.tyk.svc
        --set global.postgres.password=topsecretpassword
        --set global.postgres.database=$DB
        --set global.license.dashboard=$LIC)
echo "### [$NS] install released tyk-stack 5.3.0"
helm install tyk-stack tyk-helm/tyk-stack --version 5.3.0 -n $NS --create-namespace --wait --timeout 12m $COMMON >/dev/null 2>&1
echo "exit=$?"; kubectl get pods -n $NS
echo "### [$NS] baseline gateway securityContext"
kubectl get pod -n $NS -l app=gateway-tyk-stack-tyk-gateway -o jsonpath='POD_SC={.items[0].spec.securityContext}{"\n"}CTR_SC={.items[0].spec.containers[0].securityContext}{"\n"}INIT_SC={.items[0].spec.initContainers[0].securityContext}{"\n"}IMAGE={.items[0].spec.containers[0].image}{"\n"}'
echo "### [$NS] upgrade to main with flag: ${FLAG:-none}"
if [ -n "$FLAG" ]; then
  helm upgrade tyk-stack ./tyk-charts/tyk-stack -n $NS --wait --timeout 12m $FLAG 2>&1 | grep -E "STATUS|REVISION|Error"
else
  helm upgrade tyk-stack ./tyk-charts/tyk-stack -n $NS --wait --timeout 12m $COMMON 2>&1 | grep -E "STATUS|REVISION|Error"
fi
sleep 15
kubectl get pods -n $NS
echo "### [$NS] post-upgrade gateway securityContext"
kubectl get pod -n $NS -l app=gateway-tyk-stack-tyk-gateway -o jsonpath='POD_SC={.items[0].spec.securityContext}{"\n"}CTR_SC={.items[0].spec.containers[0].securityContext}{"\n"}INIT_SC={.items[0].spec.initContainers[0].securityContext}{"\n"}IMAGE={.items[0].spec.containers[0].image}{"\n"}INIT_EXIT={.items[0].status.initContainerStatuses[0].state.terminated.exitCode}{"\n"}'
echo "### [$NS] gateway log errors (permission/write):"
kubectl logs -n $NS -l app=gateway-tyk-stack-tyk-gateway --tail=200 2>/dev/null | grep -iE "permission denied|write error|error" | tail -8
echo "### [$NS] dashboard status:"
kubectl get pod -n $NS -l app=dashboard-tyk-stack-tyk-dashboard -o jsonpath='{.items[0].status.phase} {.items[0].status.containerStatuses[0].ready}{"\n"}'
