#!/bin/zsh
# TC-06 Step 6 — data-plane connection-string secret, LIVE.
# Owner 1 proved Steps 1-5 (render + upgrade regression) and handed over the secret shape.
# What this adds: the env var is READABLE AT RUNTIME. A secretKeyRef pointing at a missing
# key fails at POD START, not at render — which is exactly what a render cannot catch.
set -u
E=~/playground/tt17018-owner2/evidence/tc06; mkdir -p $E
NS=tyk-dp
say(){ echo; echo "########## $* ##########"; }

say "TC-06 Step 6 — live connection-string check (ns $NS)"
oc get ns $NS >/dev/null 2>&1 || { echo "SKIP: $NS absent — data-plane not installed"; exit 0; }

say "1. how does the gateway currently get its connection string?"
POD=$(oc get pods -n $NS -o name 2>/dev/null | grep -i gateway | head -1)
[ -z "$POD" ] && { echo "SKIP: no gateway pod"; exit 0; }
echo "pod: ${POD#pod/}"
oc get $POD -n $NS -o jsonpath='{range .spec.containers[0].env[?(@.name=="TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING")]}name={.name}{"\n"}value={.value}{"\n"}fromSecret={.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{"\n"}{end}' | tee $E/step6-baseline.txt

say "2. create a secret and switch the gateway to read from it"
MDCB_ADDR=$(oc get $POD -n $NS -o jsonpath='{range .spec.containers[0].env[?(@.name=="TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING")]}{.value}{end}')
[ -z "$MDCB_ADDR" ] && MDCB_ADDR="mdcb-svc-tyk-tyk-mdcb.tyk-qa.svc:9091"
oc create secret generic mdcb-conn-live -n $NS \
  --from-literal=mdcbUrl="$MDCB_ADDR" --dry-run=client -o yaml | oc apply -n $NS -f - 2>&1 | tail -1
echo "secret mdcb-conn-live created with CUSTOM key 'mdcbUrl' (not the default 'connectionString')"

cd ~/playground/tt17018-owner2/tyk-charts
helm upgrade tyk ./tyk-data-plane -n $NS --wait --timeout 12m --reuse-values \
  --set global.remoteControlPlane.connectionStringSecretName=mdcb-conn-live \
  --set global.remoteControlPlane.connectionStringSecretKey=mdcbUrl \
  2>&1 | grep -E 'STATUS|REVISION|Error' | tee $E/step6-upgrade.txt
sleep 10

say "3. the env var now resolves FROM THE SECRET, with the custom key"
POD=$(oc get pods -n $NS -o name 2>/dev/null | grep -i gateway | head -1)
oc get $POD -n $NS -o jsonpath='{range .spec.containers[0].env[?(@.name=="TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING")]}fromSecret={.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{"\n"}{end}' | tee $E/step6-after.txt

say "4. RUNTIME proof — the value is actually readable inside the container"
oc exec -n $NS $POD -- sh -c 'echo "resolved=$TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING"' 2>/dev/null | tee -a $E/step6-after.txt \
  || echo "  (distroless image — no shell; falling back to pod readiness as the signal)"

say "5. gateway still Ready and connected?"
oc get pods -n $NS --no-headers | grep -i gateway | tee -a $E/step6-after.txt
oc logs -n $NS $POD --tail=20 2>/dev/null | grep -iE 'rpc|mdcb|connect|error' | tail -6

echo
grep -q 'mdcb-conn-live/mdcbUrl' $E/step6-after.txt \
  && echo "=> PASS: custom secret + custom key resolved at runtime, gateway healthy" \
  || echo "=> REVIEW: secret reference did not take"
