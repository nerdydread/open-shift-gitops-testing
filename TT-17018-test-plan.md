# TT-17018 — QA Test & Validation Plan

**Ticket:** [TT-17018] [Innersource] OpenShift with GitOps Support
**Status:** Blocked · **Assignee:** Sedky Abou-Shamalah · **Reporter:** Travis Johnson
**Component:** Tyk Charts · **Fix version:** Tyk Charts 5.4.0 · **Label:** `2026_r4_candidate`
**Code:** `TykTechnologies/tyk-charts` PR #485 — **merged to `main` 27 Jul 2026** as `61e5cf1` (66 files, +4,530/−182). PR #467 is closed/superseded — do not review that diff.
**Version:** 2 (10 Aug 2026) — adds environment decision and step-by-step execution detail

---

## 1. Why this plan exists

The change is already on `main` (chart version `5.3.0`), but Andy Ost flagged on 28 Jul that it was merged before QA sign-off, and Valmir asked on 5 Aug whether QA is the only thing left. This plan defines what an **independent QA pass** has to cover to close that gap and release into Charts 5.4.0.

The honest position: engineering-side validation here is unusually strong. The customer tested on real ROSA, Sedky validated on CRC 4.22.1 as an unprivileged user, and Leonid ran two independent reviews plus a live `restricted-v2` admission probe on the Red Hat Developer Sandbox. QA does **not** need to redo that work. What QA needs to cover is the surface neither the reviews nor CI touched — which is mostly **end-to-end install and upgrade on the umbrella charts the customer actually runs**.

---

## 2. Evidence ledger — what is already proven, and by whom

| Area | Evidence | Who | QA action |
|---|---|---|---|
| SCC rejects the default render (`fsGroup: 2000`, init `runAsUser: 65532`) | Bare-Pod admission probe on real OpenShift, unprivileged, two clusters with different UID ranges | Leonid (Dev Sandbox), Sedky (CRC 4.22.1) | **Spot-check only** — reproduce once |
| `securityContext.enabled: false` opt-out → Pod admitted, SCC injects UID/fsGroup | Same probes, pod reached `Running` under `restricted-v2` | Leonid, Sedky | **Spot-check only** |
| Null `annotations`/`labels` under `disableHelmHooks` (customer's reported bug) | Fixed + regression tests that fail when ported to `main`; 19-permutation sweep, 0 null keys across 4 umbrellas | Leonid re-review | Covered by unit tests — **re-run, don't rebuild** |
| `securityContext.enabled` field leak | Live `kubectl apply --dry-run=server`, all 8 components clean | Leonid | Covered — **re-run** |
| Annotation/label quoting (`sync-wave: -1` as int) | Original API rejection reproduced, then fixed at all 6 loop sites + 3 podLabels sites | Leonid | Covered by unit tests |
| Render-level correctness of every new value key | `helm unittest` 189/189 across 29 suites, `helm lint` 11/11 clean | Both | **Re-run against current `main`** |
| Real ROSA + ArgoCD/Kustomize deployment | Customer report, 20 Jul (on `c99bc03`, i.e. **before** the last round of fixes) | Customer | **Re-confirm on merged `main`** |

### The gaps — this is where QA's effort belongs

Verified against the merged tree, not inferred from the review comments:

1. **No real upgrade test exists anywhere.** CI's "upgrade" steps (`smoke-upgrade-oss`, `smoke-upgrade-data-plane`) upgrade the branch chart onto itself with `--reuse-values --set tyk-gateway.gateway.kind=DaemonSet`. Nothing ever upgrades from a *previously released* chart version. The largest documented risk on this ticket — removing container-level `runAsUser` while retaining `runAsNonRoot: true`, safe only because default image tags were bumped — has **zero automated coverage**. This is QA's #1 job.
2. **`tyk-stack` and `tyk-control-plane` are never installed end-to-end.** `run-tests.yaml` only smoke-installs `tyk-oss` and `tyk-data-plane`. The PR added +133 lines to `tyk-stack/values.yaml` and +124 to `tyk-control-plane/values.yaml`. The customer runs control-plane + data-plane.
3. **The SCC opt-out is only e2e-installed on `tyk-oss`.** `ci/no-securitycontext-values.yaml` exists for that umbrella alone, and covers only gateway, pump and the helm-test pod — because that's all `tyk-oss` contains. **Dashboard, dev-portal, MDCB, operator and bootstrap opt-outs have never been installed**, only rendered and unit-tested.
4. **Bootstrap jobs never actually execute in CI.** Bootstrap belongs to `tyk-stack`/`tyk-control-plane`, which aren't installed. `disableHelmHooks`, `backoffLimit`, `imagePullSecrets`, `preDelete.command` and `rbacAnnotations` are **render-verified only**.
5. **`tyk-data-plane` has no `tests/` directory.** CI's unit-test discovery explicitly skips charts without root-level `tests/*_test.yaml`. The `connectionStringSecret_test.yaml` suite covering TC3 lives under `tyk-stack` — yet the connection-string secret is a **data-plane** feature.
6. **Dev Portal changes have no e2e coverage.** `extraEnvs` with `valueFrom`, `storage.s3.secretRef`, and the configurable `bootstrapJob` are covered by null-key unit tests only. The portal is not installed in any smoke job.
7. **Private-registry bootstrap (an explicit AC) has never been tested** against an actual private registry.
8. **Redis and PostgreSQL are separate releases, not chart dependencies.** bitnami/redis pins `fsGroup`/`runAsUser`/`runAsGroup` to `1001`. The AC "deploys on OpenShift without Kustomize patches" is therefore only true for Tyk's own components.
9. **Suspected: the operator opt-out is not reachable from any umbrella.** `components/tyk-operator/templates/all.yaml` reads `.Values.managerPodSecurityContext` (line 395) and `.Values.securityContext` (line 375), but all three umbrellas expose only `tyk-operator.podSecurityContext` — a pre-existing key the operator's own values.yaml explicitly notes "no template reads". **Verify in TC-04 Step 3.** If confirmed, an OpenShift user following the umbrella values cannot opt the operator out through the documented surface.

---

## 3. Environment strategy

### 3.1 The decision

**Use Developer Sandbox and CRC together. Skip ROSA. Defer MicroShift.**

These are three different jobs, not one choice:

| Option | Verdict | Reasoning |
|---|---|---|
| **Red Hat Developer Sandbox** | ✅ **Use — for TC-03 only** | Free, ~10 min to a login, and its best property is that you *cannot* be privileged. That makes it the most trustworthy evidence source for the one test where accidentally holding `anyuid` silently invalidates the result. Leonid already ran this exact probe on it. |
| **CRC / OpenShift Local** | ✅ **Use — primary workhorse** | The only free option giving you **both** cluster-admin (to install the OpenShift GitOps operator and the tyk-operator CRDs) **and** an unprivileged `developer` user to test as. Sedky has a known-good full-install path on CRC 4.22.1. |
| **ROSA** | ❌ **Skip — contingency only** | You already get real ROSA coverage free via **TC-12**: the customer runs Tyk on ROSA across three AWS regions and has been testing PRs. Paying duplicates their coverage. |
| **MicroShift** | ⏸ **Out of scope for this pass** | It's the §7 follow-up — the permanent CI gate. Different job, different timeline. Folding it in now will slow the release. |

**Why the Sandbox alone isn't enough.** It has no cluster-admin, so you cannot install operators — which rules out TC-05's real ArgoCD instance and anything touching the tyk-operator's CRDs. Pods are also auto-deleted after 12 consecutive hours and the sandbox expires after 30 days, so it can't hold a long-running stack.

**Why CRC needs a hardware check first.** Current CRC docs state a minimum of **4 physical CPU cores, 10.5 GB free memory, 35 GB storage** — and that is for an *idle* cluster. Running four umbrellas plus Redis, PostgreSQL and ArgoCD on top realistically wants ~8–10 cores and 24–32 GB allocated to the VM, so a **32 GB host**. (The "~9 vCPU / 9 GB" figure in v1 of this plan came from Leonid's guide and understates it.) **If QA's machine can't spare that, rent a cloud VM for the week** — still far cheaper than a ROSA cluster.

**The CRC trap.** Unlike the Sandbox, `kubeadmin` is right there on CRC, and a cluster-admin gets `anyuid`, which bypasses `restricted-v2` and makes everything falsely pass. Run the §3.6 privilege gate at the top of **every** CRC session, not once at setup.

**The ROSA contingency.** The risk of skipping ROSA isn't technical, it's schedule: the customer's last round-trip took roughly a month (asked in June, replied 20 July). Mitigation — start TC-12 on **day 1**, set a hard date by which you need their answer, and only spin up a paid cluster if they go quiet past it.

### 3.2 Which cluster runs which test

| Test case | kind | Dev Sandbox | CRC | Customer ROSA |
|---|:--:|:--:|:--:|:--:|
| TC-01 Upgrade from released chart | ● | | | |
| TC-02 Pinned old image tag | ● | | | |
| TC-03 SCC admission probe | | ● | ○ | |
| TC-04 Full install with opt-out | | | ● | |
| TC-05 GitOps / ArgoCD | | | ● | ○ |
| TC-06 Connection-string secret | ● | | ○ | |
| TC-07 Bootstrap job config | ● | | ● | |
| TC-08 Dev Portal config | ● | | ● | |
| TC-09 Unit tests + lint | ● | | | |
| TC-10 Field-leak sweep | ● | | | |
| TC-11 Vanilla-k8s backwards compat | ● | | | |
| TC-12 Customer re-confirmation | | | | ● |

● primary · ○ optional secondary

### 3.3 Set up the Developer Sandbox (for TC-03)

**Step 1 — Provision.** Go to <https://developers.redhat.com/developer-sandbox> → "Start your sandbox for free". You get an unprivileged project automatically.
→ *Testing:* nothing yet — but note the sandbox is active for **30 days** and pods are **auto-deleted after 12 consecutive hours**. Plan TC-03 as a single short session.

**Step 2 — Log in from the CLI.** Console → top-right user menu → "Copy login command" → Display Token → run the `oc login --token=… --server=…` locally.
→ *Note:* tokens are short-lived. Re-copy when they expire; this is normal, not a fault.

**Step 3 — Run the privilege gate** (§3.6). On the Sandbox this should pass by construction.

### 3.4 Set up CRC (for TC-04 through TC-08)

**Step 1 — Check the host has capacity.**
```bash
nproc                      # want >= 8 physical cores
free -g                    # want >= 32 GB total, >= 24 GB free
df -h ~                    # want >= 60 GB free (35 GB minimum + images)
```
→ *Testing:* whether CRC can hold the full stack. If this fails, provision a cloud VM now rather than discovering it mid-install.

**Step 2 — Install and size the cluster.**
```bash
crc setup
crc config set memory 24576      # MB — above the 10.5 GB minimum, the stack needs headroom
crc config set cpus 8
crc config set disk-size 100     # GB
crc start
```
→ *Testing:* nothing functional — but under-sizing here produces `Pending` pods later that look like chart bugs and aren't. Size it correctly first so that every later failure is a real finding.

**Step 3 — Install the OpenShift GitOps operator as `kubeadmin`** (needed for TC-05).
```bash
oc login -u kubeadmin -p "$(crc console --credentials | grep -o "kubeadmin.*'" | cut -d\' -f2)" https://api.crc.testing:6443
oc apply -f - <<'YAML'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: {name: openshift-gitops-operator, namespace: openshift-operators}
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML
oc get csv -n openshift-operators -w   # wait for Succeeded
```
→ *Testing:* nothing in the chart — this is the only step that legitimately needs cluster-admin, which is exactly why the Sandbox can't do TC-05.

**Step 4 — Switch to the unprivileged `developer` user and stay there.**
```bash
oc login -u developer -p developer https://api.crc.testing:6443
oc new-project tyk-qa
```
→ ⚠️ **Every subsequent chart test must run as `developer`.** Testing as `kubeadmin` grants `anyuid` and everything passes falsely.

**Step 5 — Run the privilege gate** (§3.6). This is the step that catches the mistake above.

### 3.5 Set up kind (for TC-01, TC-02, TC-09 through TC-11)

```bash
kind create cluster --name tyk-qa-126 --image kindest/node:v1.26.13
kind create cluster --name tyk-qa-130 --image kindest/node:v1.30.0
```
→ *Testing:* the two ends of the CI matrix. The earlier regressions on this ticket (emptyDir ownership, init-container UID mismatch) were **vanilla-k8s** failures across 1.26–1.30, not OpenShift ones — which is why both ends matter.

### 3.6 The privilege gate — run before every OpenShift session

```bash
oc whoami
oc auth can-i use scc/anyuid        # MUST be: no
oc auth can-i use scc/privileged    # MUST be: no
oc auth can-i '*' '*'               # MUST be: no  (not cluster-admin)
oc get ns "$(oc project -q)" -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
# e.g. 1004340000/10000  ->  allowed UIDs 1004340000-1004349999
```
→ *Testing:* that the SCC results you are about to collect mean anything at all.
→ **If `can-i use scc/anyuid` returns `yes`, stop.** A cluster-admin bypasses `restricted-v2` entirely and every SCC test will pass regardless of the chart's behaviour. Record the UID range — you need it to verify injected values later.

### 3.7 Tooling

```bash
helm version          # 3.18.4 — matches what the branch was validated on
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v0.7.2
oc version
crane version         # for image USER inspection in TC-02
```

### 3.8 Code under test

Test **merged `main`**, not the PR branch — `main` has moved since the merge (`462900f`, then reverted by `4e0f1be` for TT-16572 lifecycle hooks).

```bash
git clone https://github.com/TykTechnologies/tyk-charts.git && cd tyk-charts
git rev-parse HEAD    # record this SHA on TT-17018 — all results are against it
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do helm dependency update ./$u; done
```
→ *Testing:* that you are testing the shipping artefact. Results against the PR branch don't count — the merge and subsequent commits could have changed behaviour.

---

## 4. Test cases

Priority: **P0** = blocks release · **P1** = blocks sign-off, parallelisable · **P2** = note as residual risk if skipped.

---

### TC-01 · Upgrade from released chart → 5.4.0, stock values
**P0 · Cluster: kind (1.26.13 and 1.30.0) · ~4 hours**

**What this proves:** that existing customers on stock values survive `helm upgrade`. This is the single largest untested risk — nothing in CI covers it.

Run the whole sequence for `tyk-oss`, then `tyk-data-plane`, then `tyk-stack` if a licence is available.

**Step 1 — Install the last released chart.**
```bash
helm repo add tyk-helm https://helm.tyk.io/public/helm/charts/ && helm repo update
helm search repo tyk-helm/tyk-oss --versions | head -5   # note the version you install
helm install tyk-oss tyk-helm/tyk-oss -n tyk --create-namespace --wait \
  --set global.redis.addrs={redis-master.tyk.svc:6379}
```
→ *Testing:* establishes the "before" state — a real customer install on the old chart, with the old `runAsUser: 1000` container context.
→ *Pass:* all pods Ready. Record `kubectl get pod -n tyk -o jsonpath='{..securityContext}'` as the baseline.

**Step 2 — Create real state.**
```bash
# create at least one API and one key via the gateway/dashboard API
```
→ *Testing:* gives the upgrade something to preserve. A clean-slate upgrade hides exactly the file-ownership bugs this change risks — the `file object creation failed, write error` class only appears when the gateway writes to a directory created under the *old* UID.
→ *Pass:* API resolves before upgrade.

**Step 3 — Upgrade without `--reuse-values`.**
```bash
helm upgrade tyk-oss ./tyk-oss -n tyk --wait --timeout 10m \
  --set global.redis.addrs={redis-master.tyk.svc:6379}
```
→ *Testing:* the default upgrade path — new chart defaults fully applied, including the removed container-level `runAsUser` and the bumped image tags.
→ *Pass:* rollout completes; no pod enters `CreateContainerConfigError`.
→ *Fail signature:* `container has runAsNonRoot and image will run as root` — this is the documented upgrade hazard materialising. Capture the full pod event log if seen.

**Step 4 — Repeat with `--reuse-values` on a fresh install.**
→ *Testing:* real users do both. `--reuse-values` carries the old values forward, which can leave a stale `runAsUser` interacting with new image tags — a different failure surface from Step 3.
→ *Pass:* same as Step 3.

**Step 5 — Verify the UID transition.**
```bash
kubectl get pod -n tyk -l app.kubernetes.io/name=tyk-gateway \
  -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
```
→ *Testing:* the specific behaviour change this PR introduces on vanilla k8s.
→ *Pass:* container UID has moved `1000 → 65532`; pod-level **`fsGroup: 2000` is retained** (its removal is what broke k8s 1.26–1.30 and was reverted).

**Step 6 — Verify volume permissions survived.**
```bash
kubectl logs -n tyk <gateway-pod> -c setup-directories
kubectl get pod -n tyk <gateway-pod> -o jsonpath='{.status.initContainerStatuses[0].state}'
```
→ *Testing:* that the `setupDirectories` init container can still `mkdir` into the `/mnt/tyk-gateway` emptyDir. This is precisely the failure that commit `aac23c3` reverted.
→ *Pass:* init container `terminated` with exit code 0; gateway reaches Ready.

**Step 7 — Verify state survived and writes still work.**
```bash
# GET the API created in Step 2 — must still resolve
# POST a NEW API — must return 200
```
→ *Testing:* the UID-mismatch bug class fixed in `e92f013`. A pre-existing API resolving proves reads work; creating a *new* one proves the gateway can still write to directories the init container made.
→ *Pass:* both succeed. HTTP 500 `file object creation failed, write error` is a hard fail.

**Step 8 — Repeat Steps 1–7 on the second kind cluster (1.30.0).**
→ *Testing:* kubelet behaviour around `runAsNonRoot` and fsGroup differs across the matrix; the original regressions spanned 1.26–1.30.

---

### TC-02 · Upgrade with a pinned older image tag
**P0 · Cluster: kind · ~2 hours**

**What this proves:** that the known-dangerous upgrade path fails *loudly and as documented*, rather than silently. Expect this test to fail — the point is confirming the failure is understood and detectable.

**Step 1 — Measure the actual image USER for every default tag.**
```bash
for img in tyk-gateway tyk-dashboard tyk-pump tyk-sink portal; do
  tag=$(grep -A2 "repository: tykio/$img" components/*/values.yaml | grep 'tag:' | head -1 | awk '{print $2}')
  echo -n "$img:$tag -> USER="
  crane config docker.io/tykio/$img:$tag | jq -r '.config.User'
done
```
→ *Testing:* the load-bearing assumption behind the whole `runAsUser` removal. `runAsNonRoot: true` is only safe if every default image carries a **numeric** USER.
→ *Pass:* every tag returns a numeric UID (e.g. `65532`).
→ *Fail:* an empty USER, or a **symbolic** one like `nonroot` — kubelet cannot verify a non-numeric user against `runAsNonRoot`, which is why `e92f013` moved the umbrellas off `tyk-gateway-ee`. Check every component, not just the gateway.

**Step 2 — Install the previous released chart with an old tag pinned.**
```bash
helm install tyk-stack tyk-helm/tyk-stack -n tyk-old --create-namespace --wait \
  --set tyk-dashboard.dashboard.image.tag=v5.4.0
```
→ *Testing:* the dashboard's non-root boundary is **v5.5.0**, not 5.0.2 — `crane` confirms v5.0.2 / v5.1.0 / v5.3.0 / v5.4.0 all report `USER=''`. Tags v5.0.3–v5.4.0 render no init container and still fail on the main container.
→ *Pass:* installs successfully on the old chart (it should — the old chart pinned `runAsUser: 1000`).

**Step 3 — Upgrade to the chart from `main`, keeping the pin.**
```bash
helm upgrade tyk-stack ./tyk-stack -n tyk-old --timeout 10m \
  --set tyk-dashboard.dashboard.image.tag=v5.4.0
```
→ *Testing:* the exact scenario the release note warns about.
→ *Expected:* pods fail with `CreateContainerConfigError: container has runAsNonRoot and image will run as root`.
→ *Pass criterion is not "it works"* — it is that the observed failure **matches the release note verbatim**, so a customer hitting it can self-diagnose.

**Step 4 — Check the docs actually say this.**
```bash
grep -rn "runAsNonRoot\|CreateContainerConfigError\|upgrade" tyk-stack/README.md components/tyk-dashboard/README.md
```
→ *Testing:* whether a customer who hits Step 3 can find the answer. An undocumented failure here becomes a support ticket.
→ *Pass:* the release note describes the failure, names the affected tags, and gives the escape route (pin `runAsUser` explicitly, or move to a tag with a numeric USER).

**Step 5 — Escalate the open decision.** Record the outcome and force the call in §8: release note only, or add a `semverCompare` guard / `NOTES.txt` warning? Sedky raised it and left it open. Do not sign off around this.

---

### TC-03 · SCC admission probe on real OpenShift
**P0 (confirmation run) · Cluster: Developer Sandbox · ~30 minutes**

**What this proves:** that the default chart context is genuinely rejected by `restricted-v2`, and the opt-out is genuinely admitted. Already proven twice by Leonid and Sedky — QA reproduces once to own the evidence independently.

**Step 1 — Run the privilege gate** (§3.6) and record the namespace UID range.
→ *Testing:* that this whole test case is meaningful. Skipping this is the single most common way to produce a worthless pass.

**Step 2 — Probe the DEFAULT chart context. Must be REJECTED.**
```bash
NS=$(oc project -q)
cat <<'YAML' | oc apply -n "$NS" --dry-run=server -f -
apiVersion: v1
kind: Pod
metadata: {name: scc-probe-default}
spec:
  securityContext: {fsGroup: 2000, runAsNonRoot: true}
  initContainers: [{name: init, image: busybox:1.36, command: ["true"], securityContext: {runAsUser: 65532, runAsNonRoot: true}}]
  containers:     [{name: main, image: busybox:1.36, command: ["sleep","1"]}]
YAML
```
→ *Testing:* that the chart's stock render is incompatible with `restricted-v2` for **two independent reasons** — this is the problem statement of the entire ticket.
→ *Pass:* rejected citing **both** `fsGroup: Invalid value: [2000]: 2000 is not an allowed group` **and** `initContainers[0].runAsUser: Invalid value: 65532: must be in the ranges: [<your range>]`.
→ *Note:* a bare Pod is required. SCC is evaluated at **Pod admission** — rendering or applying a Deployment proves nothing, because the Deployment is admitted and only its Pods are rejected.

**Step 3 — Isolate each cause.** Apply the same Pod twice more: once with only `fsGroup: 2000`, once with only the init `runAsUser: 65532`.
→ *Testing:* that both fields fail independently, so the fix has to address both. Confirms the diagnosis rather than assuming it.
→ *Pass:* each is rejected on its own, citing only its own field.

**Step 4 — Probe the OPT-OUT context. Must be ADMITTED.**
```bash
cat <<'YAML' | oc apply -n "$NS" -f -
apiVersion: v1
kind: Pod
metadata: {name: scc-probe-optout}
spec:
  containers: [{name: main, image: busybox:1.36, command: ["sleep","30"]}]
YAML
oc get pod scc-probe-optout -n "$NS" \
  -o jsonpath='scc={.metadata.annotations.openshift\.io/scc} fsGroup={.spec.securityContext.fsGroup}{"\n"}'
oc delete pod scc-probe-optout -n "$NS"
```
→ *Testing:* that omitting the block entirely — what `securityContext.enabled: false` produces — lets the SCC do its job.
→ *Pass:* pod admitted, `scc=restricted-v2`, and OpenShift has **injected** an `fsGroup` inside your namespace range. Pod reaches `Running`.
→ *This is the end-to-end proof:* rejected default → admitted opt-out → SCC fills a valid UID/GID.

---

### TC-04 · Full install with the opt-out, per umbrella
**P0 · Cluster: CRC · ~1.5 days**

**What this proves:** that the opt-out works for real, on the components that have only ever been rendered — dashboard, dev-portal, MDCB, operator and bootstrap. This is gap #3 and the largest single hole.

**Deliverable from this test case:** `ci/no-securitycontext-values.yaml` for `tyk-stack`, `tyk-control-plane` and `tyk-data-plane`, contributed back to the repo.

**Step 1 — Author the missing opt-out values files.** The exact keys, read from the merged umbrella `values.yaml` files:

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
→ ⚠️ **Use `enabled: false`, never `securityContext: {}`.** Helm deep-merges the component chart defaults back in, so `{}` is a silent no-op and produces a false pass.
→ *Note the key irregularities:* MDCB and the operator use `podSecurityContext`/`managerPodSecurityContext`, not `securityContext`; dev-portal's blocks sit at the chart root with no `.devPortal` nesting; `tyk-control-plane` has no `tests:` block (no helm-test template), while `tyk-oss`, `tyk-stack` and `tyk-data-plane` do.

**Step 2 — Render and confirm the blocks are gone.**
```bash
helm template t ./tyk-control-plane -f ./tyk-control-plane/ci/no-securitycontext-values.yaml \
  | grep -nE 'fsGroup:|runAsUser:|enabled:'
```
→ *Testing:* that every block was actually removed, and that no invalid `enabled` field leaked into the manifest.
→ *Pass:* no `fsGroup:` or `runAsUser:` anywhere; no stray `enabled:` inside a `securityContext` block.

**Step 3 — Verify the operator opt-out specifically** (gap #9).
```bash
helm template t ./tyk-control-plane --set tyk-operator.podSecurityContext.enabled=false \
  | yq 'select(.metadata.name|test("operator")) | .spec.template.spec.securityContext'
helm template t ./tyk-control-plane --set tyk-operator.managerPodSecurityContext.enabled=false \
  | yq 'select(.metadata.name|test("operator")) | .spec.template.spec.securityContext'
```
→ *Testing:* the suspected gap. `components/tyk-operator/templates/all.yaml:395` reads `.Values.managerPodSecurityContext`, but every umbrella exposes only `tyk-operator.podSecurityContext` — which the operator's own values.yaml notes "no template reads".
→ *Pass:* the second command removes the block. **If the first command does not**, raise a defect: the documented umbrella surface cannot opt the operator out, and the umbrella `values.yaml` needs `managerPodSecurityContext` added.

**Step 4 — Install each umbrella on CRC as `developer`.**
```bash
oc project tyk-qa
helm install tyk ./tyk-control-plane -n tyk-qa --wait --timeout 15m \
  -f ./tyk-control-plane/ci/no-securitycontext-values.yaml
```
→ *Testing:* the actual acceptance criterion — charts deploy on OpenShift without Kustomize patches.
→ *Pass:* `helm install` completes; no pod stuck Pending or in `CreateContainerConfigError`.

**Step 5 — Confirm every pod is genuinely under `restricted-v2`.**
```bash
oc get pods -n tyk-qa -o custom-columns=\
'NAME:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc,UID:.spec.securityContext.fsGroup'
```
→ *Testing:* that the SCC assigned the context rather than the chart pinning it — the whole point of the change.
→ *Pass:* every pod reads `restricted-v2`, and every injected `fsGroup` falls inside the namespace UID range from §3.6.
→ *Fail:* any pod on `anyuid` means you are privileged and the result is void — go back to §3.6.

**Step 6 — Check for SCC denials in events.**
```bash
oc get events -n tyk-qa --field-selector reason=FailedCreate
oc get events -n tyk-qa | grep -i 'forbidden\|scc\|securityContext'
```
→ *Testing:* denials that don't surface as pod failures — a ReplicaSet can retry silently while the Deployment looks merely slow.
→ *Pass:* no output.

**Step 7 — Confirm bootstrap jobs completed, not just rendered.**
```bash
oc get jobs -n tyk-qa
oc logs -n tyk-qa job/bootstrap-post-install-tyk-tyk-bootstrap
```
→ *Testing:* gap #4 — bootstrap has never actually run in any automated test.
→ *Pass:* jobs show `Completions 1/1`; logs show real bootstrap work, not an early exit.

**Step 8 — Sweep live objects for null keys.**
```bash
oc get all,sa,role,rolebinding,cm,secret -n tyk-qa -o yaml \
  | grep -nE ':[[:space:]]*null[[:space:]]*$'
```
→ *Testing:* the customer's original reported bug, verified against **live API objects** rather than rendered YAML — the API server can normalise things `helm template` won't show.
→ *Pass:* no output.

**Step 9 — Functional smoke.** Dashboard loads; gateway serves a request against a created API; portal starts and reaches Ready.
→ *Testing:* that "admitted by the SCC" also means "actually works" — a pod can be admitted with an SCC-assigned UID and still fail to write to its volumes.

**Step 10 — Repeat Steps 4–9 for `tyk-stack` and `tyk-data-plane`.**
→ *Testing:* gap #2 — two of the four umbrellas have never been installed anywhere, and control-plane + data-plane is the customer's actual topology.

---

### TC-05 · GitOps / ArgoCD path
**P1 · Cluster: CRC (with OpenShift GitOps from §3.4 Step 3) · ~1 day**

**What this proves:** that the customer's real workflow — ArgoCD sync, no Helm hooks — works end to end, not just in `helm template`.

**Step 1 — Render with hooks disabled and sweep for null keys.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  | grep -nE ':[[:space:]]*null[[:space:]]*$'
```
→ *Testing:* the exact defect the customer reported (`annotations: null` / `labels: null` on the bootstrap pod templates), plus the three neighbouring resources Leonid found afterwards (bootstrap SA, Role, RoleBinding).
→ *Pass:* no output. ArgoCD rejects null annotations/labels outright.

**Step 2 — Confirm hook annotations are actually gone.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  | grep -n 'helm.sh/hook'
```
→ *Testing:* the feature's core purpose — ArgoCD does not execute Helm hooks, so hook-annotated resources never run.
→ *Pass:* no output.

**Step 3 — Confirm the pre-delete Job is not rendered at all.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  | grep -n 'pre-delete'
```
→ *Testing:* a deliberate design decision — with hooks off, the pre-delete Job would otherwise render as a normal install-time Job and run its cleanup at sync time, deleting the operator secret and bricking the install.
→ *Pass:* no output. Also verify the docs no longer suggest re-enabling it via an ArgoCD hook annotation — that advice is unreachable, since the whole template is gated off before any annotation is evaluated.

**Step 4 — Verify annotation quoting.**
```bash
helm template t ./tyk-control-plane \
  --set tyk-bootstrap.bootstrap.rbacAnnotations."argocd\.argoproj\.io/sync-wave"=-1 \
  --set tyk-bootstrap.bootstrap.jobs.preInstall.annotations."argocd\.argoproj\.io/sync-wave"=-1 \
  | grep -n 'sync-wave'
```
→ *Testing:* `annotations` is `map[string]string`; an unquoted `-1` renders as an integer and the API server rejects the object with `cannot unmarshal number into … type string`. This broke the flagship ArgoCD use case.
→ *Pass:* every value renders quoted — `"-1"`, not `-1`.

**Step 5 — Confirm the API server accepts it.**
```bash
helm template t ./tyk-control-plane --set tyk-bootstrap.bootstrap.disableHelmHooks=true \
  --set tyk-bootstrap.bootstrap.rbacAnnotations."argocd\.argoproj\.io/sync-wave"=-1 \
  | oc apply --dry-run=server -f -
```
→ *Testing:* that quoting holds against a real API server, not just visually in the render.
→ *Pass:* no `cannot unmarshal number` error.

**Step 6 — Deploy through the real ArgoCD instance.** Create an ArgoCD Application pointing at the chart with `disableHelmHooks: true` and sync-wave annotations, then sync.
→ *Testing:* everything above in combination, plus ordering. Render checks cannot prove that bootstrap actually runs before the components that depend on it when sync waves replace Helm hooks.
→ *Pass:* Application reports `Synced` / `Healthy`; bootstrap completes before dependent pods start; **zero manual Kustomize patches required**.

**Step 7 — Delete the Application and observe cleanup.**
→ *Testing:* the documented consequence of disabling hooks — no pre-delete Job exists, so cleanup is the user's responsibility.
→ *Pass:* behaviour matches the docs; no cleanup Job fires at install/sync time; no orphaned bootstrap resources beyond what's documented.

---

### TC-06 · Data-plane connection-string secret (ticket TC3)
**P1 · Cluster: kind (render) + CRC (live) · ~3 hours**

**What this proves:** that the MDCB connection string can come from a secret, and — critically — that this did not break the existing documented setup. Note the ticket's original AC named the wrong key: it is `connectionStringSecretName`, deliberately decoupled from `useSecretName`.

**Step 1 — Default path: literal value.**
```bash
helm template t ./tyk-data-plane --set global.remoteControlPlane.connectionString="tcp://mdcb:9091" \
  | grep -A4 TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING
```
→ *Testing:* backwards compatibility — existing users who set a literal string must see no change.
→ *Pass:* renders `value: "tcp://mdcb:9091"`, no `valueFrom`.

**Step 2 — Secret with the default key.**
```bash
helm template t ./tyk-data-plane --set global.remoteControlPlane.connectionStringSecretName=mdcb-conn \
  | grep -A4 TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING
```
→ *Testing:* the new feature, and its default key fallback.
→ *Pass:* renders `valueFrom.secretKeyRef` with `name: mdcb-conn` and `key: connectionString`; **no literal `value:` alongside it**.

**Step 3 — Secret with a custom key.**
```bash
helm template t ./tyk-data-plane --set global.remoteControlPlane.connectionStringSecretName=mdcb-conn \
  --set global.remoteControlPlane.connectionStringSecretKey=myKey \
  | grep -A4 TYK_GW_SLAVEOPTIONS_CONNECTIONSTRING
```
→ *Testing:* the Crossplane-shaped case where secret keys aren't chart defaults.
→ *Pass:* `key: myKey`.

**Step 4 — The regression that previously broke installs.** Install the *previous released* data-plane chart configured the documented way — a credentials secret via `useSecretName` **plus** a literal `connectionString` in values — then upgrade to `main`.
→ *Testing:* the decoupling decision. Tying `connectionString` to `useSecretName` previously broke existing installs with `couldn't find key connectionString in Secret` on `helm upgrade`. This is the highest-value step in this test case.
→ *Pass:* upgrade succeeds; no `couldn't find key connectionString in Secret`.

**Step 5 — Check the pump path too.**
```bash
grep -n "connectionStringSecretName" -A5 components/tyk-pump/templates/deployment-pmp.yaml
```
→ *Testing:* `deployment-pmp.yaml` carries the same conditional branch as the gateway. It's easy to fix one and miss the other.
→ *Pass:* pump renders `secretKeyRef` under the same conditions as the gateway.

**Step 6 — Live check on CRC.** With a real secret and a reachable MDCB, confirm the data-plane gateway connects.
→ *Testing:* that the env var is not just rendered but readable at runtime — a secretKeyRef pointing at a missing key fails at pod start, not at render.
→ *Pass:* gateway logs show a successful MDCB connection.

---

### TC-07 · Bootstrap job configurability, executed not rendered
**P1 · Cluster: CRC (+ kind for renders) · ~1 day**

**What this proves:** gap #4 — five new bootstrap settings that have never actually run anywhere.

Install `tyk-control-plane` and exercise each in turn.

**Step 1 — `backoffLimit`.** Set `tyk-bootstrap.bootstrap.jobs.preInstall.backoffLimit=0`, then `=3`, forcing a job failure each time (e.g. point at an unreachable dashboard).
→ *Testing:* that the value is honoured. Previously hardcoded to `1`; ArgoCD users need `0` to avoid retry storms.
→ *Pass:* `oc get job -o jsonpath='{.spec.backoffLimit}'` matches; with `0` the job does not retry; with `3` it retries exactly three times.

**Step 2 — `imagePullSecrets` against a real private registry.** Push the bootstrap image to a private registry (ECR/GCR/ACR/Harbor), point the chart at it, install **without** the pull secret first, then **with** it.
→ *Testing:* an explicit acceptance criterion that has never been tested. Installing only the working case proves nothing — you need the negative control to know the secret is doing the work.
→ *Pass:* without the secret → `ImagePullBackOff`; with it → job pulls and completes.

**Step 3 — `preDelete.command` override.**
```bash
helm upgrade tyk ./tyk-control-plane -n tyk-qa \
  --set-json 'tyk-bootstrap.bootstrap.jobs.preDelete.command=["/bin/sh","-c","echo no-op"]'
helm uninstall tyk -n tyk-qa
```
→ *Testing:* the GitOps escape hatch — users who don't want Tyk deleting resources when ArgoCD removes the app.
→ *Pass:* the override runs on uninstall; Tyk resources are **not** deleted.

**Step 4 — `rbacAnnotations`.** Set sync-wave annotations and inspect the live objects.
```bash
oc get sa,role,rolebinding -n tyk-qa -o yaml | grep -B2 -A2 sync-wave
```
→ *Testing:* that annotations reach **all three** RBAC resources — the SA, Role and RoleBinding were the exact three that rendered `annotations: null` in Leonid's first review.
→ *Pass:* present on all three, quoted, accepted by the API server.

**Step 5 — `disableHelmHooks` on a live install.** Install with it true.
→ *Testing:* combination behaviour — hooks off, jobs still complete, no null keys, pre-delete absent.
→ *Pass:* as TC-05 Steps 1–3, but verified against live cluster objects.

---

### TC-08 · Dev Portal configurability
**P1 · Cluster: CRC · ~half a day**

**What this proves:** gap #6 — the portal has null-key unit tests only and is installed by no smoke job.

**Step 1 — `extraEnvs` with `valueFrom`.** Set both a `secretKeyRef` and a `configMapKeyRef`.
→ *Testing:* the rendering change from a plain `value:` field to `tplvalues.render`.
→ *Pass:* both render correctly, and `oc exec <portal-pod> -- env` shows the resolved values at runtime.

**Step 2 — `extraEnvs` with plain `value:` still works.**
→ *Testing:* backwards compatibility. The rendering change is where a regression would hide.
→ *Pass:* existing-style entries render unchanged.

**Step 3 — `storage.s3.secretRef` with custom key names.** Set `secretRef.name`, `accessKeyIdKey`, `secretAccessKeyKey`.
→ *Testing:* the Crossplane case — externally-managed secrets whose key names aren't the chart defaults (`DevPortalAwsAccessKeyId` / `DevPortalAwsSecretAccessKey`).
→ *Pass:* the custom keys are used, and `secretRef` takes precedence over `useSecretName`.

**Step 4 — Fallback chain with `secretRef.name` empty.**
→ *Testing:* that existing users who never set `secretRef` are unaffected — the documented fallback to `useSecretName`.
→ *Pass:* falls back cleanly; no null keys, no empty `secretKeyRef`.

**Step 5 — `bootstrapJob` configuration.** Override the image (previously hardcoded `curlimages/curl:8.8.0`), set `imagePullSecrets`, set `securityContext.enabled: false`.
→ *Testing:* the hardcoded image blocked air-gapped and private-registry users entirely.
→ *Pass:* the job runs on OpenShift under `restricted-v2` with the overridden image.

**Step 6 — PVC write permissions under the opt-out.**
→ *Testing:* the portal is the only component with a real PVC. With `fsGroup` omitted, the SCC assigns the GID — if that plumbing is wrong the portal starts but cannot write.
→ *Pass:* portal writes to its storage; no permission errors in logs.

---

### TC-09 · Regression suite and lint on merged `main`
**P1 · Cluster: none (local) · ~1 hour**

**What this proves:** that nothing regressed between the PR branch and the merged tree, and — more importantly — that the new tests actually bite.

**Step 1 — Run every discovered suite.**
```bash
CHARTS=$(for d in $(find . -path '*/tests/*_test.yaml'); do echo "$d" | sed 's#/tests/[^/]*_test.yaml##'; done | sort -u)
helm unittest $CHARTS
```
→ *Testing:* render-level correctness across all new value keys.
→ *Pass:* all green. The branch reported 189/189 across 29 suites / 6 charts — **re-baseline against current `main`**, which has moved, rather than asserting that exact number.

**Step 2 — Lint every chart.**
```bash
for c in $(find . -maxdepth 2 -name Chart.yaml | sed 's#/Chart.yaml##'); do helm lint "$c"; done
```
→ *Pass:* all 11 charts clean.

**Step 3 — Anti-vacuity check.** Locally revert one fix — e.g. re-introduce the null `annotations` on `components/tyk-bootstrap/templates/bootstrap-serviceaccount.yml` — and re-run the suite.
→ *Testing:* whether the regression tests are real. A test that passes on both the fixed *and* the broken tree is worthless, and this suite was written by the same person who wrote the fix.
→ *Pass:* the suite goes **red**. If it stays green, the test is a placebo — raise it.

**Step 4 — Confirm CI discovery works in a real run.**
```bash
grep -n "tests/\*_test.yaml" -B5 -A5 .github/workflows/unit-tests.yaml
```
→ *Testing:* the claim that CI now runs every chart's suites rather than `tyk-stack` alone — 8 suites were previously orphaned and never executed.
→ *Pass:* confirm in an **actual CI run log**, not just locally. Note `tyk-data-plane` legitimately has no root-level `tests/` and is skipped by design — flag it as gap #5, not as a CI bug.

---

### TC-10 · Field-leak and API-strictness sweep
**P1 · Cluster: kind · ~1 hour**

**What this proves:** that `enabled` — a synthetic chart-level flag, not a Kubernetes field — never reaches a rendered manifest.

**Step 1 — Server-side dry-run every umbrella with its opt-out file.**
```bash
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do
  echo "=== $u ==="
  helm template t ./$u -f ./$u/ci/no-securitycontext-values.yaml \
    | kubectl apply --dry-run=server -f - 2>&1 | grep -i 'unknown field' && echo "LEAK in $u"
done
```
→ *Testing:* Leonid's original finding — `enabled` was implemented only in the gateway, and on dashboard/pump/bootstrap/dev-portal it leaked into the manifest, where the API server hard-rejects it with `strict decoding error: unknown field "spec.securityContext.enabled"`.
→ *Pass:* no `unknown field` output for any umbrella.
→ ⚠️ **Server-side dry-run is required.** Client-side dry-run does not perform strict decoding and will pass regardless — a false-pass trap. This runs fine on kind; no OpenShift needed.

**Step 2 — Repeat with each block disabled individually**, not just all at once.
→ *Testing:* an all-at-once pass can mask a leak in one component if another fails first. There are 15 blocks; test them independently.

---

### TC-11 · Backwards compatibility on vanilla Kubernetes
**P0 · Cluster: kind, full matrix · ~half a day**

**What this proves:** that the OpenShift work didn't break the 99% of users on vanilla k8s. Every regression CI caught on this ticket was a **vanilla-k8s** failure, not an OpenShift one. Do not skip this.

Fresh installs with **stock values** (no opt-out) across `v1.26.13`, `v1.27.10`, `v1.28.6`, `v1.29.4`, `v1.30.0`.

**Step 1 — Gateway init container and emptyDir.**
→ *Testing:* the `aac23c3` revert — removing pod-level `fsGroup` left `/mnt/tyk-gateway` owned `root:root 0755`, so `setupDirectories` couldn't `mkdir` and the gateway never reached Ready.
→ *Pass:* init container exits 0; gateway Ready; `fsGroup: 2000` present in the rendered pod spec.

**Step 2 — Init/main UID alignment.** Create an API through the gateway.
→ *Testing:* the `e92f013` fix — an init container at UID 1000 against a main container at UID 65532 produced HTTP 500 `file object creation failed, write error`.
→ *Pass:* API creation returns 200.

**Step 3 — Dashboard `init-analytics-conf` on the legacy path.** Install with `dashboard.image.tag` ≤ 5.0.2 so the init container renders.
→ *Testing:* a regression this PR *introduced* and then fixed — the init container reused `containerSecurityContext`, which this PR stripped `runAsUser` from, so busybox failed admission under inherited `runAsNonRoot: true`.
→ *Pass:* pod admits and starts; the init container has its own securityContext with `runAsUser: 1000`.

**Step 4 — Pump `extraContainers`.** Install with a sidecar defined and `pump.securityContext.enabled: false`.
→ *Testing:* `extraContainers` were nested inside the `securityContext` conditional, so sidecars **silently vanished** when it was falsy. Silent data loss is worse than a crash — it needs an explicit test.
→ *Pass:* the sidecar renders and runs with the securityContext disabled.

**Step 5 — Pod Security Admission `restricted`.**
```bash
kubectl label ns tyk pod-security.kubernetes.io/enforce=restricted
```
→ *Testing:* that removing pinned UIDs didn't break PSA, the vanilla-k8s analogue of SCC.
→ *Pass:* all pods admit.

**Step 6 — `helm test` on each umbrella.**
→ *Testing:* the umbrella test pods previously pinned `runAsUser: 1000` with no opt-out, so `helm test` could never pass on OpenShift; they now have an `enabled` flag.
→ *Pass:* `helm test` passes.
→ **Known issue:** run it **twice**. The second run fails with `configmaps ... already exists` — the test configmap is missing a `hook-delete-policy`. Sedky said he'd raise this separately; confirm that ticket exists and decide whether it blocks 5.4.0.

---

### TC-12 · Customer re-confirmation
**P1 · Cluster: customer's ROSA · elapsed time, not effort — start on day 1**

**What this proves:** that the merged state works on the environment that motivated the ticket. The customer tested `c99bc03`, which **predates** the final round of fixes — null keys on SA/Role/RoleBinding, the `enabled` leak on non-gateway components, and annotation quoting. Their "works great" report does not cover what shipped.

**Step 1 — Send the merged `main` chart** (pin the SHA from §3.8) and ask them to deploy on ROSA + ArgoCD across their three regions.

**Step 2 — Ask three specific questions:**
- How many of the original **24 Kustomize patches** remain?
- Is the `op: remove` workaround patch for null labels/annotations now removable?
- Are the `fsGroup` and init-UID patches gone with the opt-out?

→ *Testing:* the headline acceptance criterion, measured rather than asserted. "Works great" is not a pass signal; a patch count is.
→ *Pass:* the remaining patch list contains **only non-Tyk components** (Redis, PostgreSQL), and the customer explicitly agrees that is acceptable.

**Step 3 — Set a response deadline** and note it on the ticket. If it passes without a reply, trigger the ROSA contingency from §3.1 rather than letting the release drift.

---

## 5. Execution order

Roughly 4–5 working days for one QA engineer. TC-01/02/11 (kind) and TC-03/04 (OpenShift) are independent and can run in parallel if two people are available.

| Day | Work | Cluster |
|---|---|---|
| 1 | Environment setup (§3.3–3.5); TC-09, TC-10 | local, kind |
| 1–2 | TC-01, TC-02, TC-11 — the upgrade and backwards-compat block | kind |
| 2 | TC-03 (30 min), then author the three opt-out values files | Sandbox |
| 2–3 | TC-04 across all four umbrellas | CRC |
| 3–4 | TC-05 (ArgoCD), TC-06, TC-07, TC-08 | CRC |
| 5 | Write-up, defect filing, sign-off decision | — |

---

## 6. Sign-off checklist

Release into Charts 5.4.0 when:

- [ ] TC-01 passes on k8s 1.26 and 1.30 for `tyk-oss`, `tyk-data-plane` and `tyk-stack`, with and without `--reuse-values`
- [ ] TC-02 outcome documented, and the pinned-old-tag decision explicitly made (guard vs. release note only)
- [ ] TC-03 reproduced by QA on a real, unprivileged OpenShift cluster
- [ ] TC-04 passes for all four umbrellas; the three missing `ci/no-securitycontext-values.yaml` files are merged; the operator key question (gap #9) is resolved
- [ ] TC-05 passes through a real ArgoCD instance, not just `helm template`
- [ ] TC-06 passes including the `useSecretName` + literal `connectionString` upgrade regression
- [ ] TC-07 bootstrap jobs verified **executing**, including against a real private registry with a negative control
- [ ] TC-08 dev portal verified running with all three new config paths
- [ ] TC-09 green on merged `main`, **with the anti-vacuity revert check done**
- [ ] TC-10 zero field leaks under server-side dry-run
- [ ] TC-11 green across the full kind matrix
- [ ] TC-12 customer confirms on the merged state; remaining patch list agreed in writing
- [ ] Upgrade release note reviewed and published in the 5.4.0 changelog
- [ ] OpenShift docs cover the `enabled: false` opt-out (and why `{}` doesn't work), the Redis/PostgreSQL caveat, and the per-component image-tag boundary

---

## 7. Recommended follow-ups (not blockers for 5.4.0)

1. **A real-SCC CI gate on MicroShift.** Everything here that CI structurally cannot cover reduces to "kind has no SCC controller." MicroShift is light enough for a GitHub Actions job and would make TC-03/TC-04 permanent regression coverage instead of a manual pre-release ritual. Highest-leverage follow-up.
2. **A genuine upgrade job in CI** — install the last released chart from the public Helm repo, then upgrade to the branch. Today's `--reuse-values` self-upgrade doesn't test what breaks.
3. **Add a `tests/` suite to `tyk-data-plane`**, or move `connectionStringSecret_test.yaml` there.
4. **Smoke-install `tyk-stack` and `tyk-control-plane`** in `run-tests.yaml`.
5. **Fix the `helm test` configmap `hook-delete-policy`** so repeat runs don't fail.
6. **Expose `managerPodSecurityContext` in the umbrella values** if gap #9 is confirmed, and consider removing or documenting the dead `podSecurityContext` key.
7. **Document the Redis/PostgreSQL OpenShift story.** `master.podSecurityContext.enabled=false` in Tyk values is a no-op because they're separate releases; bitnami/redis pins UID/GID 1001.

---

## 8. Open questions for the Thursday review

1. **Pinned-old-tag upgrades (TC-02):** ship with a release note only, or add a `semverCompare` guard / `NOTES.txt` warning? The most likely support-ticket generator in 5.4.0.
2. **Scope of "no Kustomize patches":** does the AC mean Tyk components only? Redis/PostgreSQL will still need patches. Needs stating in the AC and the docs, and agreeing with the customer.
3. **Process:** the change is already on `main`. If QA finds a P0 — revert, or fix forward before the 5.4.0 cut? Decide now rather than under pressure.
4. **Chart version:** `main` reads `5.3.0` while the fix version is Charts 5.4.0. Confirm the release-prep bump is tracked separately and QA is testing the right tree.
5. **TC-12 ownership and deadline.** It's elapsed-time-bound and the last round took roughly a month. Who owns it, and what's the date that triggers the ROSA contingency?

---

## Sources

- [TT-17018 — [Innersource] OpenShift with GitOps Support](https://tyktech.atlassian.net/browse/TT-17018) — description, backwards-compatibility audit, and all 12 comments (Sedky Abou-Shamalah, Leonid Bugaev, Andy Ost, Valmir Verbani)
- Related: [TT-17352](https://tyktech.atlassian.net/browse/TT-17352) (Closed), [TT-17353](https://tyktech.atlassian.net/browse/TT-17353) (Closed)
- `TykTechnologies/tyk-charts` @ `main` — merge commit `61e5cf1`; `.github/workflows/unit-tests.yaml`, `.github/workflows/run-tests.yaml`, `tyk-oss/ci/no-securitycontext-values.yaml`, `components/tyk-operator/templates/all.yaml`, and all component/umbrella `values.yaml` and `tests/` trees (inspected directly)
- [Developer Sandbox FAQ](https://developers.redhat.com/developer-sandbox/FAQ) — 30-day duration, 12-hour pod lifetime
- [Installing CRC](https://crc.dev/docs/installing/) — 4 physical cores / 10.5 GB memory / 35 GB storage minimum

