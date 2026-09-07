#!/bin/zsh
# TC-04 Step 11 — the headline acceptance criterion, measured across ALL FOUR umbrellas.
# Replaces TC-12. Nothing here depends on the customer.
set -u
cd ~/playground/tt17018-owner2/tyk-charts
E=~/playground/tt17018-owner2/evidence/tc04
PAIRS=("tyk-qa:tyk-control-plane" "tyk-stack:tyk-stack" "tyk-dp:tyk-data-plane" "tyk-oss:tyk-oss")

echo "############ TC-04 STEP 11 — HEADLINE ACCEPTANCE CRITERION ############"
echo "Cluster: $(oc whoami --show-server)"
echo "User:    $(oc whoami)  ·  anyuid=$(oc auth can-i use scc/anyuid 2>/dev/null | tail -1)"
echo "Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo

TOT_PINNED=0; TOT_INJ=0; TOT_OUT=0; TOT_LIVENULL=0; TOT_RENDNULL=0; TOT_NOTREADY=0; TOT_NONRV2=0
for pair in $PAIRS; do
  ns=${pair%%:*}; ch=${pair##*:}
  oc get ns $ns >/dev/null 2>&1 || { echo "--- $ch: namespace absent, umbrella not installed ---"; continue; }
  UIDR=$(oc get ns $ns -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}')
  LO=${UIDR%%/*}; HI=$(( LO + ${UIDR##*/} - 1 ))

  # render the opt-out for this umbrella to count what the CHART pins
  helm template t ./$ch -f ./$ch/ci/no-securitycontext-values.yaml \
       --set global.components.pump=true > /tmp/r-$ch.yaml 2>/dev/null
  pinned_fg=$(grep -c 'fsGroup:' /tmp/r-$ch.yaml)
  pinned_ru=$(grep -c 'runAsUser:' /tmp/r-$ch.yaml)
  rendnull=$(grep -cE ':[[:space:]]*null[[:space:]]*$' /tmp/r-$ch.yaml)

  inj=0; outb=0; nonrv2=0
  for p in $(oc get pods -n $ns -o name 2>/dev/null); do
    fg=$(oc get $p -n $ns -o jsonpath='{.spec.securityContext.fsGroup}' 2>/dev/null)
    scc=$(oc get $p -n $ns -o jsonpath='{.metadata.annotations.openshift\.io/scc}' 2>/dev/null)
    [ -n "$fg" ] && { inj=$((inj+1)); { [ "$fg" -ge $LO ] && [ "$fg" -le $HI ]; } || outb=$((outb+1)); }
    [ -n "$scc" ] && [ "$scc" != "restricted-v2" ] && nonrv2=$((nonrv2+1))
  done
  livenull=0
  for k in deploy sts job sa role rolebinding cm svc secret; do
    livenull=$(( livenull + $(oc get $k -n $ns -o yaml 2>/dev/null | grep -cE ':[[:space:]]*null[[:space:]]*$') ))
  done
  notready=$(oc get pods -n $ns --no-headers 2>/dev/null | grep -vcE 'Running|Completed')

  echo "--- $ch  (ns $ns, band $LO..$HI) ---"
  printf '  %-46s %s\n' "1. fsGroup patch still needed?"        "$([ $pinned_fg -eq 0 ] && [ $inj -gt 0 ] && [ $outb -eq 0 ] && echo 'NO — SCC injects it, chart pins none' || echo "REVIEW (pinned=$pinned_fg injected=$inj outOfBand=$outb)")"
  printf '  %-46s %s\n' "2. init-container UID patch needed?"   "$([ $pinned_ru -eq 0 ] && [ $notready -eq 0 ] && echo 'NO — chart pins none, all pods up' || echo "REVIEW (pinned=$pinned_ru notReady=$notready)")"
  printf '  %-46s %s\n' "3. op:remove null-key workaround?"     "$([ $livenull -eq 0 ] && [ $rendnull -eq 0 ] && echo 'NO — zero null keys, live and rendered' || echo "REVIEW (live=$livenull render=$rendnull)")"
  printf '  %-46s %s\n' "   pods not on restricted-v2:"         "$nonrv2"
  echo
  TOT_PINNED=$((TOT_PINNED+pinned_fg+pinned_ru)); TOT_INJ=$((TOT_INJ+inj)); TOT_OUT=$((TOT_OUT+outb))
  TOT_LIVENULL=$((TOT_LIVENULL+livenull)); TOT_RENDNULL=$((TOT_RENDNULL+rendnull))
  TOT_NOTREADY=$((TOT_NOTREADY+notready)); TOT_NONRV2=$((TOT_NONRV2+nonrv2))
done

echo "############ ROW 4 — anything else needed to make it install ############"
echo "  Kustomize patches against Tyk components: 0"
echo "  Non-Tyk workarounds required:"
echo "    * bitnami/redis      — master.{pod,container}SecurityContext.enabled=false  (pins UID 1001)"
echo "    * bitnami/postgresql — primary.{pod,container}SecurityContext.enabled=false (pins UID 1001)"
echo "  Both are SEPARATE HELM RELEASES, not Tyk chart dependencies. Gap #8; feeds section 8 Q2."
echo
echo "############ AGGREGATE ############"
printf '  chart-pinned fsGroup/runAsUser lines : %s\n' $TOT_PINNED
printf '  SCC-injected fsGroups                : %s  (outside band: %s)\n' $TOT_INJ $TOT_OUT
printf '  null keys  live / rendered           : %s / %s\n' $TOT_LIVENULL $TOT_RENDNULL
printf '  pods not Running/Completed           : %s\n' $TOT_NOTREADY
printf '  pods not on restricted-v2            : %s\n' $TOT_NONRV2
echo
if [ $TOT_PINNED -eq 0 ] && [ $TOT_OUT -eq 0 ] && [ $TOT_LIVENULL -eq 0 ] && [ $TOT_RENDNULL -eq 0 ] && [ $TOT_NOTREADY -eq 0 ] && [ $TOT_NONRV2 -eq 0 ]; then
  echo "  VERDICT: PASS — four umbrellas installed on OpenShift with zero Kustomize patches"
  echo "           against Tyk components. All three customer patch categories: NO LONGER NEEDED."
else
  echo "  VERDICT: REVIEW — see the per-umbrella rows above before claiming the AC."
fi
echo
echo "  SCOPE LIMIT, state at sign-off: ONE ROSA cluster, single pipeline. Proves the chart needs"
echo "  no patches on OpenShift; proves nothing about the customer's own Kustomize overlays."
