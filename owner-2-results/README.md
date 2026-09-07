# TT-17018 QA — Owner 2 (OpenShift) results

**Tester:** automated run driven by Claude Code on Travis's laptop
**Date:** 2026-09-07 (single day, ~14:00–21:00 UTC)
**Tree under test:** `TykTechnologies/tyk-charts` @ **`39957f3660212154296b6ffc9ab733f822e6809d`** — the same
SHA Owner 1 tested, so the two evidence sets aggregate
**Chart version in tree:** `5.3.0` for all four umbrellas (D-09 still stands)
**Clusters:**
  * Red Hat Developer Sandbox — OpenShift **4.21.30**, user `trapgeek`, UID band `1009560000–1009569999`
  * **ROSA Classic `tt17018-qa`** — OpenShift **4.22.11**, `us-east-2`, 3 × m5.xlarge, **single-AZ**,
    tested as unprivileged `developer` via an htpasswd IdP
**Tooling:** helm `v3.18.6` (matches Owner 1 exactly), oc `4.22.11`, rosa `1.2.64`, yq `v4.30.8`, jq `1.6`
**Licences:** dashboard + MDCB, both valid to 2026-10-07 — no leg was ever blocked on licensing
**Evidence:** `evidence/` (119 files) · **Scripts:** `scripts/`

> Every SCC result in this pack came from a session where `oc auth can-i use scc/anyuid` returned
> **`no`**. The runbooks abort outright if it returns `yes`, because a privileged session silently
> invalidates every admission result.

---

## Verdict summary

| §6 row | Item | Verdict |
|---|---|---|
| 3 | TC-03 reproduced on a real, unprivileged OpenShift cluster | **PASS — CLOSED** |
| 4 | TC-04 all four umbrellas with the opt-out files | **PASS — CLOSED** |
| 5 | TC-05 through a real ArgoCD instance | **PASS — CLOSED** |
| 6 | TC-06 incl. the connection-string secret (Step 6) | **PASS — CLOSED** (Owner 1 owns Steps 1–5) |
| 7 | TC-07 bootstrap executing, auth registry + negative control | **PASS — CLOSED**, raising D-13 |
| 8 | TC-08 dev portal running, all three config paths | **PASS — CLOSED** |
| 12 | **Headline AC** — four umbrellas, zero Kustomize patches | **PASS — CLOSED** |
| 14 | OpenShift docs (shared with Owner 1) | **Owner 2's input delivered** — see D-06 material below; the write-up is outstanding |

**Three coverage gaps closed that nothing had ever tested:**

| Gap | What it was | Now |
|---|---|---|
| **#3** | dashboard, MDCB, pump, bootstrap opt-outs only ever *rendered* | installed and running under real `restricted-v2` |
| **#4** | bootstrap Jobs never executed in *any* automated test, anywhere | executed, with real work in the logs |
| **#7** | `imagePullSecrets` against an auth-requiring registry — an explicit AC | proven, with a negative control |

---

## ⚠️ What is left to do

**No testing remains in Owner 2's packet.** Every test case is complete. What is outstanding is
decisions and writing, and none of it belongs to Owner 2 alone.

| # | Item | Owner | Blocked on | Effort |
|---|---|---|---|---|
| **1** | **§8 Q3 — D-01 decision.** `helm upgrade --reuse-values` silently breaks the gateway's file writes. Revert TT-17018, or fix forward before the 5.4.0 cut? | team | a decision, not a test | one meeting |
| **2** | **§8 Q1 — pinned-old-tag policy.** Release note only, or a `NOTES.txt` warning / `semverCompare` guard? | team | a decision | one meeting |
| **3** | **NEW — D-13 decision.** The documented `preDelete.command` neutralisation cannot execute and hangs `helm uninstall`. Fix the docs, fix the image, or add a real `preDelete.enabled: false`? | team | a decision | one meeting |
| **4** | **Row 13 — the release note needs a home.** `tyk-charts` has no CHANGELOG. Owner 1's draft is written and covers D-01 and D-05. Suggest the GitHub Release body — it exists, is discoverable, and needs no new process | 1 + repo owner | a venue decision | 15 min |
| **5** | **Row 14 — the OpenShift docs.** Needs: image-tag bands (D-05), the Redis/PostgreSQL story (D-06, now fully characterised below), and the `enabled: false` opt-out with why `{}` does not work | 1 + 2 | writing | half a day |
| **6** | **Optional — the D-11/D-14/D-02 pattern.** Three instances of "a key or piece of advice that looks right and silently does nothing." Worth one conversation, not three tickets | team | — | 10 min |

**Nothing above blocks on cluster access, licences, or QA time.** The ROSA cluster can be torn down.

### Deliberately not done, and why

| Not done | Why it is not required |
|---|---|
| **Multi-AZ ROSA** | The cluster is real ROSA — the customer's actual platform, materially better evidence than the SNO the packet assumed — but `Multi-AZ: false`. Everything in scope (SCC admission, annotation quoting, bootstrap ordering, securityContext omission) is **node-count-independent**. The residual-risk row should read **"real ROSA, single-AZ"**, not be retired. |
| **The customer's own ArgoCD/Kustomize overlays** | TC-05 proves the chart syncs through a real ArgoCD instance with correct sync-wave ordering. It cannot prove anything about overlays we do not have. This remains the larger of the two accepted gaps. |
| **The 24 → N patch-count delta** | We prove Tyk components need **zero** patches. We cannot produce the customer's arithmetic without their overlays. The AC is answered; the specific number is not. |

---

## Defects raised by Owner 2

| ID | Severity | Finding | Blocks 5.4.0 |
|---|---|---|---|
| **D-11** | docs | `preDelete.annotations` documented for a case where it cannot render — and the chart **contradicts itself**, since the component chart correctly says annotations cannot reach the Job while both umbrellas offer a worked ArgoCD example for it, 3× each | no |
| **D-12** | environment | A fresh ROSA cluster serves **two different API certs for ~30 min**; measured **60% of `oc` calls failing**. Intermittent, so failures masquerade as missing resources. Killed the first automated run | no |
| **D-13** | **medium** | The documented `preDelete.command` neutralisation **cannot execute** (no shell in the image) and **hangs `helm uninstall`** to timeout, leaving the release undeleted | **decision** |
| **D-14** | low/docs | `bootstrapJob.imagePullSecrets` is a dead key — the template reads the chart-root `imagePullSecrets` | no |
| **D-15** | low | The portal bootstrapJob is a plain Job with no `hook-delete-policy`, so it persists and its `spec.template` immutability **blocks any upgrade** that reconfigures it | no |

Full detail, reproduction commands and verbatim output for each: see the sections below.

---

## Reproducing this

```bash
cd ~/playground/tt17018-owner2                 # clone + evidence + scripts
git -C tyk-charts rev-parse HEAD               # 39957f3660212154296b6ffc9ab733f822e6809d

./scripts/tc05-sweep.sh          # TC-05 Steps 1-4, all four umbrellas, no cluster
./scripts/tc08-render.sh         # TC-08 Steps 2-4 render assertions, no cluster
./scripts/tc08-s3.sh             # TC-08 Step 3/4 with storage.type=s3 (all three fallback tiers)
./scripts/tc04-all.sh            # TC-04 Steps 4-10, all four umbrellas (needs the cluster)
./scripts/tc04-step11-ac.sh      # TC-04 Step 11 — the headline AC table
./scripts/tc06-step6.sh          # TC-06 Step 6 live connection-string check
./scripts/tc07-bootstrap.sh      # TC-07 backoffLimit / rbacAnnotations / preDelete
./scripts/tc08-live.sh           # TC-08 Steps 1, 5, 6 live
```

⚠️ **Two shell traps cost real time on this run, both worth inheriting:**

1. **zsh does not word-split unquoted string variables.** `helm template ./x $FLAGS` passes one
   malformed argument, helm errors, and `2>&1 | grep` then reports a **false PASS** from the error
   text. Use zsh arrays, and make render helpers fail loudly instead of grepping stderr. This is the
   same class as Owner 1's D-07 — and it recurred here.
2. **`--set key[0]=value` is glob-expanded by zsh** (`no matches found`). Quote the whole `--set`
   argument, or `setopt NO_NOMATCH`.

**Anti-vacuity is not optional on this ticket.** Every "pass = no output" check here is paired with a
baseline proving the grep *can* fire. That is what caught trap 1.

### Cluster teardown

```bash
rosa delete admin --cluster tt17018-qa
rosa delete cluster --cluster tt17018-qa --watch
rosa delete operator-roles --cluster tt17018-qa
rosa delete oidc-provider --cluster tt17018-qa
```

---
# Pre-cluster work — laptop only

## Drift check — D-08 is effectively closed

`main` is now at `261728d`. Between the pinned SHA and current `main` there is exactly **one commit**,
and it is docs-only:

```
261728d docs: add a testing guide to the README (#510)
  README.md                 | 168 +++++++++
  scripts/kind-cluster.yaml |  11 ++
```

**Zero chart changes.** So testing at `39957f3` is chart-identical to testing today's `main`, and
Owner 1's evidence and Owner 2's aggregate without reservation. D-08 raised the risk that
`fb7b449` (which touches pod templates) sat between the trees — it does not; it is *behind* the
pinned SHA, already included.

---

## Completed: block A — setup

| Item | Result |
|---|---|
| Clone + checkout pinned SHA | ok — `39957f3` |
| `helm dependency update` × 4 | ok — 3 / 6 / 7 / 2 subcharts vendored, matching each Chart.yaml exactly |
| All deps are `file://` local | confirmed — no network subcharts; Redis/PostgreSQL are **not** dependencies (gap #8 in concrete form) |

## Completed: block B — TC-05 Steps 1–4 (§6 row 5, render half)

Run for **all four umbrellas**. Renders are 13k–49k lines, so no result is vacuous.

| Step | Validates | Result |
|---|---|---|
| 1 — null-key sweep, `disableHelmHooks=true` | the customer-reported `annotations: null` / `labels: null` defect | **PASS** ×4 |
| 1b — same, pump + devPortal + operator enabled | the same under every component toggle | **PASS** ×4 |
| 2 — hook annotations gone | ArgoCD does not execute Helm hooks | **PASS** on `tyk-control-plane` (18 → 0). See note below for the other three |
| 3 — pre-delete Job not rendered | it would otherwise run at sync time and brick the install | **PASS** ×4 (8 → 0 on stack and control-plane) |
| 4 — annotation quoting | unquoted `-1` renders as an integer and the API server rejects it | **PASS** — 4/4 quoted `"-1"` on both bootstrap-bearing umbrellas |

### Anti-vacuity baseline (render WITHOUT the flag)

| Umbrella | render | hook annotations | pre-delete |
|---|---|---|---|
| tyk-oss | 481 L | 4 | 0 |
| tyk-stack | 1107 L | 21 | 8 |
| tyk-control-plane | 1028 L | 18 | 8 |
| tyk-data-plane | 574 L | 3 | 0 |

With the flag, control-plane goes 18 → 0 and pre-delete 8 → 0. The passes are real, not empty greps.

### Note on Step 2 — the packet's pass criterion is too broad

`tyk-oss`, `tyk-stack` and `tyk-data-plane` still show 3–4 `helm.sh/hook` hits with hooks disabled.
**Every one is a helm-test hook** (`"helm.sh/hook": test` and its `hook-delete-policy`), not a
bootstrap hook. `tyk-control-plane` — the umbrella the packet's command was written against, and the
only one with no `tests:` block — is completely clean.

So the literal criterion "pass = no output" only holds for `tyk-control-plane`. For the other three
the correct criterion is "no *bootstrap* hook annotations." This is a **plan-accuracy issue, not a
chart defect** — the same class as Owner 1's D-07.

## Completed: block B — TC-08 Steps 2–4 (§6 row 8, render half)

Portal rendered through `tyk-stack` with `global.components.devPortal=true`.

| Step | Result |
|---|---|
| 2 — `extraEnvs` with plain `value:` | **PASS** — both entries render unchanged; the `tplvalues.render` change did not regress |
| 3 — `s3.secretRef` custom keys, precedence over `useSecretName` | **PASS** — `crossplane-s3` + `CROSSPLANE_AKID`/`CROSSPLANE_SAK` used; `useSecretName` correctly superseded |
| 4 — fallback, `secretRef.name` empty | **PASS** — falls back to `useSecretName` with default key names, 0 null keys, 0 empty `secretKeyRef` |
| 4b — *added*: neither set | **PASS** — falls back to the chart's own `secrets-<release>` secret |

⚠️ These render only under `storage.type=s3` (the default is `db`). A sweep that does not set it
returns an empty env list and looks like a failure — worth stating in the packet.

---

## Defect found

### D-11 · docs · `preDelete.annotations` is documented for a case where it cannot render

`tyk-control-plane/values.yaml:1167` says:

```yaml
# annotations adds annotations to the pre-delete Job metadata (e.g. ArgoCD sync waves).
# annotations:
#   argocd.argoproj.io/sync-wave: "2"
```

ArgoCD users are precisely the ones who set `disableHelmHooks=true`, and that gates the whole
pre-delete template off *before* any annotation is evaluated. Probed directly:

| Config | `sync-wave: "5"` occurrences |
|---|---|
| `preDelete.annotations` set, hooks **enabled** | 1 |
| `preDelete.annotations` set, hooks **disabled** | **0** |

So the one worked example the comment gives is unreachable in the scenario it names. The READMEs do
**not** carry this advice — only `values.yaml` does, in all umbrellas that ship bootstrap.

**Blocks 5.4.0: no.** Fix is a one-line comment change.

---

---

# Sandbox session — 2026-09-07T18:41Z

**Cluster:** Red Hat Developer Sandbox `api.rm2.thpm.p1.openshiftapps.com` · OpenShift **4.21.30**
**User:** `trapgeek` · project `trapgeek-dev`
**Privilege gate:** `scc/anyuid` = **no**, `scc/privileged` = **no**, `'*' '*'` = **no**
**UID range:** `1009560000/10000` → allowed band **1009560000–1009569999**

## TC-03 · SCC admission probe · **P0** · §6 row 3 → CLOSED

| Step | Result |
|---|---|
| 1 · privilege gate | **PASS** — all three `can-i` checks `no`; UID band recorded |
| 2 · default context, must be REJECTED | **PASS** — rejected citing **both** fields independently |
| 3 · isolate each cause | **PASS** — each field rejected alone, citing only itself |
| 4 · opt-out context, must be ADMITTED | **PASS** — admitted under `restricted-v2`, SCC-injected `fsGroup=1009560000` **and** `runAsUser=1009560000`, both inside the band, pod reached `Running` |

Step 2 verbatim, the two independent causes:

```
provider restricted-v2: .spec.securityContext.fsGroup: Invalid value: [2000]: 2000 is not an allowed group
provider restricted-v2: .initContainers[0].runAsUser: Invalid value: 65532: must be in the ranges: [1009560000, 1009569999]
```

Step 4 injection, proving the SCC does its job once the chart stops pinning:

```
scc=restricted-v2  fsGroup=1009560000  runAsUser=1009560000  seLinux=s0:c98,c27  phase=Running
```

**End-to-end chain proven: rejected default → admitted opt-out → SCC fills a valid UID/GID.**
§6 row 3 is satisfied by this output plus the Step 1 gate. Probe pod deleted after the run.

## TC-05 Step 5 · server-side dry-run · §6 row 5

| Umbrella | Result |
|---|---|
| tyk-control-plane | **PASS** — 15 objects accepted, no decode errors |
| tyk-stack | **PASS on decoding** — 15 accepted; 1 pod SCC-rejected (see below) |
| tyk-oss | **PASS on decoding** — 5 accepted; 1 pod SCC-rejected |
| tyk-data-plane | **PASS on decoding** — 7 accepted; 1 pod SCC-rejected |

No `cannot unmarshal number` anywhere — the annotation quoting holds against a real API server, which
is what Step 5 exists to prove.

### New: the helm-test pod is a fourth SCC rejection site

The one rejected object in each of three umbrellas is the **helm-test pod**, and the cause is real:

```
pods "t-tyk-oss-test-tyk-oss" is forbidden: ...
  provider restricted-v2: .containers[0].runAsUser: Invalid value: 1000: must be in the ranges: [1009560000, 1009569999]
```

`tyk-control-plane` is clean at 15/15 **because it ships no test pod** — the "no `tests:` block" that
Owner 1 confirmed is by design turns out to be why it is the only umbrella whose default render is
fully admissible.

This is not a new defect — it is the ticket's own premise showing up on a surface TC-03's bare-Pod
probe does not reach. It matters for two reasons: the `tests:` blocks in Owner 1's opt-out files are
**load-bearing on OpenShift, not cosmetic**, and any future `ct install` job on OpenShift would fail
on the test pod before it failed on anything else.

## Bonus · opt-out values files vs **real** `restricted-v2`

Owner 1's three values files (plus the shipped `tyk-oss` one) rendered and pushed through
server-side admission on real OpenShift:

| Umbrella | Result |
|---|---|
| tyk-control-plane | **PASS** — 16 objects admitted, 0 SCC rejections, 0 field leaks |
| tyk-stack | **PASS** — 17 admitted, 0 rejections, 0 leaks |
| tyk-data-plane | **PASS** — 8 admitted, 0 rejections, 0 leaks |
| tyk-oss | **PASS** — 6 admitted, 0 rejections, 0 leaks |

Default render → test pod rejected. Opt-out render → **everything admitted**. This is the ticket's
central claim validated against real SCC admission by QA on an unprivileged account.

⚠️ **This is not TC-04 and must not be reported as it.** Nothing was installed: no pods ran, no
bootstrap Job executed, no PVC was bound, no functional smoke happened. It proves *admissibility*,
which is a strictly weaker claim than *installs and works*. §6 rows 4 and 12 still need the admin
cluster. What it does do is de-risk TC-04 — if the opt-out files were going to be rejected by an
SCC, they would have been rejected here.

## Environment note — OpenShift 4.21 ships `restricted-v3`

Every rejection message lists a `restricted-v3` provider complaining
`.spec.securityContext.hostUsers: Invalid value: null: Host Users must be set to false`. It is not
the SCC the ticket targets and it did not affect any verdict, but it is new since the packet was
written and worth a line at sign-off — a future chart may need `hostUsers: false` to be admissible
under it.

---

# S6 characterised on the laptop, before the cluster existed

The packet budgets **half a day** for Redis/PostgreSQL on OpenShift. That budget assumed *discovery*
— working out what has to be turned off and where. All of that is a render question, so it was done
locally while the ROSA cluster built.

## Gap #8, measured

| Chart | Rendering | `fsGroup` | `runAsGroup` | `runAsUser` | securityContext blocks |
|---|---|---|---|---|---|
| bitnami/redis | packet's plain command | `1001` | `1001` | `1001` | 2 |
| bitnami/redis | `master.{pod,container}SecurityContext.enabled=false` | — | — | — | **0** |
| bitnami/postgresql | plain | `1001` | `1001` | `1001` | 2 |
| bitnami/postgresql | `primary.{pod,container}SecurityContext.enabled=false` | — | — | — | **0** |

UID `1001` is outside every Sandbox/ROSA namespace band, so the plain render is rejected by
`restricted-v2` before a single Tyk chart is exercised — exactly as gap #8 predicts. The opt-out
flags strip the pinning completely, on the **bitnami release itself**. Setting the same keys in
*Tyk's* values is a no-op, because it is a different Helm release.

**This is the answer §8 Q2 needs:** "deploys on OpenShift without Kustomize patches" can only mean
**Tyk components**. Redis and PostgreSQL need their own security contexts disabled, and no amount of
work on the Tyk charts changes that.

## Bitnami catalogue change — CI has a workaround the docs lack

`bitnami/redis` and `bitnami/postgresql` now resolve to rolling **`:latest`** tags. Both exist and
are current (pushed 2026-09-03, amd64 + arm64), so the plain command works today. But
`run-tests.yaml:92-99` pins six image repositories to `bitnamilegacy/*` (frozen July 2025) and
**nothing in the docs mentions this**. A user following the README gets a rolling tag whose contents
can change under them; CI does not. That belongs in the D-06 write-up alongside the UID story.

---

# ROSA run — 2026-09-07, 20:02–20:08 UTC

**Cluster:** ROSA Classic `tt17018-qa` · OpenShift **4.22.11** · `us-east-2` · 3 × m5.xlarge · **single-AZ**
**User:** `developer` via htpasswd IdP · `anyuid=no`, `privileged=no`, `'*' '*'=no`
**Namespaces:** `tyk-qa` (control-plane), `tyk-stack`, `tyk-dp` (data-plane), `tyk-oss` — each with its own Redis, and PostgreSQL where needed

## §6 row 4 — TC-04 Steps 4–10, ALL FOUR umbrellas · **PASS**

| Umbrella | Pods | All on `restricted-v2` | fsGroup in band | Null keys | Bootstrap Jobs |
|---|---|---|---|---|---|
| tyk-control-plane | 6 | 6/6 | ✅ 1001070000 | 0 | pre + post, real work |
| tyk-stack | 5 | 5/5 | ✅ 1001080000 | 0 | pre + post, real work |
| tyk-data-plane | 3 | 3/3 | ✅ 1001100000 | 0 | n/a (none shipped) |
| tyk-oss | 3 | 3/3 | ✅ 1001120000 | 0 | n/a (none shipped) |

All four installed with `helm install -f ci/no-securitycontext-values.yaml`, **zero Kustomize patches**,
`rc=0` on every install, zero SCC denial events, zero null keys on live API objects.

### Gap #4 CLOSED — bootstrap Jobs executed, for the first time in any automated test

```
pre-install  : "Pre-install Hook bootstrapping succeeded, the provided license is valid!"
post-install : "All Pods are ready"
               "Bootstrapping Tyk Dashboard"
               "Creating Kubernetes Secret for Tyk Operator" secretName=tyk-operator-conf
```

Real work, not empty logs — which is the packet's explicit pass criterion. **These Jobs carry
`hook-delete-policy: hook-succeeded` and delete themselves on success**, so the logs had to be
captured concurrently with the install. A post-hoc `oc logs` returns nothing, which is
indistinguishable from the genuine "completed with an empty log is a fail" case.

### Gap #3 CLOSED — dashboard, MDCB, pump and bootstrap opt-outs installed, not just rendered

Before today these had only ever been rendered. All are now running under `restricted-v2` with an
SCC-injected fsGroup and no chart-pinned UID anywhere.

## §6 row 12 — the headline AC · **PASS**

| Customer patch category | Still needed? |
|---|---|
| `fsGroup` patch | **NO** — SCC injects it; chart pins none |
| Init-container UID patch | **NO** — chart pins none; all pods up |
| `op: remove` null-key workaround | **NO** — zero null keys, live and rendered |

Aggregate across all four umbrellas: **0** chart-pinned fsGroup/runAsUser lines, **17** SCC-injected
fsGroups with **0** outside band, **0** null keys, **0** pods not Running, **0** pods off `restricted-v2`.

**Everything needed that was not a Tyk chart:** Redis and PostgreSQL security contexts disabled on
their own releases. Nothing else. That is gap #8 and it feeds §8 Q2.

⚠️ **Scope limit for sign-off:** one ROSA cluster, **single-AZ**, one pipeline. This is the customer's
real *platform*, which is stronger than the SNO the packet assumed — but it is not multi-AZ, and it
proves nothing about the customer's own Kustomize overlays. The residual-risk row should read
"real ROSA, single-AZ" rather than being retired.

## §6 row 6 — TC-06 Step 6 · **PASS**

Secret `mdcb-conn-live` with a **custom key** `mdcbUrl` (not the default `connectionString`), so
`connectionStringSecretKey` is exercised rather than the happy path.

```
fromSecret = mdcb-conn-live/mdcbUrl
resolved   = mdcb-svc-tyk-tyk-mdcb.tyk-qa.svc:9091     <- read from inside the container
gateway    = 1/1 Running, "--> Connected to DB", RPC policy/definition backups storing
```

Runtime resolution proven, not just the reference. Owner 1 owns Steps 1–5 including the
`useSecretName` upgrade regression, so **row 6 is now complete across both owners**.

## D-12 · environment · fresh ROSA serves two different API certs for ~30 min

Immediately after `ready`, the API load balancer fronts apiservers that have not all picked up the
public Let's Encrypt cert. Sampling 8 connections: 3 presented Let's Encrypt, **5 presented the
internal `kube-apiserver-lb-signer` cert**, which the system trust store rejects.

Measured failure rate: **60% of `oc` calls** (12 of 20), varying call to call.

This is vicious for QA specifically, because it is intermittent and non-deterministic: a failed
`oc get pod` looks like a missing pod, and SCC conclusions drawn through it would be transport
failures misreported as chart findings. It also killed the first automated run, whose abort logic
treated one failed `oc whoami` as proof the session was dead.

**Fix (used here):** build a CA bundle of the public roots **plus** the cluster's internal signer and
set it as `certificate-authority-data`. Failure rate went 60% → **0%**.
`--insecure-skip-tls-verify` also works but means every result arrives over an unverified
connection, which is a poor property for release-gating evidence.

**Belongs in the packet** — anyone running Owner 2's work against a fresh ROSA cluster will hit it,
and neither the packet nor the master plan mentions it. **Blocks 5.4.0: no** — it is a test-environment
issue, not a chart defect.

## D-13 · medium · the documented `preDelete.command` example cannot execute

`components/tyk-bootstrap/values.yaml` (mirrored into all umbrellas that ship bootstrap) documents
how to neutralise the pre-delete Job for GitOps environments:

```yaml
# command overrides the default container command. Use this to neutralise
# the pre-delete job in GitOps environments where you don't want Tyk to
# delete resources on Helm uninstall (e.g., ArgoCD app deletion).
# Example: ["/bin/sh", "-c", "echo 'Pre-delete disabled. No-op.'"]
```

**That example cannot run.** `tykio/tyk-k8s-bootstrap-pre-delete:v2.2.0` ships no shell:

```
Error: container create failed: executable file `/bin/sh` not found: No such file or directory
```

Reproduced twice — once through the chart (`--set tyk-bootstrap.bootstrap.jobs.preDelete.command[...]`)
and once with a bare Pod using the same image, to rule out the chart.

**Consequence is worse than the feature simply not working.** The Job sticks in
`CreateContainerError`, so `helm uninstall` blocks on its pre-delete hook until it times out:

```
Error: 1 error occurred:
  * timed out waiting for the condition
helm uninstall rc=1
```

The release is left undeleted — all 10 Tyk secrets and `sh.helm.release.v1.tyk.v1` still present —
and the user must intervene by hand. A customer following the documented example to make uninstall
*safer* instead makes it *hang*.

**Verified workaround:** override the image as well as the command, to something that has a shell.

```
--set tyk-bootstrap.bootstrap.jobs.preDelete.image.repository=busybox
--set tyk-bootstrap.bootstrap.jobs.preDelete.image.tag=1.36
--set 'tyk-bootstrap.bootstrap.jobs.preDelete.command[0]=/bin/sh' ...
```
Confirmed: pod `Succeeded` under `restricted-v2`, printing `Pre-delete disabled. No-op.`

**Suggested fix**, in preference order: (1) add a real `preDelete.enabled: false` toggle, since
neutralising the job is clearly the intended use case and is currently expressed as a hack;
(2) change the doc example to a command that exists in the image; (3) ship a shell in the image.

**Blocks 5.4.0: recommend a decision.** The GitOps/ArgoCD path is this ticket's headline use case,
`preDelete.command` exists specifically to serve it, and its only documented usage is impossible.
Not a security or admission issue, so not a P0 by the packet's definition — but it is a
customer-facing feature whose documentation is wrong in a way that breaks `helm uninstall`.

⚠️ Note this is **only reachable with Helm hooks enabled**. Under `disableHelmHooks=true` — the
actual ArgoCD configuration — the pre-delete Job is not rendered at all (TC-05 Step 3), so an
ArgoCD user never hits it. The users who hit it are Helm users who read the GitOps advice. That
lowers the severity but sharpens the docs problem: the advice is filed under a use case that
cannot reach it, which is the same defect shape as D-11.

---

# §6 row 5 — TC-05 Steps 6–7, through a REAL ArgoCD instance · **PASS**

**Operator:** Red Hat OpenShift GitOps **v1.21.4** from `redhat-operators` — the real thing, not the
community-manifest fallback the packet allowed as a documented downgrade.
**Application:** `repoURL https://github.com/TykTechnologies/tyk-charts`, `targetRevision 39957f3…`,
`path tyk-control-plane`, opt-out values supplied inline via `spec.source.helm.values`.

The opt-out files are not merged upstream, so inlining them in the Application is the faithful way to
test this — it is what a customer does when they do not want to fork the chart. ArgoCD resolved the
`file://` subchart dependencies without help because **`Chart.lock` is committed** for all four umbrellas.

## Step 6 — sync, and the ordering claim · **PASS**

```
sync=Synced   health=Healthy   phase=Succeeded   "successfully synced (all tasks run)"
```

Under `disableHelmHooks: true` the bootstrap Jobs render as **plain Jobs ArgoCD manages** (`hook=NONE`),
so sync-waves have real work to do. Observed ordering:

| Wave | Resource | Created |
|---|---|---|
| **-2** | `Role/k8s-bootstrap-role`, `ServiceAccount/k8s-bootstrap-role` | 20:28:47 |
| **-2** | `RoleBinding/k8s-bootstrap-role` | 20:28:48 |
| **-1** | `Job/bootstrap-pre-install` | 20:28:50 |
| **0** | `Deployment/{dashboard,gateway,mdcb}`, `Job/bootstrap-post-install` | 20:28:55 |

**The ordering is real, not incidental:** the pre-install Job reports
`completedAt=2026-09-07T20:28:54Z` and the Deployments were created at `20:28:55Z` — one second later.
Bootstrap finished *before* dependent workloads started. This is the claim render checks structurally
cannot make, and it is why §6 row 5 insists on "a real ArgoCD instance, not just `helm template`".

Zero manual Kustomize patches on Tyk components. All pods `Running`/`Completed`, Application `Healthy`.

## Step 7 — cleanup on Application deletion · **PASS, no docs defect**

| | Before | After deleting the Application |
|---|---|---|
| Tyk pods | 5 | 5 |
| Tyk secrets | 8 | 8 |
| pre-delete Job rendered | 0 | 0 |

Resources survive, because ArgoCD's default deletion is non-cascading without the
`resources-finalizer.argocd.argoproj.io` finalizer and **no pre-delete Job exists** under
`disableHelmHooks: true`. Cleanup is the user's responsibility.

**The docs state this correctly** — `components/tyk-bootstrap/values.yaml:211-213`:

> "This is unconditional: `bootstrap.jobs.preDelete.annotations` cannot bring the Job back, because
> the whole template is skipped before any annotation is evaluated. GitOps users who need
> deletion-time cleanup must run it outside this chart (e.g., a separately managed Job)."

Accurate, and it matches observed behaviour. No docs defect for Step 7.

## D-11 sharpened — the chart contradicts itself, in the same repo

The component chart's comment above is right. But every umbrella that ships bootstrap still carries,
**three times each** in `tyk-stack/values.yaml` and `tyk-control-plane/values.yaml`:

```yaml
# annotations adds annotations to the pre-delete Job metadata (e.g. ArgoCD sync waves).
# annotations:
#   argocd.argoproj.io/sync-wave: "2"
```

So one file says annotations on this Job **cannot** work under GitOps, and another offers a worked
ArgoCD example for exactly that. Proven earlier by direct probe: `sync-wave: "5"` renders **1** time
with hooks enabled and **0** times with them disabled.

The fix is to delete the worked example from the umbrellas, or qualify it with "only applies when
Helm hooks are enabled; ArgoCD users disable them, and then this Job is not rendered at all."
**Blocks 5.4.0: no.**

## §6 row 8 — TC-08 Steps 1, 5, 6 live · **PASS** (with two notes)

| Step | Result |
|---|---|
| 1 · `extraEnvs` from Secret **and** ConfigMap | **PASS — runtime proven.** Portal is distroless, so an ephemeral debug container read `/proc/1/environ`: `QA_FROM_SECRET=from-secret-tt17018`, `QA_FROM_CM=from-configmap-tt17018`, `QA_PLAIN=plain-still-works` |
| 5 · `bootstrapJob` image override | **PASS** — `curlimages/curl:8.8.0` → `8.10.1` on the live Job, pod on `restricted-v2`. The hardcoded image that blocked air-gapped users is genuinely overridable |
| 5 · `securityContext.enabled: false` | **PASS** — job ran under `restricted-v2` with no chart-set context |
| 5 · `curl_user` probe | **Caveat, not a pass** — see below |
| 6 · PVC writable under the opt-out | **PASS** — `/opt/portal/db` is `drwxrwsr-x 0 1001140000` (setgid, group-owned by the SCC-injected fsGroup), container runs as that UID, **write succeeded** |

Step 6 is the one no admission check could catch: with `fsGroup` omitted the SCC assigns the GID, and
if that plumbing were wrong the portal would start but be unable to write. It is correct.

### The `curl_user` probe — masked on OpenShift, still a hazard elsewhere

`curlimages/curl:8.8.0` declares a **symbolic** USER (`curl_user`). Setting `runAsNonRoot: true`
without a numeric `runAsUser` renders exactly that. Probed live:

```
phase=Succeeded  scc=restricted-v2  injectedRunAsUser=1001140000
```

OpenShift injects a numeric UID, so `runAsNonRoot` is satisfiable and **the hazard is masked here**.
A vanilla-Kubernetes user doing the same would get
`container has runAsNonRoot and image will run as root`. Record this as a passed-but-masked result,
not as evidence the configuration is safe generally.

## D-14 · low · docs · `bootstrapJob.imagePullSecrets` is a dead key

`components/tyk-dev-portal/templates/job-portal.yaml:14` reads **`.Values.imagePullSecrets`** — the
chart root — not `.Values.bootstrapJob.imagePullSecrets`. Probed both:

| Key set | Rendered `imagePullSecrets` on the Job |
|---|---|
| `tyk-dev-portal.bootstrapJob.imagePullSecrets[0].name` | `null` |
| `tyk-dev-portal.imagePullSecrets[0].name` | `- name: qa-regcred` |

The chart-root key also covers the portal StatefulSet, so one secret serves the whole chart — a
reasonable design. The problem is discoverability: `bootstrapJob:` has its own `image:`,
`securityContext:` and `containerSecurityContext:` blocks, so `bootstrapJob.imagePullSecrets` is the
natural guess, and it is a **silent no-op**.

**This is the third instance of the same defect shape on this ticket** — D-02 (operator's
`podSecurityContext` dead, `managerPodSecurityContext` live) and D-11 (advice filed under a use case
that cannot reach it). Worth calling out as a pattern at the review rather than three unrelated tickets.
**Blocks 5.4.0: no.** Fix is a comment under `bootstrapJob:` pointing at the root key.

## D-15 · low · the portal bootstrapJob blocks its own reconfiguration on upgrade

Unlike the `tyk-bootstrap` hook Jobs, the portal's bootstrapJob is a **plain Job with no
`helm.sh/hook-delete-policy`**, so it persists after completing. Job `spec.template` is immutable,
so any `helm upgrade` that changes the bootstrapJob's image, pull secrets or security context fails:

```
Error: UPGRADE FAILED: cannot patch "dev-portal-job-tyk-tyk-dev-portal" with kind Job:
  spec.template: Invalid value: {...}: field is immutable
```

So the new bootstrapJob configurability — TC-08 Step 5's whole point — **cannot be applied to an
existing release**. Workaround: `oc delete job dev-portal-job-<release>-tyk-dev-portal` first, which
is what was done here; the upgrade then succeeds (REVISION 3, image 8.10.1). **Blocks 5.4.0: no**,
but it makes a new feature unreachable by the normal upgrade path, and a `hook-delete-policy` or a
job-name suffix would fix it.

---

# §6 row 7 — TC-07 · **PASS** (with D-13 raised from Step 3)

## Step 2 · auth-requiring registry with a negative control — gap #7 CLOSED

Gap #7 is an **explicit acceptance criterion that had never been tested anywhere**. Built the
registry rather than requesting corporate access, exactly as S7 recommends:

- `registry:2` with **bcrypt** htpasswd (`registry:2` supports bcrypt only — SHA-512 crypt is
  silently rejected, worth knowing)
- exposed via an OpenShift **edge-terminated Route**, so it presents a Let's Encrypt cert the nodes
  already trust — no insecure-registry MachineConfig needed, which would have been disruptive
- auth proven before use: `GET /v2/` → **401 anonymous**, **200 with credentials**
- the real `tykio/tyk-k8s-bootstrap-pre-install:v2.2.0` copied in by an in-cluster `skopeo` Job

| Leg | Config | Result |
|---|---|---|
| **Negative control** | private image, **no** pull secret | **`ErrImagePull` → `ImagePullBackOff`** |
| **Positive** | same image + `bootstrap.imagePullSecrets` | **`install rc=0`**, pod `Succeeded` |

Positive-leg proof it genuinely pulled and ran from the private registry:

```
ServiceAccount k8s-bootstrap-role  imagePullSecrets=qa-regcred
bootstrap log: "Pre-install Hook bootstrapping succeeded, the provided license is valid!"
```

**Implementation note (not a defect):** `bootstrap.imagePullSecrets` lands on the **ServiceAccount**,
not the Job pod spec — pods using that SA inherit it, which is the idiomatic Kubernetes pattern. A
check that looks only at `.spec.template.spec.imagePullSecrets` will see `null` and wrongly conclude
the key is dead. It is not.

## Row 7 step summary

| Step | Result |
|---|---|
| 1 · `backoffLimit` **observed**, not read back | **PASS** — limit 0 → 1 pod (`failed=1`); limit 3 → 4 pods (`failed=4`) |
| 2 · auth registry + negative control | **PASS** — see above |
| 3 · `preDelete.command` override | **DEFECT — D-13.** The documented example cannot execute and hangs `helm uninstall` |
| 4 · `rbacAnnotations` on all three RBAC objects | **PASS** — ServiceAccount, Role and RoleBinding all carry `sync-wave=-1` on the live API, proving the server accepted a *string* |
| 5 · `disableHelmHooks` on a live install | **PASS** — covered by TC-05 Step 6, where the Jobs rendered as plain Jobs and ArgoCD ordered them by sync-wave |

§6 row 7 asks for "bootstrap verified **executing**, incl. an auth-requiring registry with a negative
control". Both are now evidenced. D-13 is a defect *found by* that verification, not an obstacle to
it — it belongs in the release decision, not in this row's status.
