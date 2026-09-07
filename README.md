# TT-17018 — QA workstreams (2 owners)

> ## ✅ Status: 2026-09-07 — **all QA testing complete. 10 of 14 sign-off rows closed.**
>
> Both owners tested `39957f3660212154296b6ffc9ab733f822e6809d`.
> **Nothing outstanding requires a cluster, a licence, or QA time** — the four open rows need
> three decisions and two pieces of writing. See **[What's left](#whats-left--nothing-here-needs-a-cluster)**.
>
> Results: [`owner-1-results/`](owner-1-results/README.md) · [`owner-2-results/`](owner-2-results/README.md)
>
> *The planning content below is preserved as written for the record — the calendar, effort estimates
> and day-0 checklist describe the plan going in, not what happened. Owner 2's five-day packet
> completed in one day, because most of its budget was discovery that turned out to be render work.*

Companion to `TT-17018-test-plan.md`. That document is the authority
on *what* and *why*. This directory splits it into **two packets** that two people can own and run
without blocking each other.

| File | For |
|---|---|
| [`00-shared-setup.md`](00-shared-setup.md) | Both owners. ~15 min read. |
| [`owner-1-kind-and-render.md`](owner-1-kind-and-render.md) | Owner 1 — kind & render. ~4 days. |
| [`owner-2-openshift.md`](owner-2-openshift.md) | Owner 2 — OpenShift. ~5 days. |

Each owner file is self-contained: setup steps, every command, and per step a **Validates / Pass /
Evidence** triplet so what sign-off requires is explicit rather than inferred. Neither owner needs
the 818-line master plan open to work.

---

## The split

Drawn on **environment**, because setup cost dominates everything else here. The result:
**Owner 1 never touches OpenShift, Owner 2 never touches kind.** One environment each, no
duplicated setup tax.

| | **Owner 1 — kind & render** | **Owner 2 — OpenShift** |
|---|---|---|
| **Test cases** | TC-04 Steps 1–3, TC-09, TC-10, TC-01, TC-02, TC-06 Steps 1–5, TC-11 | TC-03, TC-04 Steps 4–**11**, TC-05, TC-07, TC-08, TC-06 Step 6 |
| **Clusters** | kind 1.26 + 1.30, local | Dev Sandbox + one admin-capable cluster |
| **Effort** | ~4 days | ~5 days |
| **P0 work** | TC-01, TC-11 (+ TC-02 as a documented outcome) | TC-03, TC-04 |
| **Owns** | the upgrade risk — the largest untested surface on the ticket | gaps #2, #3, #4, #6 — everything CI never installed |
| **Skills** | Helm, kind, `crane`, `yq`, helm-unittest | OpenShift/`oc`, SCC, ArgoCD, private registry |
| **Also owns** | the 5.4.0 release note | the headline AC (TC-04 Step 11) and the Redis-on-OpenShift scope question (§8 Q2) |

**Total ≈ 9 person-days over ~5 calendar days**, after the scope trims below. The master plan's "4–5 working days for one QA
engineer" (§5) excludes environment setup and assumes every install works first time. Treat it as
best case.

### Why two test cases are split down the middle

Neither TC-04 nor TC-06 is a single unit of work, and treating them as one would wreck the balance:

- **TC-04 Steps 1–3 are desk work; Steps 4–10 need a live cluster.** Steps 1–3 *produce* the three
  missing `ci/no-securitycontext-values.yaml` files; Steps 4–10 *consume* them. Kept together, all
  OpenShift work would sit behind one person's morning at a text editor.
- **TC-06 Steps 1–3 and 5 are renders, Step 4 is an upgrade regression, only Step 6 needs a
  cluster.** Step 4 runs fine on kind and belongs with Owner 1's other upgrade work. Without this
  move Owner 2 lands at ~6.5 days and becomes the entire critical path.

---

## Handoffs — both from Owner 1 to Owner 2, both on day 1

Owner 2's TC-04 is **blocked** until these land. They are Owner 1's first task of day 1, time-boxed
to the morning.

| # | What | Why Owner 2 needs it |
|---|---|---|
| 1 | Three `ci/no-securitycontext-values.yaml` files (`tyk-control-plane`, `tyk-stack`, `tyk-data-plane`) | TC-04 Steps 4–10 install with these. They don't exist in the repo yet — only `tyk-oss` has one. |
| 2 | The **gap #9** operator verdict | All umbrellas expose only `tyk-operator.podSecurityContext`, but the template reads `.Values.managerPodSecurityContext`. If confirmed broken, Owner 2 can't opt the operator out through the documented surface and must set the other key directly. |

Soft handoffs, useful but not blocking:

- **Owner 1 → Owner 2:** the per-component image-`USER` table from TC-02 Step 1 (the real non-root
  tag boundary), and the TC-06 secret name/key so Owner 2's live check matches the renders.
- **Owner 2 → Owner 1:** the OpenShift docs gaps for the §6 row 14 doc work, and the
  Redis/PostgreSQL workaround for §8 Q2.

---

## Calendar

| Day | Owner 1 — kind & render | Owner 2 — OpenShift |
|---|---|---|
| **0** | Shared actions below (30 min, together) | Shared actions + request the Partner Lab |
| **1 AM** | Setup · **TC-04 Steps 1–3 → hand to Owner 2** | Kick off the SNO install · provision Sandbox |
| **1 PM** | TC-09 (incl. anti-vacuity check), TC-10 | TC-05 Steps 1–5 (renders, no cluster) · **TC-03 on Sandbox** |
| **2** | TC-01 on kind 1.26 — `tyk-oss`, `tyk-data-plane` | Redis/PostgreSQL on OpenShift (S6) · TC-04 Steps 4–9 on `tyk-control-plane` |
| **3** | TC-01 on kind 1.30 + `tyk-stack` · TC-02 | TC-04 Steps 10–11 (`tyk-stack`, `tyk-data-plane`, **headline AC**) · TC-05 Steps 6–7 (real ArgoCD) |
| **4** | TC-11 on kind 1.26 and 1.30 · TC-06 Steps 1–5 | TC-07 (bootstrap executing, self-hosted registry) |
| **5** | Write-up · defects · release note | TC-08 · TC-06 Step 6 · write-up · defects |

Owner 2's day 1 is deliberately cluster-free work — the cluster install (~1 hour unattended) and the
Sandbox provisioning run in the background while the TC-05 renders and TC-03 get done.

---

## Day-0 actions — 30 minutes, both owners together

Shared inputs. Without them, several tests produce results that can't be aggregated or trusted.

- [ ] **Pin the SHA.** One person clones `main` and records `git rev-parse HEAD` on TT-17018.
      Both owners test *that* SHA. Master plan §3.8 — `main` has moved since merge `61e5cf1`
      (`462900f`, then reverted by `4e0f1be`). Results against different trees don't aggregate.
- [ ] **Request the Red Hat OpenShift Partner Lab — it's free, and it has lead time.** Purpose-built
      for "testing and certification of containers and operators or **Helm charts**", reservable 1 day
      to 1 month. Tyk ships a certified operator, so eligibility is likely. Confirm two things when
      requesting: it runs **Mon–Fri 08:00–18:00** only, and that you get **cluster-admin**. If there's
      no answer in a day or two, fall through to the next item rather than waiting.
- [ ] **Otherwise, provision Owner 2's cluster: Single Node OpenShift on one x86_64 cloud VM.**
      8 vCPU / 32 GB / 120 GB+, ~$84/week continuous or ~$40/week stopped overnight and at weekends.
      **Neither laptop can host this** — both are 16 GB Apple Silicon, and CRC-on-a-cloud-VM is not a
      workaround because CRC's own docs state it doesn't support nested virtualisation. Details and
      the free local-CRC stopgap: [`owner-2-openshift.md` S4](owner-2-openshift.md#s4--your-admin-capable-cluster--half-a-day-to-a-day).
- [ ] **Resolve licences.** Dashboard licence for TC-01's `tyk-stack` leg, TC-02, TC-04, TC-05,
      TC-07, TC-08; MDCB for TC-06. Check how many **concurrent** dashboard installs it allows —
      both owners may want one on days 2–3. **This is the only genuine long-lead item.**
- [ ] **Agree the P0 rule now.** Master plan §8 Q3: the change is already on `main`, so if QA finds
      a P0 — revert, or fix forward before the 5.4.0 cut? Decide before you're under pressure on
      day 4. Either owner hitting a P0 escalates the **same day**; do not batch to the write-up.

---

## Sign-off tracker

**Status 2026-09-07 — 10 of 14 rows closed. All QA testing is complete.**

Both owners tested the same tree, `39957f3660212154296b6ffc9ab733f822e6809d`, so the evidence
aggregates. The four open rows need **decisions and writing, not tests** — see
[What's left](#whats-left--nothing-here-needs-a-cluster) below.

Evidence: [`owner-1-results/`](owner-1-results/README.md) (kind & render) ·
[`owner-2-results/`](owner-2-results/README.md) (OpenShift).

| # | Sign-off item | Owner | P0 | Status |
|---|---|---|:--:|:--:|
| 1 | TC-01 passes on k8s 1.26 and 1.30 for `tyk-oss`, `tyk-data-plane`, `tyk-stack`, with and without `--reuse-values` | 1 | ● | ◐ evidence complete, all four umbrellas both k8s versions — **held open only by the D-01 decision** |
| 2 | TC-02 outcome documented, pinned-old-tag decision explicitly made | 1 → team | ● | ◐ evidence complete — **team decision owed** (§8 Q1) |
| 3 | TC-03 reproduced by QA on a real, unprivileged OpenShift cluster | 2 | ● | **☑ CLOSED** — Sandbox 4.21.30, unprivileged |
| 4 | TC-04 all four umbrellas; three values files **authored and TC-04 passing with them**; gap #9 resolved — see note | 1 + 2 | ● | **☑ CLOSED** — all four on ROSA, rc=0 each, zero patches, all four serving traffic |
| 5 | TC-05 passes through a real ArgoCD instance, not just `helm template` | 2 | | **☑ CLOSED** — real ArgoCD, sync-wave ordering proven |
| 6 | TC-06 incl. the `useSecretName` + literal `connectionString` upgrade regression | 1 + 2 | | **☑ CLOSED** — Owner 1 S1–5, Owner 2 S6 live |
| 7 | TC-07 bootstrap verified **executing**, incl. an auth-requiring registry with a negative control | 2 | | **☑ CLOSED** — auth registry + negative control; raised D-13 |
| 8 | TC-08 dev portal verified **running** with all three new config paths | 2 | | **☑ CLOSED** — portal running, PVC writes |
| 9 | TC-09 green on merged `main`, **with the anti-vacuity revert check done** | 1 | | **☑ CLOSED** — 216/216, revert goes red |
| 10 | TC-10 zero field leaks under **server-side** dry-run | 1 | | **☑ CLOSED** — 8/8 components, both k8s versions |
| 11 | TC-11 green on k8s **1.26 and 1.30** (the ends; middle versions only if they disagree) | 1 | ● | **☑ CLOSED** — all six steps, both versions |
| 12 | **Headline AC proven by QA** — four umbrellas installed on OpenShift with zero Kustomize patches on Tyk components, and the customer's three known patch categories confirmed unnecessary *(replaces TC-12)* | 2 | | **☑ CLOSED** — four umbrellas, zero Kustomize patches |
| 13 | Upgrade release note reviewed and published in the 5.4.0 changelog | 1 | | ◐ draft written — **needs a home** (no CHANGELOG) |
| 14 | OpenShift docs cover the `enabled: false` opt-out (and why `{}` doesn't work), the Redis/PostgreSQL caveat, and the per-component image-tag boundary | 1 + 2 | | ◐ both owners' inputs delivered — **write-up outstanding** |

Rows 4, 6 and 14 are the shared ones — neither owner can close them alone.

> **Row 4 — no PR is required to validate this.** The master plan's §6 row 4 asks for the three
> `ci/no-securitycontext-values.yaml` files to be **merged**. They are *inputs* to TC-04, and
> `helm install -f <path>` behaves identically from a working copy — so the gate is *"authored,
> attached to TT-17018, TC-04 passes with them"*.
>
> Merging wouldn't close the CI gap anyway: CI never runs `ct install` (only `ct lint --all`), and the
> `smoke-tests-no-securitycontext` job hardcodes `./tyk-oss/ci/no-securitycontext-values.yaml`
> against `tyk-oss` alone — so extra files add **no install coverage** without also editing
> `run-tests.yaml`. Both belong in §7 beside §7.4. Gating release sign-off on someone else's code
> review would import a dependency QA doesn't control, on a ticket already flagged for merging before
> QA ran.
>
> **Rows 13 and 14 are release deliverables, not validation** — a changelog entry and docs. They gate
> the release, not the evidence. Do them after the testing, and don't let them displace it.

---

## What's left — nothing here needs a cluster

**All 12 test cases across both packets are complete.** The remaining work is decisions and writing.

### Three decisions the team owes

| # | Question | Evidence | Why it is blocking |
|---|---|---|---|
| **§8 Q3** | **D-01** — `helm upgrade --reuse-values` silently breaks the gateway's file writes. **Revert TT-17018, or fix forward before the 5.4.0 cut?** | [Owner 1](owner-1-results/README.md) | No admission failure, readiness probe passes, no warning events — it escapes every automated gate in the pipeline. Row 1 names both upgrade paths, so it cannot be signed off as-is. |
| **§8 Q1** | **Pinned-old-tag upgrades** — release note only, or a `NOTES.txt` warning / `semverCompare` guard? | [Owner 1](owner-1-results/README.md) | Most likely support-ticket generator in 5.4.0. Recommendation on file: ship the note with the `--reuse-values` hazard and the tag bands added, and a `NOTES.txt` warning for the silent case only. |
| **NEW** | **D-13** — the documented `preDelete.command` neutralisation cannot execute and **hangs `helm uninstall`**. Fix the docs, ship a shell in the image, or add a real `preDelete.enabled: false`? | [Owner 2](owner-2-results/README.md) | The GitOps path is this ticket's headline use case, `preDelete.command` exists to serve it, and its only documented usage is impossible. |

### Two pieces of writing

| # | Item | Owner | State |
|---|---|---|---|
| **Row 13** | Upgrade release note | 1 + repo owner | **Draft written**, covering D-01 and D-05. Blocked only on *where it goes* — `tyk-charts` has no CHANGELOG. Suggestion: the GitHub Release body, which exists and needs no new process. ~15 min once decided. |
| **Row 14** | OpenShift docs | 1 + 2 | Both owners' inputs delivered. Needs: the `enabled: false` opt-out and why `{}` is a silent no-op; the image-tag bands (D-05); the Redis/PostgreSQL story (D-06), now fully characterised by Owner 2's S6 work. ~half a day. |

### Worth ten minutes at the review

**D-02, D-11 and D-14 are the same defect three times** — a values key or a piece of documented advice
that looks correct and silently does nothing:

- **D-02** — the operator's `podSecurityContext` is dead; `managerPodSecurityContext` is live
- **D-11** — `preDelete.annotations` is documented with an ArgoCD example, in a case where the Job cannot render (and the component chart says so, while both umbrellas contradict it 3× each)
- **D-14** — `bootstrapJob.imagePullSecrets` is dead; the chart-root `imagePullSecrets` is live

One conversation about the pattern is worth more than three tickets.

### Accepted residual risk — state it explicitly at sign-off

| Not covered | Assessment |
|---|---|
| **Multi-AZ ROSA** | TC-04 and TC-05 ran on **real ROSA** — the customer's actual platform, materially stronger than the SNO the plan assumed — but **single-AZ**. Everything in scope is node-count-independent. The row should read *"real ROSA, single-AZ"*, not be marked retired. |
| **The customer's ArgoCD + Kustomize overlays** | TC-05 proves the chart syncs through a real ArgoCD instance with correct sync-wave ordering. It cannot prove anything about overlays we do not have. The larger of the two gaps. |
| **The 24 → N patch-count delta** | Tyk components provably need **zero** patches. The customer's arithmetic needs their overlays. The AC is answered; the number is not. |


---

## Residual risk, accepted knowingly

**Nothing in this pass depends on the customer.** The master plan made TC-12 a sign-off gate: send
the merged chart to the customer, have them redeploy on ROSA across three regions, and report how
many of their 24 Kustomize patches remain. That is **removed**. It put a release gate on a third
party's response time — the last round-trip took roughly a month — and it asked someone outside the
team to produce the evidence for the ticket's *headline* acceptance criterion.

**The criterion is still validated, by Owner 2, directly.** TC-04 Step 11 installs all four umbrellas
on OpenShift with zero Kustomize patches and checks each of the customer's three known patch
categories — the `fsGroup` patch, the init-container UID patch, and the `op: remove` workaround for
null labels/annotations — against the live install. That is better evidence than a patch count in an
email, because it arrives with commands and output.

**What is genuinely no longer covered, and should be stated at sign-off:**

| Not covered | Assessment |
|---|---|
| **Real multi-AZ ROSA** | Both owners are on single-node clusters. Modest exposure: everything in scope — SCC admission, annotation quoting, bootstrap ordering, securityContext omission — is **node-count-independent**. There is no mechanism by which three AZs behave differently from one for these changes. |
| **The customer's specific ArgoCD + Kustomize pipeline** | TC-05 proves the chart works through a real ArgoCD instance with sync waves and hooks disabled. It cannot prove anything about the customer's own overlay structure. This is the larger of the two gaps. |
| **The 24 → N patch-count delta** | We can prove Tyk components need **zero** patches. We cannot produce the customer's arithmetic, because we don't have their overlays. The AC is answered; the specific number isn't. |

Both are **acceptance decisions, not QA findings** — the review should accept them explicitly rather
than have someone discover the omission later. If the customer volunteers a report during the week,
treat it as a bonus data point, never as a gate.

## Already found: three defects in the master plan's own commands

All surfaced before day 1, and all would have produced misleading results wherever the tests ran.
Fixed in the owner packets; flagged here because the Thursday review should see them. **The good news
first: the ticket's central premise was checked and it holds — see defect 2.**

**1 — TC-02 Step 1's image loop names two repositories that don't exist.** It iterates
`tyk-gateway tyk-dashboard tyk-pump tyk-sink portal`, but there is no `tykio/tyk-pump` (it's
`tykio/tyk-pump-docker-pub`) and no `tykio/tyk-sink` (it's `tykio/tyk-mdcb-docker`). As written it
silently reports nothing for pump and MDCB — on the one step whose purpose is proving *every* default
image has a numeric non-root USER. The corrected loop also adds the operator and the three bootstrap
images, which the master plan omitted entirely.

Worse, the loop also targets the wrong **registry**: the gateway and pump are pulled from
**`docker.tyk.io`**, not Docker Hub, so `crane config docker.io/tykio/…` could never have resolved
them. The replacement command reads whatever the chart actually renders, at whatever registry, so it
can't drift.

**2 — the gateway's image USER is not monotonic. Checked against `main`, and the premise holds.**
The change rests on "removing container-level `runAsUser` is safe because default image tags were
bumped". The non-root change was backported into the 5.8.x LTS line at **v5.8.13** but reached
mainline only at **v5.13.0** — so **v5.9.0 through v5.12.0 all still declare `USER 0`**, a trap for
anyone re-pinning tags later.

**✅ Verified 2026-08-20 on `main`: the gateway default is `v5.13.1` → `USER 65532`, in the safe
band.** Dashboard v5.13.1, pump v1.16.0, MDCB v2.12.0, portal v1.18.0, operator v1.4.2 and all three
bootstrap images at v2.2.0 are likewise numeric `65532`. So this is **not** a P0 — but it is a
standing re-pin hazard, and Owner 1 re-confirms it against the pinned SHA as a two-minute desk check
(TC-02 Step 1b).

**3 — two helper images are not numeric, and the audit had never covered them.** Both are init/helper
images TC-02 never looked at:

- **`busybox:1.32`** (gateway `setupDirectories` init container) has **no USER at all**. Safe as
  shipped, because the chart pins `runAsUser: 65532` on that container precisely for this reason —
  but disabling *only* the init container's own `securityContext` makes the template fall back to
  `gateway.containerSecurityContext`, which asserts `runAsNonRoot: true` with no UID. On OpenShift
  the SCC rescues that; on **vanilla Kubernetes it is an admission failure**. The opt-out values
  files must disable **all three** blocks, which is why they're written that way.
- **`curlimages/curl:8.8.0`** (portal `bootstrapJob`) has a **symbolic** USER, `curl_user`. Inert
  today because the bootstrap job renders no securityContext — but TC-08 Step 5 is exactly where
  someone starts setting those fields, so Owner 2 probes it deliberately.

Also confirmed while checking: `tyk-oss/Chart.yaml` on `main` reads **`version: 5.3.0`** against a
fix version of 5.4.0, so §8 Q4 is a real open question; and every Tyk component publishes both amd64
and arm64. One image remains unchecked — `gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0`, the operator
sidecar.

## Open questions for the Thursday review

Master plan §8, with who brings the evidence:

| # | Question | Evidence from |
|---|---|---|
| 1 | Pinned-old-tag upgrades: release note only, or a `semverCompare` guard / `NOTES.txt` warning? Most likely support-ticket generator in 5.4.0. | Owner 1, TC-02 |
| 2 | Scope of "no Kustomize patches" — Tyk components only? Redis/PostgreSQL will still need patches. Needs stating in the AC and docs, and agreeing with the customer. | Owner 2, S6 |
| 3 | The change is already on `main`. If QA finds a P0 — revert, or fix forward before the 5.4.0 cut? | either |
| 4 | `main` reads chart version `5.3.0` while the fix version is Charts 5.4.0. Confirm the release-prep bump is tracked separately. | Owner 1 |
| 5 | ~~TC-12 ownership and deadline~~ — **moot, TC-12 is removed.** Replaced by: does the review accept single-node OpenShift evidence for the headline AC, with multi-AZ ROSA as documented residual risk? | Owner 2 |
| 6 | Gap #9 — expose `managerPodSecurityContext` in the umbrella values? Remove or document the dead `podSecurityContext` key? | Owner 1 (verdict) + Owner 2 (impact) |
| 7 | **New** — confirm the scope trims: no PR for row 4, self-hosted registry for row 7, TC-11 at the matrix ends, rows 13–14 as release deliverables. Each is listed under "Deliberately not doing" in the owner packets. | either |

---

## Reporting

Both owners report the same way so results aggregate rather than needing translation on day 5.
Format, defect conventions and the two **known-expected failures**:
[`00-shared-setup.md`](00-shared-setup.md#reporting-results).
