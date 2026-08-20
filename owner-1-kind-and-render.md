# Owner 1 — kind & render

**Effort:** ~4 days · **Clusters:** kind (`v1.26.13` and `v1.30.0`) + local only · **You never touch OpenShift.**
**Test cases:** TC-04 Steps 1–3, TC-09, TC-10, TC-01, TC-02, TC-06 Steps 1–5, TC-11, TC-12

Read [`00-shared-setup.md`](00-shared-setup.md) first (~15 min). Master plan for background:
[`../TT-17018-test-plan.md`](../TT-17018-test-plan.md).

---

## What you own

You own **the largest untested risk on this ticket**. Nothing in CI has ever upgraded from a
previously-released chart version — CI's "upgrade" jobs upgrade the branch chart onto itself with
`--reuse-values`. The headline change here (removing container-level `runAsUser` while keeping
`runAsNonRoot: true`, safe *only* because default image tags were bumped) has **zero automated
coverage**. That is TC-01 and TC-02, and it is your day 2–3.

You also own the counterintuitive half of the risk: every regression CI actually caught on this
ticket was a **vanilla-Kubernetes** failure, not an OpenShift one. TC-11 exists because the
OpenShift work kept breaking the 99% of users who aren't on OpenShift.

### Sign-off gates you hold

| §6 row | Item | Yours |
|---|---|---|
| 1 | TC-01 on 1.26 + 1.30, three umbrellas, ± `--reuse-values` | ✅ sole |
| 2 | TC-02 documented + pinned-old-tag decision made | ✅ you run it; team decides |
| 4 | Three `ci/no-securitycontext-values.yaml` **authored**; gap #9 resolved | ✅ shared — Owner 2 does the installs. **No PR required** |
| 6 | TC-06 incl. the `useSecretName` upgrade regression | ✅ shared — Owner 2 does the live check |
| 9 | TC-09 green **with the anti-vacuity revert check** | ✅ sole |
| 10 | TC-10 zero field leaks under server-side dry-run | ✅ sole |
| 11 | TC-11 green on k8s 1.26 and 1.30 | ✅ sole |
| 12 | TC-12 customer confirms; patch list agreed in writing | ✅ sole |
| 13 | Upgrade release note in the 5.4.0 changelog | ✅ sole — **release deliverable, not a test** |
| 14 | OpenShift docs complete | shared — **release deliverable, not a test**; you supply the tag boundary from TC-02 Step 1 |

Rows 13 and 14 are writing, not validating. They gate the *release*, not the *evidence* — do them
once the testing is done, and don't let them displace it.

### Your day-1 obligations to Owner 2

Owner 2 is **blocked** until you deliver these. Do them before anything else.

1. The three `ci/no-securitycontext-values.yaml` files (TC-04 Step 1)
2. The gap #9 operator verdict (TC-04 Step 3) — Owner 2 may not be able to install
   `tyk-control-plane` at all without it

Time-box to the morning. If gap #9 takes longer, ship the values files and send the verdict later.

---

## Setup

### S1 — Code under test

```bash
git clone https://github.com/TykTechnologies/tyk-charts.git && cd tyk-charts
git rev-parse HEAD    # must equal the SHA pinned on TT-17018
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do helm dependency update ./$u; done
```

**Validates:** that you are testing the shipping artefact. `main` has moved since merge `61e5cf1`
(`462900f`, then reverted by `4e0f1be` for TT-16572). PR-branch results don't count.
**Pass:** SHA matches the pinned one. If not, `git checkout <pinned-sha>`.
**Evidence:** the SHA, recorded once at the top of every result you file.

### S2 — Tooling

```bash
helm version          # 3.18.4 — what the branch was validated on
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v0.7.2
crane version         # TC-02 Step 1 image USER inspection
yq --version          # TC-04 Step 3
kind version
```

### S3 — kind clusters, created serially

You need **two** node versions — the ends of the CI matrix. **Create them one at a time and delete
before the next**; two full Tyk stacks will not co-exist comfortably on a laptop.

```bash
kind create cluster --name tyk-qa-126 --image kindest/node:v1.26.13
# ... run TC-01/TC-02/TC-06/TC-10/TC-11 against it, then:
# kind delete cluster --name tyk-qa-126
kind create cluster --name tyk-qa-130 --image kindest/node:v1.30.0
```

Only if 1.26 and 1.30 **disagree** do you need the middle versions, and then only to bisect:
`kindest/node:v1.27.10`, `v1.28.6`, `v1.29.4`.

**Validates:** the two ends of the CI matrix. The earlier regressions on this ticket — emptyDir
ownership (`aac23c3`) and init-container UID mismatch (`e92f013`) — spanned 1.26–1.30, which is why
both ends matter and why TC-11 walks the middle.
**Pass:** `kubectl get nodes` reports the expected `v1.x` server version for each cluster you
create. A silently-defaulted node image invalidates every version-specific result below.
**Evidence:** `kubectl version --short` per cluster, recorded once alongside the results from it.

### S4 — Redis and PostgreSQL ⚠️ not in the master plan

**The master plan's install commands assume Redis already exists and never install it.** Gap #8
notes Redis and PostgreSQL are separate releases, not chart dependencies. On kind that's just a
missing step — do this in every namespace before any Tyk install:

```bash
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk --create-namespace \
  --set auth.enabled=false --set architecture=standalone --wait
# service becomes redis-master.tyk.svc:6379 — matches the --set in every TC command below

# tyk-stack and tyk-control-plane also need PostgreSQL:
helm install postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n tyk \
  --set auth.postgresPassword=topsecretpassword --set auth.database=tyk_analytics --wait
```

**Note:** on OpenShift this same step is a hard blocker rather than an omission — bitnami pins
UID/GID `1001`, outside the namespace range. That's Owner 2's problem, not yours, but it's the same
root cause and it feeds §8 Q2.

### S5 — Licences

TC-01's `tyk-stack` leg, and TC-02, need a dashboard licence. Confirm on day 0 how many concurrent
dashboard installs your licence allows — you and Owner 2 may both want one on day 2–3.

---

## Day 1 (AM) — Owner 2's unblock, first

### TC-04 Step 1 · Author the three missing opt-out values files

`ci/no-securitycontext-values.yaml` exists only for `tyk-oss`, and covers only gateway, pump and the
helm-test pod — because that's all `tyk-oss` contains. Dashboard, dev-portal, MDCB, operator and
bootstrap opt-outs have **never been installed anywhere**, only rendered. That's gap #3, the largest
single hole in the coverage, and it can't be closed until these files exist.

Write one per umbrella: `tyk-control-plane`, `tyk-stack`, `tyk-data-plane`. Keys read from the
merged umbrella `values.yaml` files:

```yaml
# tyk-control-plane/ci/no-securitycontext-values.yaml
tyk-gateway:
  gateway:
    securityContext: {enabled: false}
    containerSecurityContext: {enabled: false}
    initContainers:
      setupDirectories:
        securityContext: {enabled: false}
tyk-dashboard:
  dashboard:
    securityContext: {enabled: false}
    containerSecurityContext: {enabled: false}
    initContainers:
      initAnalyticsConf:
        securityContext: {enabled: false}
tyk-pump:
  pump:
    securityContext: {enabled: false}
    containerSecurityContext: {enabled: false}
tyk-mdcb:
  mdcb:
    podSecurityContext: {enabled: false}
    containerSecurityContext: {enabled: false}
tyk-bootstrap:
  bootstrap:
    securityContext: {enabled: false}
    containerSecurityContext: {enabled: false}
tyk-dev-portal:
  securityContext: {enabled: false}
  containerSecurityContext: {enabled: false}
  bootstrapJob:
    securityContext: {enabled: false}
    containerSecurityContext: {enabled: false}
tyk-operator:
  managerPodSecurityContext: {enabled: false}   # NOT podSecurityContext — see Step 3
```

Then trim per umbrella to the components it actually contains.

⚠️ **`enabled: false`, never `securityContext: {}`.** Helm deep-merges the component defaults back
in, so `{}` is a silent no-op that produces a false pass. If a later test passes unexpectedly, check
this first.

⚠️ **The gateway init container needs BOTH blocks disabled, not just its own.** The chart documents
this explicitly in `components/tyk-gateway/values.yaml`: setting `enabled: false` on
`initContainers.setupDirectories.securityContext` does **not** omit the block — the template *falls
back* to `gateway.containerSecurityContext`, which asserts `runAsNonRoot: true` and pins no UID.

That fallback is what lets an OpenShift SCC assign a UID, so it's deliberate. But
`busybox:1.32` **has no USER directive** (verified — see TC-02 Step 1c), so on **vanilla
Kubernetes**, where nothing injects a UID, that combination is exactly the admission failure the
chart's comment warns about: `container has runAsNonRoot and image will run as root`.

Practical consequences:
- The values file above is correct **because it disables all three blocks.** Don't "simplify" it by
  dropping the `gateway.containerSecurityContext` line — a partial opt-out is worse than none.
- **TC-04 Step 2's grep only passes if all three are off.** If you see a surviving `runAsUser:`, this
  is the first thing to check.
- **Flag it for TC-11.** A vanilla-k8s user who applies only the init-container opt-out gets a broken
  gateway. Worth confirming whether the docs say so, since it's a plausible thing for a reader to try.

**Key irregularities — do not normalise them:**
- MDCB uses `podSecurityContext`, the operator `managerPodSecurityContext` — not `securityContext`
- dev-portal's blocks sit at the **chart root**, with no `.devPortal` nesting
- `tyk-control-plane` has **no `tests:` block** (no helm-test template); `tyk-oss`, `tyk-stack` and
  `tyk-data-plane` do

**Validates:** gap #3 — that a documented opt-out surface exists at all for the five components
that have only ever been rendered.
**Pass:** three files written, each covering every component in its umbrella.
**Evidence:** the three files, attached to TT-17018 and sent to Owner 2 **before** you continue.

### TC-04 Step 2 · Render and confirm the blocks are gone

```bash
helm template t ./tyk-control-plane -f ./tyk-control-plane/ci/no-securitycontext-values.yaml \
  | grep -nE 'fsGroup:|runAsUser:|enabled:'
```

Repeat for `tyk-stack` and `tyk-data-plane`.

**Validates:** that every block was actually removed, and that no invalid `enabled` field leaked
into the manifest — `enabled` is a synthetic chart flag, not a Kubernetes field.
**Pass:** no `fsGroup:` or `runAsUser:` anywhere; no stray `enabled:` inside a `securityContext`
block.
**Evidence:** the command output per umbrella (empty, or only legitimate unrelated `enabled:` keys).

### TC-04 Step 3 · Verify the operator opt-out — gap #9

```bash
helm template t ./tyk-control-plane --set tyk-operator.podSecurityContext.enabled=false \
  | yq 'select(.metadata.name|test("operator")) | .spec.template.spec.securityContext'
helm template t ./tyk-control-plane --set tyk-operator.managerPodSecurityContext.enabled=false \
  | yq 'select(.metadata.name|test("operator")) | .spec.template.spec.securityContext'
```

**Validates:** a suspected defect, not a known one. `components/tyk-operator/templates/all.yaml:395`
reads `.Values.managerPodSecurityContext` (and `:375` reads `.Values.securityContext`), but all
three umbrellas expose only `tyk-operator.podSecurityContext` — a key the operator's own
`values.yaml` explicitly notes "no template reads". If that's right, an OpenShift user following the
documented umbrella values **cannot opt the operator out at all**.
**Pass:** the **second** command removes the block.
**Fail → raise a defect:** if the **first** command does not remove it, the documented umbrella
surface is dead and the umbrella `values.yaml` needs `managerPodSecurityContext` added. This blocks
§6 row 4 and feeds follow-up §7.6.
**Evidence:** both command outputs side by side, plus your verdict in one sentence. **Send to
Owner 2 immediately** — it determines whether their control-plane install can opt the operator out.

### Where the files live

Keep them on disk and attach them to TT-17018. **No PR is required to validate this** — they are
**inputs** to Owner 2's testing, and `helm install -f <path>` behaves identically whether the file
came from a merged repo or your working copy.

Contributing them upstream is a repo improvement, not validation, and it wouldn't close the CI gap
anyway: CI never runs `ct install` (only `ct lint --all`), and the opt-out install job hardcodes
`./tyk-oss/ci/no-securitycontext-values.yaml` against `tyk-oss` alone — so extra files add no
install coverage without also editing `run-tests.yaml`. Both belong in the §7 follow-ups.

### TC-12 Step 1 · Send the customer request — day 1, hard

**Validates:** that the merged state works on the environment that motivated the ticket. The
customer tested `c99bc03`, which **predates** the final round of fixes — the null keys on
SA/Role/RoleBinding, the `enabled` leak on non-gateway components, and annotation quoting. Their
"works great" report **does not cover what shipped**.

Send them the merged `main` chart, pinned to the SHA from S1, and ask them to deploy on ROSA +
ArgoCD across their three regions. Ask exactly three questions:

- How many of the original **24 Kustomize patches** remain?
- Is the `op: remove` workaround patch for null labels/annotations now removable?
- Are the `fsGroup` and init-UID patches gone with the opt-out?

**Pass:** the remaining patch list contains **only non-Tyk components** (Redis, PostgreSQL), and
the customer explicitly agrees in writing that this is acceptable.
**Evidence:** a patch count, not a sentiment. "Works great" is not a pass signal.

**Set a response deadline and note it on the ticket today.** The last round-trip took roughly a
month (asked June, replied 20 July). If the deadline passes without a reply, trigger the ROSA
contingency (master plan §3.1) rather than letting the release drift. This is §8 Q5 — who owns the
date. It's you; pick it now.

---

## Day 1 (PM) — Static verification

### TC-09 · Regression suite and lint on merged `main` · P1 · ~1 hour

**Step 1 — Run every discovered suite.**
```bash
CHARTS=$(for d in $(find . -path '*/tests/*_test.yaml'); do echo "$d" | sed 's#/tests/[^/]*_test.yaml##'; done | sort -u)
helm unittest $CHARTS
```
**Validates:** render-level correctness across every new value key, on the merged tree rather than
the PR branch.
**Pass:** all green. The branch reported 189/189 across 29 suites / 6 charts — **re-baseline against
current `main`**, don't assert that exact number.
**Evidence:** the pass count and the chart list, against the pinned SHA.

**Step 2 — Lint every chart.**
```bash
for c in $(find . -maxdepth 2 -name Chart.yaml | sed 's#/Chart.yaml##'); do helm lint "$c"; done
```
**Pass:** all 11 charts clean.
**Evidence:** the summary lines.

**Step 3 — Anti-vacuity check. This is the point of TC-09.**

Locally revert one fix — e.g. re-introduce the null `annotations` on
`components/tyk-bootstrap/templates/bootstrap-serviceaccount.yml` — and re-run the suite.

**Validates:** whether the regression tests are real. These tests were written by the same person
who wrote the fix; a test that passes on both the fixed *and* the broken tree is worthless. A green
suite proves nothing until you've seen it go red.
**Pass:** the suite goes **red**, naming the reverted resource.
**Fail:** it stays green → the test is a placebo. Raise it as a defect against the test suite. §6
row 9 explicitly requires this check, so a green-only result does not sign off.
**Evidence:** both runs — green on `main`, red on the reverted tree — and `git diff` of the revert.
Restore the tree afterwards (`git checkout -- <file>`).

**Step 4 — Out of scope: CI discovery config.** The master plan asks you to confirm in a real CI run
log that every chart's suites are now discovered. That validates **CI configuration**, not the chart
— and Step 1 already proves the suites pass. Skip it; note gap #5 for the follow-ups instead
(`tyk-data-plane` has no root-level `tests/`, so the `connectionStringSecret_test.yaml` suite
covering a **data-plane** feature lives under `tyk-stack` — that's §7.3, not a defect).

### TC-10 · Field-leak and API-strictness sweep · P1 · ~2 hours

**Step 1 — Server-side dry-run every umbrella with its opt-out file.**
```bash
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do
  echo "=== $u ==="
  helm template t ./$u -f ./$u/ci/no-securitycontext-values.yaml \
    | kubectl apply --dry-run=server -f - 2>&1 | grep -i 'unknown field' && echo "LEAK in $u"
done
```
**Validates:** Leonid's original finding — `enabled` was implemented only in the gateway; on
dashboard, pump, bootstrap and dev-portal it leaked into the manifest, where the API server hard-
rejects it with `strict decoding error: unknown field "spec.securityContext.enabled"`.
**Pass:** no `unknown field` output for any umbrella.
**Evidence:** full output for all four umbrellas.

⚠️ **Server-side dry-run is mandatory.** Client-side dry-run does **not** perform strict decoding
and will pass regardless — a false-pass trap. Runs fine on kind; no OpenShift needed.
This step consumes the files you wrote this morning, so it must come after TC-04 Step 1.

**Step 2 — Repeat per component, not per block.**

The master plan says all **15 blocks** individually. Trim this to **one pass per component** —
gateway, dashboard, pump, MDCB, dev-portal, operator, bootstrap, and the helm-test pod. The leak was
implemented per component (only the gateway had `enabled` handled correctly), so **the component is
the failure axis**; splitting pod-level from container-level from init-level triples the runs without
adding a distinct way to fail.

**Validates:** that an all-at-once pass isn't masking a leak — if one component's manifest is
rejected first, a leak in another never surfaces.
**Pass:** no `unknown field` for any of the 8.
**Evidence:** an 8-row table: component → result. §6 row 10 is not satisfied by the Step 1 sweep
alone. If any component *does* leak, then split that one into its individual blocks to localise it.

---

## Days 2–3 — The upgrade block

### TC-01 · Upgrade from released chart → 5.4.0, stock values · **P0** · ~4h per umbrella per cluster

**What this validates overall:** that existing customers on stock values survive `helm upgrade`.
The single largest untested risk on this ticket; nothing in CI covers it.

**Scope warning.** The master plan's "~4 hours" reads as one umbrella on one cluster. The full
matrix is 3 umbrellas × 2 clusters — realistically 2 days. If the licence or the clock constrains
you, prioritise in this order and record what you dropped:

1. `tyk-oss` on 1.26.13 **and** 1.30.0 (both ends — mandatory)
2. `tyk-data-plane` on both (customer's actual topology)
3. `tyk-stack` on 1.30.0 only

Do **not** silently drop a leg — §6 row 1 names all three umbrellas, so a partial run is a
documented residual risk that the sign-off meeting has to accept explicitly.

**Step 0 — Install Redis** (S4) into the target namespace.

**Step 1 — Install the last released chart.**
```bash
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ && helm repo update
helm search repo tyk-helm/tyk-oss --versions | head -5   # note the version you install
helm install tyk-oss tyk-helm/tyk-oss -n tyk --create-namespace --wait \
  --set global.redis.addrs={redis-master.tyk.svc:6379}
```
**Validates:** establishes the "before" state — a real customer install on the old chart, carrying
the old container-level `runAsUser: 1000`.
**Pass:** all pods Ready.
**Evidence:** `kubectl get pod -n tyk -o jsonpath='{..securityContext}'` — this is your baseline;
you compare against it in Step 5.

**Step 2 — Create real state.**

Create at least one API and one key through the gateway API:
```bash
# verify names for your release first: kubectl get svc,secret -n tyk
kubectl port-forward -n tyk svc/gateway-svc-tyk-oss-tyk-gateway 8080:8080 &
SECRET=$(kubectl get secret -n tyk secrets-tyk-oss-tyk-gateway -o jsonpath='{.data.APISecret}' | base64 -d)
curl -sS -H "x-tyk-authorization: $SECRET" -H 'Content-Type: application/json' \
  http://localhost:8080/tyk/apis -d '{"name":"qa-tt17018","api_id":"qa1","org_id":"1",
  "proxy":{"listen_path":"/qa/","target_url":"http://httpbin.org","strip_listen_path":true},
  "auth":{"auth_header_name":"Authorization"},"version_data":{"not_versioned":true,
  "versions":{"Default":{"name":"Default"}}}}'
curl -sS -H "x-tyk-authorization: $SECRET" http://localhost:8080/tyk/reload
```
**Validates:** gives the upgrade something to preserve. A clean-slate upgrade **hides** exactly the
file-ownership bugs this change risks — the `file object creation failed, write error` class only
appears when the gateway writes into a directory created under the *old* UID.
**Pass:** `GET /qa/` resolves before the upgrade.
**Evidence:** the API ID you created and a successful proxied response.

**Step 3 — Upgrade without `--reuse-values`.**
```bash
helm upgrade tyk-oss ./tyk-oss -n tyk --wait --timeout 10m \
  --set global.redis.addrs={redis-master.tyk.svc:6379}
```
**Validates:** the default upgrade path, with new chart defaults fully applied — including the
removed container-level `runAsUser` and the bumped image tags.
**Pass:** rollout completes; no pod enters `CreateContainerConfigError`.
**Fail signature:** `container has runAsNonRoot and image will run as root` — the documented upgrade
hazard materialising on the *default* path, which would be a **P0**. Capture the full pod event log
and escalate the same day.
**Evidence:** `kubectl get pods -n tyk` post-upgrade + `kubectl get events -n tyk`.

**Step 4 — Repeat with `--reuse-values` on a fresh install.**

**Validates:** real users do both. `--reuse-values` carries the old values forward, which can leave
a stale `runAsUser: 1000` interacting with the new image tags — a **different** failure surface from
Step 3, not a duplicate of it.
**Pass:** same as Step 3.
**Evidence:** both paths recorded separately. §6 row 1 requires both.

**Step 5 — Verify the UID transition.**
```bash
kubectl get pod -n tyk -l app.kubernetes.io/name=tyk-gateway \
  -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
```
**Validates:** the specific behaviour change this PR introduces on vanilla k8s.
**Pass:** container UID moved `1000 → 65532`, **and** pod-level `fsGroup: 2000` is **retained** —
its removal is what broke k8s 1.26–1.30 and was reverted in `aac23c3`.
**Evidence:** the jsonpath output, compared against your Step 1 baseline.

**Step 6 — Verify volume permissions survived.**
```bash
kubectl logs -n tyk <gateway-pod> -c setup-directories
kubectl get pod -n tyk <gateway-pod> -o jsonpath='{.status.initContainerStatuses[0].state}'
```
**Validates:** that the `setupDirectories` init container can still `mkdir` into the
`/mnt/tyk-gateway` emptyDir. This is precisely the failure `aac23c3` reverted — without pod-level
`fsGroup`, that directory came up `root:root 0755` and the gateway never reached Ready.
**Pass:** init container `terminated` with exit code 0; gateway reaches Ready.
**Evidence:** the init container state and its logs.

**Step 7 — Verify state survived and writes still work.**
```bash
# GET the API created in Step 2 — must still resolve
# POST a NEW API — must return 200
```
**Validates:** the UID-mismatch bug class fixed in `e92f013`. A pre-existing API resolving proves
**reads** work; creating a *new* one proves the gateway can still **write** into directories the
init container made. You need both — reads alone will pass on a broken tree.
**Pass:** both succeed.
**Fail:** HTTP 500 `file object creation failed, write error` is a hard fail.
**Evidence:** both HTTP responses.

**Step 8 — Repeat Steps 1–7 on kind 1.30.0.**
**Validates:** kubelet behaviour around `runAsNonRoot` and `fsGroup` differs across the matrix; the
original regressions spanned 1.26–1.30.
**Pass:** every Step 1–7 criterion holds again on 1.30.0. A pass on 1.26 alone does **not** satisfy
§6 row 1 — it names both versions.
**Evidence:** a per-cluster, per-umbrella result grid. That grid *is* §6 row 1.

### TC-02 · Upgrade with a pinned older image tag · **P0** · ~2 hours

**What this validates overall:** that the known-dangerous upgrade path fails **loudly and exactly
as documented**, rather than silently. **Expect this test to fail** — the point is confirming the
failure is understood, detectable and self-diagnosable by a customer.

**Step 1 — Measure the actual image USER for every default tag.**

⚠️ **The master plan's loop for this step cannot work, for three separate reasons.** It runs
`crane config docker.io/tykio/$img:$tag` over
`tyk-gateway tyk-dashboard tyk-pump tyk-sink portal`, but:

1. **Two repositories don't exist** — there is no `tykio/tyk-pump` and no `tykio/tyk-sink`.
2. **Two components aren't on Docker Hub at all.** The gateway and pump are pulled from
   **`docker.tyk.io`** (Cloudsmith-backed), so hardcoding `docker.io/tykio/` is the wrong registry,
   and the `grep "repository: tykio/$img"` that finds the tag matches nothing for them.
3. **It omits the operator, the three bootstrap images, and every init/sidecar image** — which is
   where the actual non-root risk turned out to live.

**Use this instead. It reads whatever the chart really renders, at whatever registry, so it cannot
drift out of date:**
```bash
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do
  helm template t ./$u 2>/dev/null
done | grep -oE '^[[:space:]]+image:[[:space:]]*.*' | awk '{print $2}' | tr -d '"' | sort -u \
| while read -r img; do
    printf '%-52s USER=' "$img"
    crane config "$img" 2>/dev/null | jq -r '.config.User // "" | if .=="" then "EMPTY (=root)" else . end' \
      || echo "UNREACHABLE — note it, do not skip it"
  done
```
**Validates:** the load-bearing assumption behind the entire `runAsUser` removal. `runAsNonRoot:
true` is only safe if every image that inherits it carries a **numeric** USER.
**Pass:** every image either returns a numeric UID, or is an image that nothing asserts
`runAsNonRoot` over (see the two exceptions below).
**Fail:** an empty USER, or a **symbolic** one like `nonroot` or `curl_user`, on an image that *does*
inherit `runAsNonRoot: true` — kubelet cannot verify a non-numeric user, which is why `e92f013` moved
the umbrellas off `tyk-gateway-ee`.
**Evidence:** the full table. **Send it to Owner 2 and keep it for the docs** — this is the
per-component image-tag boundary §6 row 14 requires.

**Step 1b — Check the gateway's default tag against the non-root bands.**

The gateway's `USER` is **not monotonic across versions** — the non-root change was backported into
the 5.8.x LTS line at v5.8.13 but only reached mainline at v5.13.0, so an entire band of
newer-looking tags still declares root:

| Gateway tag | Declared USER |
|---|---|
| v5.3.0 | absent (implicitly root) |
| v5.3.12, v5.5.0, v5.7.0, v5.8.0, v5.8.10 | **`0` — root** |
| v5.8.13, v5.8.14, v5.8.15 | `65532` |
| **v5.9.0, v5.10.0, v5.11.0, v5.12.0** | **`0` — root** |
| v5.13.0, v5.13.1, v5.14.0 | `65532` |

**✅ This was checked on `main` ahead of the pass — the premise holds.** Verified 2026-08-20 against
`docker.tyk.io` (the registry the chart actually pulls from), with `tyk-oss/Chart.yaml` reading
`version: 5.3.0`:

| Component | Repository (as the chart sets it) | Default tag | USER |
|---|---|---|---|
| Gateway | `docker.tyk.io/tyk-gateway/tyk-gateway` | **v5.13.1** | **`65532`** ✅ safe band |
| Dashboard | `tykio/tyk-dashboard` | v5.13.1 | `65532` |
| Pump | `docker.tyk.io/tyk-pump/tyk-pump` | v1.16.0 | `65532` |
| MDCB | `tykio/tyk-mdcb-docker` | v2.12.0 | `65532` |
| Dev Portal | `tykio/portal` | v1.18.0 | `65532` |
| Operator | `tykio/tyk-operator` | v1.4.2 | `65532:65532` |
| Bootstrap ×3 | `tykio/tyk-k8s-bootstrap-{pre-install,post,pre-delete}` | v2.2.0 | `65532:65532` |
| Gateway init | `busybox` | 1.32 | **EMPTY (=root)** — see Step 1c |
| Portal bootstrap | `curlimages/curl` | 8.8.0 | **`curl_user` (symbolic)** — see Step 1c |
| Operator sidecar | `gcr.io/kubebuilder/kube-rbac-proxy` | v0.15.0 | **not checked** — verify it |

**Re-confirm this against your pinned SHA rather than trusting the table** — it's a desk check that
costs two minutes, and `main` moves.
**Pass:** the gateway's default tag sits in a `65532` row.
**Fail — escalate same day as a P0:** if a future re-pin lands it in the **v5.9–v5.12 band**, the
default image runs as root while the chart asserts `runAsNonRoot: true` and every stock install fails
with `CreateContainerConfigError`.
**Evidence:** the table above, regenerated against your SHA.

**Step 1c — The two images that are *not* numeric, and why only one of them is a risk.**

Both are init/helper images the master plan's TC-02 never looked at.

**`busybox:1.32` (gateway `setupDirectories` init container) — no USER directive at all.** This is
**by design and safe as shipped**: the chart pins `runAsUser: 65532` on the init container
specifically because of it. The chart's own comment says so — *"busybox has no USER directive, so with
the main container's `runAsNonRoot: true` inherited kubelet would reject the init container at
admission"*. **But the fallback is a live trap** — see TC-04 Step 1 below, and check it in TC-11.

**`curlimages/curl:8.8.0` (portal `bootstrapJob`) — symbolic USER `curl_user`.** Currently **inert**,
because `bootstrapJob.securityContext` and `.containerSecurityContext` both render **empty** by
default (`enabled: true` with no fields), so nothing asserts `runAsNonRoot` over it.
→ **Hand to Owner 2 for TC-08 Step 5.** That step deliberately overrides the bootstrapJob image and
securityContext. The moment anyone adds `runAsNonRoot: true` to
`bootstrapJob.containerSecurityContext` without a numeric `runAsUser`, kubelet cannot verify
`curl_user` and the job fails at admission. Worth a docs note either way.
**Evidence:** confirm the rendered bootstrap job still carries no `runAsNonRoot`.

> Minor related trap: `:latest` on gateway, dashboard, pump and MDCB is a stale 2020/2021
> **amd64-only** artifact, and `tykio/portal:latest` doesn't exist at all. Harmless while the charts
> pin versioned tags — it only bites an override that sets `tag: latest`.

> Aside for §8 Q4: `tyk-oss/Chart.yaml` on `main` reads **`version: 5.3.0`** while the fix version is
> Charts 5.4.0 — confirmed, so that open question is real and still needs an answer.

**Step 2 — Install the previous released chart with an old tag pinned.**
```bash
helm install tyk-stack tyk-helm/tyk-stack -n tyk-old --create-namespace --wait \
  --set tyk-dashboard.dashboard.image.tag=v5.4.0
```
**Validates:** that the old chart tolerated old tags, establishing that the *chart*, not the tag, is
what changes behaviour. Note the dashboard's non-root boundary is **v5.5.0**, not 5.0.2 — `crane`
confirms v5.0.2 / v5.1.0 / v5.3.0 / v5.4.0 all report `USER=''`. Tags v5.0.3–v5.4.0 render no init
container and still fail on the main container.
**Pass:** installs successfully (it should — the old chart pinned `runAsUser: 1000`).
**Evidence:** pods Ready on the old chart with the old tag.

**Step 3 — Upgrade to the chart from `main`, keeping the pin.**
```bash
helm upgrade tyk-stack ./tyk-stack -n tyk-old --timeout 10m \
  --set tyk-dashboard.dashboard.image.tag=v5.4.0
```
**Validates:** the exact scenario the release note warns about.
**Expected:** pods fail with `CreateContainerConfigError: container has runAsNonRoot and image will
run as root`.
**Pass criterion is not "it works"** — it is that the observed failure **matches the release note
verbatim**, so a customer hitting it can self-diagnose.
**Evidence:** the verbatim error string and the pod events, quoted next to the release-note text.

**Step 4 — Check the docs actually say this.**
```bash
grep -rn "runAsNonRoot\|CreateContainerConfigError\|upgrade" tyk-stack/README.md components/tyk-dashboard/README.md
```
**Validates:** whether a customer who hits Step 3 can find the answer. An undocumented failure here
becomes a support ticket.
**Pass:** the release note describes the failure, **names the affected tags**, and gives the escape
route (pin `runAsUser` explicitly, or move to a tag with a numeric USER).
**Evidence:** the matching doc text, or a gap list if it's missing — which becomes your §6 row 13
work.

**Step 5 — Escalate the open decision.**
**Validates:** nothing technical — this is the release call. Record the outcome and force §8 Q1:
ship with a release note only, or add a `semverCompare` guard / `NOTES.txt` warning? Sedky raised it
and left it open, and it is the most likely support-ticket generator in 5.4.0.
**Pass:** a decision is made and minuted at the Thursday review. **Do not sign off around this.**
**Evidence:** the decision, with an owner, on TT-17018.

---

## Day 4 — Backwards compatibility and the data-plane secret

### TC-11 · Backwards compatibility on vanilla Kubernetes · **P0** · ~half a day

**What this validates overall:** that the OpenShift work didn't break the 99% of users on vanilla
k8s. **Every regression CI caught on this ticket was a vanilla-k8s failure, not an OpenShift one.**
Do not skip this and do not shorten the matrix.

**Required: the two ends — `v1.26.13` and `v1.30.0`.** The master plan lists all five
(`v1.26.13`, `v1.27.10`, `v1.28.6`, `v1.29.4`, `v1.30.0`). Run the ends first and completely; treat
`v1.27.10`, `v1.28.6` and `v1.29.4` as **optional, only if the ends disagree**.

Why the ends suffice: the failure modes here are emptyDir ownership and init/main UID alignment, which
depend on kubelet's `runAsNonRoot` and `fsGroup` handling. If both ends behave identically there is no
plausible mechanism for a middle version to differ — and if they *do* disagree, the middle three are
exactly how you bisect it. Running all five up front costs a day and, on the evidence, tells you
nothing the ends didn't. Record that you scoped it, so the sign-off meeting accepts it knowingly.

Fresh installs with **stock values** (no opt-out). Run one cluster at a time (S3).

**Step 1 — Gateway init container and emptyDir.**
**Validates:** the `aac23c3` revert — removing pod-level `fsGroup` left `/mnt/tyk-gateway` owned
`root:root 0755`, so `setupDirectories` couldn't `mkdir` and the gateway never reached Ready.
**Pass:** init container exits 0; gateway Ready; `fsGroup: 2000` present in the rendered pod spec.
**Evidence:** init container state + the rendered pod-level securityContext, per k8s version.

**Step 2 — Init/main UID alignment.** Create an API through the gateway.
**Validates:** the `e92f013` fix — an init container at UID 1000 against a main container at UID
65532 produced HTTP 500 `file object creation failed, write error`.
**Pass:** API creation returns 200.
**Evidence:** the HTTP status, per k8s version.

**Step 3 — Dashboard `init-analytics-conf` on the legacy path.** Install with
`dashboard.image.tag` ≤ 5.0.2 so the init container renders.
**Validates:** a regression **this PR introduced and then fixed** — the init container reused
`containerSecurityContext`, which this PR stripped `runAsUser` from, so busybox failed admission
under inherited `runAsNonRoot: true`.
**Pass:** pod admits and starts; the init container has **its own** securityContext with
`runAsUser: 1000`.
**Evidence:** the init container's rendered securityContext, showing it is not inheriting.

**Step 4 — Pump `extraContainers`.** Install with a sidecar defined and
`pump.securityContext.enabled: false`.
**Validates:** `extraContainers` were nested **inside** the `securityContext` conditional, so
sidecars **silently vanished** when it was falsy. Silent disappearance is worse than a crash, which
is why it needs its own explicit test rather than being assumed covered.
**Pass:** the sidecar renders **and runs** with the securityContext disabled.
**Evidence:** `kubectl get pod -o jsonpath='{.spec.containers[*].name}'` showing the sidecar present.

**Step 5 — Pod Security Admission `restricted`.**
```bash
kubectl label ns tyk pod-security.kubernetes.io/enforce=restricted
```
**Validates:** that removing pinned UIDs didn't break PSA — the vanilla-k8s analogue of SCC. This is
the closest you get to Owner 2's TC-03/TC-04 without OpenShift.
**Pass:** all pods admit.
**Evidence:** pods Ready under the label, plus no admission warnings in events.

**Step 6 — `helm test` on each umbrella.**
**Validates:** the umbrella test pods previously pinned `runAsUser: 1000` with no opt-out, so
`helm test` could never pass on OpenShift; they now have an `enabled` flag.
**Pass:** `helm test` passes.
**Evidence:** the test pod result per umbrella.
**⚠️ Known issue — run it twice.** The second run fails with `configmaps ... already exists`: the
test configmap is missing a `hook-delete-policy`. Sedky said he'd raise this separately — **confirm
that ticket exists** rather than filing a duplicate, and decide whether it blocks 5.4.0. Feeds
follow-up §7.5.

### TC-06 Steps 1–5 · Data-plane connection-string secret (ticket TC3) · P1 · ~2 hours

**What this validates overall:** that the MDCB connection string can come from a secret, and —
critically — that adding this **did not break the existing documented setup**. Note the ticket's
original AC named the wrong key: it is `connectionStringSecretName`, deliberately **decoupled** from
`useSecretName`. Owner 2 runs Step 6 (the live check) on their OpenShift cluster.

**Step 1 — Default path: literal value.**
```bash
helm template t ./tyk-data-plane --set global.remoteControlPlane.connectionString="tcp://mdcb:9091" \
  | grep -A4 TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING
```
**Validates:** backwards compatibility — existing users who set a literal string must see no change.
**Pass:** renders `value: "tcp://mdcb:9091"`, no `valueFrom`.
**Evidence:** the rendered env block.

**Step 2 — Secret with the default key.**
```bash
helm template t ./tyk-data-plane --set global.remoteControlPlane.connectionStringSecretName=mdcb-conn \
  | grep -A4 TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING
```
**Validates:** the new feature and its default key fallback.
**Pass:** renders `valueFrom.secretKeyRef` with `name: mdcb-conn` and `key: connectionString`, and
**no literal `value:` alongside it** — both present would be invalid.
**Evidence:** the rendered env block.

**Step 3 — Secret with a custom key.**
```bash
helm template t ./tyk-data-plane --set global.remoteControlPlane.connectionStringSecretName=mdcb-conn \
  --set global.remoteControlPlane.connectionStringSecretKey=myKey \
  | grep -A4 TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING
```
**Validates:** the Crossplane-shaped case where secret keys aren't chart defaults.
**Pass:** `key: myKey`.
**Evidence:** the rendered env block.

**Step 4 — The regression that previously broke installs. Highest-value step here.**

Install the **previous released** data-plane chart configured the documented way — a credentials
secret via `useSecretName` **plus** a literal `connectionString` in values — then upgrade to `main`.

**Validates:** the decoupling decision. Tying `connectionString` to `useSecretName` previously broke
existing installs with `couldn't find key connectionString in Secret` on `helm upgrade`. This is a
real, previously-shipped upgrade break, not a hypothetical.
**Pass:** upgrade succeeds; **no** `couldn't find key connectionString in Secret`.
**Evidence:** the pre-upgrade values, the upgrade output, and gateway logs. §6 row 6 names this
specific regression — the render steps above do not satisfy it.

**Step 5 — Check the pump path too.**
```bash
grep -n "connectionStringSecretName" -A5 components/tyk-pump/templates/deployment-pmp.yaml
```
**Validates:** `deployment-pmp.yaml` carries the same conditional branch as the gateway. Fixing one
and missing the other is the easy mistake.
**Pass:** pump renders `secretKeyRef` under the same conditions as the gateway.
**Evidence:** the matched template lines.

**Hand to Owner 2:** the secret name/key you used, so their Step 6 live check matches your renders.

---

## Day 5 — Close out

- [ ] Consolidate every result against the pinned SHA, in the format in
      [`00-shared-setup.md`](00-shared-setup.md#reporting-results)
- [ ] File defects — prefix `[TT-17018 QA]`, with explicit **blocks 5.4.0: yes/no**
- [ ] Attach the three values files to TT-17018 (no PR needed)
- [ ] Chase TC-12; if the deadline has passed, trigger the ROSA contingency
- [ ] Send Owner 2 the image-USER table for the docs (§6 row 14)
- [ ] Draft the upgrade release note for the 5.4.0 changelog (§6 row 13), using TC-02 Steps 1 and 4 —
      **after** the testing is done
- [ ] Bring to the Thursday review: §8 Q1 (TC-02 guard vs release note), Q4 (chart version reads
      `5.3.0` vs fix version 5.4.0), Q5 (TC-12 deadline), and the gap #9 verdict for Q6

Any **P0** — TC-01 Step 3 failing on the default path, or TC-11 Steps 1–2 failing — escalates the
**same day** and forces §8 Q3: revert `main`, or fix forward before the 5.4.0 cut.

---

## Deliberately not doing — and why

Recorded so the sign-off meeting accepts the scope knowingly, rather than someone finding a gap on
day 5. All of these are in the master plan; none of them validate the change.

| Dropped | Why it isn't required |
|---|---|
| **Opening a PR for the three values files** | They're *inputs*. `helm install -f <path>` behaves the same from a working copy, and merging wouldn't close the CI gap anyway (CI runs `ct lint`, never `ct install`). Repo improvement → §7. |
| **TC-09 Step 4** — confirming CI test discovery in a real run log | Validates CI *configuration*, not the chart. Step 1 already proves the suites pass. |
| **TC-10 Step 2 at 15-block granularity** | Reduced to 8 components. The `enabled` leak was implemented per component, so that's the real failure axis; per-block splitting triples runs with no new failure mode. Split a component only if it fails. |
| **TC-11 on k8s 1.27, 1.28, 1.29** | The two ends exercise the same kubelet behaviour. Kept in reserve as the bisect step if 1.26 and 1.30 disagree. |
| **Re-deriving the image USER audit from scratch** | Already done and recorded in TC-02 Step 1b. You re-confirm the gateway tag against your pinned SHA — two minutes, not an afternoon. |

If any of these turns out to matter mid-week, they're small and additive — pick them up then.
