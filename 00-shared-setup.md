# Shared setup — both owners read this first

~15 minutes. Then work from your own packet:
[`owner-1-kind-and-render.md`](owner-1-kind-and-render.md) ·
[`owner-2-openshift.md`](owner-2-openshift.md).
Source: [`../TT-17018-test-plan.md`](../TT-17018-test-plan.md) §3.

---

## 1. Code under test

Test **merged `main`**, not PR #485's branch. `main` has moved since the merge (`462900f`, then
reverted by `4e0f1be` for TT-16572 lifecycle hooks). PR #467 is closed/superseded — ignore it.

```bash
git clone https://github.com/TykTechnologies/tyk-charts.git && cd tyk-charts
git rev-parse HEAD    # must equal the SHA pinned on TT-17018 on day 0
for u in tyk-oss tyk-stack tyk-control-plane tyk-data-plane; do helm dependency update ./$u; done
```

If your SHA doesn't match, `git checkout <pinned-sha>` before doing anything. Results against
different trees don't aggregate — and the whole point of this pass is one coherent evidence set.

> §8 Q4: `main` reads chart version `5.3.0` while the fix version is Charts 5.4.0. You are testing
> the right tree; it just isn't labelled 5.4.0 yet. Confirm the release-prep bump is tracked
> separately.

## 2. Tooling

```bash
helm version          # 3.18.4 — what the branch was validated on
helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v0.7.2
yq --version
kind version          # Owner 1
crane version         # Owner 1, TC-02 image USER inspection
oc version            # Owner 2
```

---

## 3. The `enabled: false` trap — both owners, every test

To disable a security context block, always write:

```yaml
securityContext: {enabled: false}
```

**Never** `securityContext: {}`. Helm deep-merges the component chart defaults back in, so `{}` is a
silent no-op that produces a **false pass**. If a test passes when you expected it to fail, check
this before believing the result.

Key names are irregular across components. Do not normalise them:

| Component | Pod-level key |
|---|---|
| gateway, dashboard, pump, bootstrap | `securityContext` |
| MDCB | `podSecurityContext` |
| tyk-operator | `managerPodSecurityContext` — **not** `podSecurityContext` (gap #9) |
| dev-portal | `securityContext` at the **chart root**, no `.devPortal` nesting |

Container-level is `containerSecurityContext` throughout. Init containers carry their own nested
blocks — `initContainers.setupDirectories.securityContext` (gateway),
`initContainers.initAnalyticsConf.securityContext` (dashboard).

Also: `tyk-control-plane` has **no `tests:` block** (no helm-test template), while `tyk-oss`,
`tyk-stack` and `tyk-data-plane` do. That's by design, not a gap.

---

## 3b. Image repository names — the master plan gets two of them wrong

Both owners reference these images. Verified against the registry:

Two components are **not on Docker Hub**, and the master plan gets two Docker Hub names wrong.
Verified against `main` on 2026-08-20 — repository strings exactly as the chart sets them, and the
USER read from the registry the chart actually pulls from:

| Component | Repository as the chart sets it | Default tag | USER |
|---|---|---|---|
| Gateway | **`docker.tyk.io/tyk-gateway/tyk-gateway`** | v5.13.1 | `65532` |
| Pump | **`docker.tyk.io/tyk-pump/tyk-pump`** | v1.16.0 | `65532` |
| Dashboard | `tykio/tyk-dashboard` | v5.13.1 | `65532` |
| MDCB | `tykio/tyk-mdcb-docker` | v2.12.0 | `65532` |
| Dev Portal | `tykio/portal` | v1.18.0 | `65532` |
| Operator | `tykio/tyk-operator` | v1.4.2 | `65532:65532` |
| Bootstrap | `tykio/tyk-k8s-bootstrap-{pre-install,post,pre-delete}` — **three** images | v2.2.0 | `65532:65532` |
| Gateway init | `busybox` | 1.32 | **EMPTY (=root)** |
| Portal bootstrap | `curlimages/curl` | 8.8.0 | **`curl_user` (symbolic)** |
| Operator sidecar | `gcr.io/kubebuilder/kube-rbac-proxy` | v0.15.0 | not checked |

**Names the master plan uses that don't exist:** `tykio/tyk-pump` (pump is at `docker.tyk.io`, and its
Docker Hub mirror is `tykio/tyk-pump-docker-pub`), `tykio/tyk-sink` (MDCB is `tykio/tyk-mdcb-docker`),
and `tykio/tyk-bootstrap` (there are three bootstrap images, not one).

`docker.tyk.io` is Cloudsmith-backed and **readable anonymously** — no credentials needed, but blob
reads need a token from `https://docker.tyk.io/login` and follow a redirect to `dl.cloudsmith.io`.
`crane` handles all of this transparently; hand-rolled `curl` does not.

The gateway's USER is **non-monotonic** across versions — root on v5.9–v5.12, non-root on v5.8.13–15
and v5.13+. The current default is in the safe band, but any re-pin needs re-checking. Detail and the
band table: Owner 1's TC-02 Step 1b. All Tyk components publish **both amd64 and arm64**, so
architecture isn't a constraint on Tyk's own images (bitnami Redis/PostgreSQL is unverified — see §5).
A `-fips` twin exists for every component.

## 4. The privilege gate — Owner 2, every OpenShift session

Not once at setup. **Every session.**

```bash
oc whoami
oc auth can-i use scc/anyuid        # MUST be: no
oc auth can-i use scc/privileged    # MUST be: no
oc auth can-i '*' '*'               # MUST be: no  (not cluster-admin)
oc get ns "$(oc project -q)" -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
# e.g. 1004340000/10000  ->  allowed UIDs 1004340000-1004349999
```

**If `can-i use scc/anyuid` returns `yes`, STOP and re-login as `developer`.** A cluster-admin gets
`anyuid`, which bypasses `restricted-v2` entirely — every SCC test then passes regardless of what the
chart does. This is the single most common way to produce a worthless pass on this ticket.

Unlike the Developer Sandbox, an admin-capable cluster hands you cluster-admin freely and it's easy
to fall back into.
Assume you are privileged until this gate says otherwise. Record the UID range — you need it to
verify SCC-injected values later.

---

## 5. Redis and PostgreSQL ⚠️ the master plan omits this and both owners will hit it

Gap #8 notes Redis and PostgreSQL are **separate releases**, not chart dependencies, and that
`bitnami/redis` pins `fsGroup`/`runAsUser`/`runAsGroup` to `1001`. The master plan states the
consequence for the acceptance criterion but never tells you how to get them running — yet every
`helm install` command in it assumes Redis at `redis-master.tyk.svc:6379`.

**Owner 1 (kind)** — just a missing step. Install before any Tyk chart:

```bash
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk --create-namespace \
  --set auth.enabled=false --set architecture=standalone --wait
helm install postgres oci://registry-1.docker.io/bitnamicharts/postgresql -n tyk \
  --set auth.postgresPassword=topsecretpassword --set auth.database=tyk_analytics --wait
```

**Owner 2 (OpenShift)** — a hard blocker. UID/GID `1001` is outside your namespace range, so **Redis
is rejected by `restricted-v2` before you ever exercise a Tyk chart**. And
`master.podSecurityContext.enabled=false` in *Tyk's* values is a **no-op** — different release. Turn
the contexts off on the Redis release itself:

```bash
helm install redis oci://registry-1.docker.io/bitnamicharts/redis -n tyk-qa \
  --set auth.enabled=false --set architecture=standalone \
  --set master.podSecurityContext.enabled=false \
  --set master.containerSecurityContext.enabled=false --wait
```

Same treatment for PostgreSQL via `primary.podSecurityContext.enabled=false`.

Budget **half a day** on OpenShift and **write down exactly what you needed**. Whatever it was is a
patch the customer will also need, which makes it evidence for:

- **§8 Q2** — does "deploys on OpenShift without Kustomize patches" mean **Tyk components only**?
  This is a scope question on the acceptance criterion, not a chart defect.
- **§7.7** — document the Redis/PostgreSQL OpenShift story as a follow-up.

---

## 6. Reporting results

Attach to TT-17018, one entry per step that produced evidence:

```
Owner:      2
Test:       TC-04 Step 5
SHA:        <pinned sha>
Cluster:    SNO 4.18 on AWS · oc whoami = developer · UID range 1004340000/10000
Command:    <the exact command you ran>
Output:     <verbatim, trimmed to what matters>
Verdict:    PASS | FAIL | BLOCKED
Notes:      <anything you had to work around>
```

Every OpenShift result **must** carry `oc whoami` and the UID range. A result without proof you were
unprivileged is not evidence — it's an untested assertion.

### Defects

File against `TykTechnologies/tyk-charts`, link TT-17018, title prefix `[TT-17018 QA]`. Include the
SHA, the umbrella, the exact command, and an explicit **blocks 5.4.0: yes/no**.

**P0 escalation.** The change is already on `main` (master plan §1 — Andy Ost flagged on 28 Jul that
it merged before QA sign-off). A P0 therefore forces §8 Q3: revert, or fix forward before the 5.4.0
cut. Escalate P0s the **same day** you find them. Do not batch them into the day-5 write-up.

P0 test cases: TC-01, TC-02, TC-03, TC-04, TC-11.

### Two failures that are expected — don't file these as new

- **TC-02 Step 3** (Owner 1) — the pinned-old-tag upgrade fails with `CreateContainerConfigError:
  container has runAsNonRoot and image will run as root`. The pass criterion is that it **matches the
  release note verbatim**, not that it works.
- **TC-11 Step 6** (Owner 1) — the *second* `helm test` run fails with `configmaps ... already
  exists`; the test configmap is missing a `hook-delete-policy`. Sedky said he'd raise this
  separately — **confirm that ticket exists** rather than filing a duplicate, and decide whether it
  blocks 5.4.0.

### What is already proven — don't rebuild it

Engineering-side validation here is unusually strong, and QA does **not** need to redo it. The
customer tested on real ROSA, Sedky validated on CRC 4.22.1 unprivileged, and Leonid ran two
independent reviews plus a live `restricted-v2` admission probe.

| Already proven | QA action |
|---|---|
| SCC rejects the default render; opt-out is admitted | **Spot-check once** — Owner 2, TC-03 |
| Null `annotations`/`labels` under `disableHelmHooks` (the customer's reported bug) | Covered by unit tests — **re-run, don't rebuild** |
| `securityContext.enabled` field leak; annotation/label quoting | Covered — **re-run** (TC-09, TC-10) |
| Render-level correctness of every new value key (189/189 unit tests, 11/11 lint) | **Re-run against current `main`** and re-baseline the number |
| Real ROSA + ArgoCD deployment | **Re-confirm on merged `main`** — the customer tested `c99bc03`, which predates the final fixes (TC-12) |

The effort belongs in the nine documented gaps, which is what both packets are built around.
