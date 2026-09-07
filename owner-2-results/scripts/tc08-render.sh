#!/bin/zsh
# TC-08 Steps 2-4 — dev portal render assertions (no cluster needed).
# Portal renders via tyk-stack with global.components.devPortal=true.
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc08
DP=(--set global.components.devPortal=true)

# pull the portal's container env block out of a tyk-stack render
portal_env(){ helm template t ./tyk-stack "$@" 2>/tmp/e.txt \
  | yq 'select(.kind=="Deployment" or .kind=="StatefulSet") | select(.metadata.name|test("portal")) | .spec.template.spec.containers[0].env' 2>/dev/null; }

echo "########## TC-08 Step 2 — extraEnvs with plain value: (backwards compat) ##########"
portal_env $DP --set-json 'tyk-dev-portal.extraEnvs=[{"name":"QA_PLAIN_ENV","value":"tt17018"},{"name":"QA_SECOND","value":"still-works"}]' \
  > $E/step2-extraenvs.yaml
grep -A1 'QA_PLAIN_ENV\|QA_SECOND' $E/step2-extraenvs.yaml
n=$(grep -c 'QA_PLAIN_ENV\|QA_SECOND' $E/step2-extraenvs.yaml)
[ "$n" -ge 2 ] && echo "-> PASS: both plain-value entries render unchanged" || echo "-> FAIL: only $n rendered"

echo "\n########## TC-08 Step 3 — s3.secretRef custom keys + precedence over useSecretName ##########"
portal_env $DP \
  --set tyk-dev-portal.useSecretName=legacy-portal-secret \
  --set tyk-dev-portal.storage.s3.secretRef.name=crossplane-s3 \
  --set tyk-dev-portal.storage.s3.secretRef.accessKeyIdKey=CROSSPLANE_AKID \
  --set tyk-dev-portal.storage.s3.secretRef.secretAccessKeyKey=CROSSPLANE_SAK \
  > $E/step3-secretref.yaml
echo "--- S3 credential env entries ---"
yq 'map(select(.name|test("(?i)aws|s3")))' $E/step3-secretref.yaml
echo "--- assertions ---"
grep -q 'crossplane-s3'    $E/step3-secretref.yaml && echo "  [ok] secretRef.name used (crossplane-s3)"       || echo "  [FAIL] secretRef.name not used"
grep -q 'CROSSPLANE_AKID'  $E/step3-secretref.yaml && echo "  [ok] custom accessKeyIdKey used"                 || echo "  [FAIL] custom accessKeyIdKey not used"
grep -q 'CROSSPLANE_SAK'   $E/step3-secretref.yaml && echo "  [ok] custom secretAccessKeyKey used"             || echo "  [FAIL] custom secretAccessKeyKey not used"
if grep -q 'legacy-portal-secret' $E/step3-secretref.yaml; then
  echo "  [note] legacy-portal-secret still referenced — checking it is NOT for the S3 keys:"
  yq 'map(select(.valueFrom.secretKeyRef.name=="legacy-portal-secret") | .name)' $E/step3-secretref.yaml | head -20
else echo "  [ok] useSecretName fully superseded for S3"; fi

echo "\n########## TC-08 Step 4 — fallback chain, secretRef.name empty ##########"
portal_env $DP --set tyk-dev-portal.useSecretName=legacy-portal-secret > $E/step4-fallback.yaml
echo "--- S3 credential env entries ---"
yq 'map(select(.name|test("(?i)aws|s3")))' $E/step4-fallback.yaml
echo "--- assertions ---"
grep -q 'legacy-portal-secret' $E/step4-fallback.yaml && echo "  [ok] falls back to useSecretName" || echo "  [FAIL] no fallback"
nulls=$(grep -cE ':[[:space:]]*null[[:space:]]*$' $E/step4-fallback.yaml)
echo "  null keys in portal env: $nulls  $([ "$nulls" -eq 0 ] && echo '[ok]' || echo '[FAIL]')"
empt=$(yq 'map(select(.valueFrom.secretKeyRef.name=="" or .valueFrom.secretKeyRef.key=="")) | length' $E/step4-fallback.yaml 2>/dev/null)
echo "  empty secretKeyRef entries: ${empt:-0}  $([ "${empt:-0}" -eq 0 ] && echo '[ok]' || echo '[FAIL]')"
