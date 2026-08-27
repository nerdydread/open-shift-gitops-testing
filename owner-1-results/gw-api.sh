#!/bin/zsh
# gw-api.sh <namespace> <release> <action> [api_id]
# actions: create <id> | get <id> | proxy <listenpath> | list
NS=$1; REL=$2; ACT=$3; ID=${4:-qa1}
SVC=$(kubectl get svc -n $NS -o name | grep gateway-svc | head -1)
SEC=$(kubectl get secret -n $NS -o name | grep "secrets-.*tyk-gateway" | head -1)
APISECRET=$(kubectl get -n $NS $SEC -o jsonpath='{.data.APISecret}' | base64 -d)
kubectl port-forward -n $NS $SVC 18080:8080 >/dev/null 2>&1 &
PF=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://localhost:18080/hello && break; sleep 1; done
case $ACT in
  create)
    curl -sS -o /tmp/gw-create.json -w 'HTTP %{http_code}\n' -H "x-tyk-authorization: $APISECRET" -H 'Content-Type: application/json' \
      http://localhost:18080/tyk/apis -d "{\"name\":\"qa-tt17018-$ID\",\"api_id\":\"$ID\",\"org_id\":\"1\",
      \"proxy\":{\"listen_path\":\"/$ID/\",\"target_url\":\"http://httpbin.org\",\"strip_listen_path\":true},
      \"auth\":{\"auth_header_name\":\"Authorization\"},\"use_keyless\":true,\"version_data\":{\"not_versioned\":true,
      \"versions\":{\"Default\":{\"name\":\"Default\"}}}}"
    cat /tmp/gw-create.json; echo
    curl -sS -H "x-tyk-authorization: $APISECRET" http://localhost:18080/tyk/reload/group; echo
    sleep 4 ;;
  get)
    curl -sS -o /dev/stdout -w '\nHTTP %{http_code}\n' -H "x-tyk-authorization: $APISECRET" http://localhost:18080/tyk/apis/$ID | head -c 300; echo ;;
  list)
    curl -sS -H "x-tyk-authorization: $APISECRET" http://localhost:18080/tyk/apis | jq -r '.[].api_id' ;;
  proxy)
    curl -sS -o /dev/null -w "proxy /$ID/ -> HTTP %{http_code}\n" http://localhost:18080/$ID/get ;;
  health)
    curl -sS -o /dev/null -w "hello -> HTTP %{http_code}\n" http://localhost:18080/hello ;;
esac
kill $PF 2>/dev/null
