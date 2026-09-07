#!/bin/zsh
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc08
DP=(--set global.components.devPortal=true --set tyk-dev-portal.storage.type=s3)

s3env(){ helm template t ./tyk-stack "$@" 2>/dev/null \
  | yq 'select(.kind=="StatefulSet" or .kind=="Deployment") | select(.metadata.name|test("portal")) | .spec.template.spec.containers[0].env | map(select(.name|test("PORTAL_S3_AWS")))' 2>/dev/null; }

echo "########## TC-08 Step 3 — tier 1: secretRef.name set, WITH useSecretName also set ##########"
echo "(proves secretRef takes precedence — the Crossplane case)"
s3env $DP \
  --set tyk-dev-portal.useSecretName=legacy-portal-secret \
  --set tyk-dev-portal.storage.s3.secretRef.name=crossplane-s3 \
  --set tyk-dev-portal.storage.s3.secretRef.accessKeyIdKey=CROSSPLANE_AKID \
  --set tyk-dev-portal.storage.s3.secretRef.secretAccessKeyKey=CROSSPLANE_SAK \
  | tee $E/step3-tier1-secretref.yaml
echo "--- assertions ---"
f=$E/step3-tier1-secretref.yaml
grep -q 'crossplane-s3'   $f && echo "  [ok]   secretRef.name wins over useSecretName" || echo "  [FAIL] secretRef.name not used"
grep -q 'CROSSPLANE_AKID' $f && echo "  [ok]   custom accessKeyIdKey used"             || echo "  [FAIL] custom accessKeyIdKey missing"
grep -q 'CROSSPLANE_SAK'  $f && echo "  [ok]   custom secretAccessKeyKey used"         || echo "  [FAIL] custom secretAccessKeyKey missing"
grep -q 'legacy-portal-secret' $f && echo "  [FAIL] useSecretName leaked into S3 keys" || echo "  [ok]   useSecretName correctly superseded"

echo "\n########## TC-08 Step 4 — tier 2: secretRef.name EMPTY, useSecretName set ##########"
s3env $DP --set tyk-dev-portal.useSecretName=legacy-portal-secret | tee $E/step4-tier2-fallback.yaml
echo "--- assertions ---"
f=$E/step4-tier2-fallback.yaml
grep -q 'legacy-portal-secret' $f && echo "  [ok]   falls back to useSecretName"        || echo "  [FAIL] no fallback"
grep -q 'DevPortalAwsAccessKeyId' $f && echo "  [ok]   default key names restored"      || echo "  [FAIL] default keys missing"
echo "  null keys: $(grep -cE ':[[:space:]]*null[[:space:]]*$' $f)"
echo "  empty name/key: $(yq 'map(select(.valueFrom.secretKeyRef.name=="" or .valueFrom.secretKeyRef.key=="")) | length' $f)"

echo "\n########## TC-08 Step 4b — tier 3: neither set (chart's own secret) ##########"
s3env $DP | tee $E/step4-tier3-default.yaml
f=$E/step4-tier3-default.yaml
grep -q 'secrets-' $f && echo "  [ok]   falls back to the chart's own secret" || echo "  [FAIL] no chart-secret fallback"
echo "  null keys: $(grep -cE ':[[:space:]]*null[[:space:]]*$' $f)"
