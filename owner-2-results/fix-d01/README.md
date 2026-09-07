# D-01 — a prototyped, tested fix-forward option

**Not a merge request.** This exists so the revert-or-fix-forward decision (§8 Q3) can be made
against something concrete rather than an estimate. It is a two-file change, it resolves the defect,
and it passes the existing suite unchanged.

## Is `--reuse-values` actually a common path?

Worth settling, because it determines whether D-01 is a real hazard or a curiosity.

| Question | Answer |
|---|---|
| Does it run automatically? | **No.** It is never implicit; someone has to type it. |
| Do Tyk's docs tell users to use it? | **No.** Searched every `*.md` in the repo — zero mentions. Every documented upgrade is a plain `helm upgrade`. |
| Does Tyk's own CI use it? | **Yes, twice** — `run-tests.yaml:109` and `:144`. |
| Would a real user reach for it? | **Very likely**, and the chart's own design pushes them there — see below. |

**Why users end up using it.** Tyk's documented install passes configuration through `--set` flags —
Redis address, PostgreSQL host and password, dashboard licence, MDCB licence. Since Helm 3, a plain
`helm upgrade` **does not carry those forward**: it takes chart defaults plus whatever `--set` you
supply on that command. So an operator upgrading has two options: retype every flag exactly, or add
`--reuse-values`. The second is the obvious choice, it is the idiom Helm documents for this, and it
is what Tyk's own CI does.

So: not automatic, not documented by Tyk, but a natural landing place for anyone who installed the
documented way. **The severity comes from the failure mode, not the frequency** — the rollout reports
success, pods go Ready, the health probe passes, and no warning events fire. The first symptom is a
`500` when something writes.

## Root cause

Released 5.3.0 renders the `setup-directories` init container from
`gateway.containerSecurityContext` — there is no init-specific key in that chart. `main` gives the
init container its own block, defaulting to `runAsUser: 65532`.

`--reuse-values` carries the operator's old `containerSecurityContext.runAsUser: 1000` forward, but
**cannot supply a value for a key that did not exist in the old release**, so the init block takes
the new chart default. Result: init runs as 65532, gateway runs as 1000. The init container creates
`apps/`, `middleware/` and `policies/` in the `tyk-scratch` emptyDir owned by 65532; the gateway
cannot write into them.

## The fix

Two files. The template already had a fallback chain from the init block to the main container's —
it was simply never reachable, because the init block now ships populated.

1. **`values.yaml`** — stop pinning `runAsUser: 65532` in the init block, so "the user chose 65532"
   becomes distinguishable from "this is the chart default". (Helm cannot otherwise tell them apart.)
2. **`deployment-gw-repset.yaml`** — resolve the init UID: **its own value if set, else the main
   container's if set, else 65532.**

See [`d01-fix.patch`](d01-fix.patch).

## Verified behaviour

| Scenario | init UID | main UID | Correct? |
|---|---|---|---|
| Fresh install, no customisation | `65532` | *(none)* | ✅ busybox has no `USER`, so it needs a numeric UID |
| **Operator pinned main to 1000 — the D-01 case** | **`1000`** | **`1000`** | ✅ **aligned; defect resolved** |
| Both pinned explicitly (main 1000, init 2000) | `2000` | `1000` | ✅ an explicit init value still wins |
| OpenShift opt-out file | *(none)* | *(none)* | ✅ block omitted, SCC assigns |

**Regression check:** `helm unittest` across all six charts with tests —
**216 passed / 216 total, 31 suites**. Byte-identical to the unpatched baseline.

## What this does not do

- **Not tested live.** The render matrix and unit suite pass; an end-to-end
  `install 5.3.0 → upgrade --reuse-values → write an API` run against this patch has **not** been done.
  That is the obvious next step if the decision is to fix forward.
- **Does not fix the stale image.** `--reuse-values` also carries the old `image.tag` forward, so the
  gateway stays on the pinned version. That is expected `--reuse-values` behaviour, not a chart
  defect, but it means an operator can still end up on an old image believing they upgraded.
- **Only covers the gateway.** The dashboard's `initAnalyticsConf` init container has the same shape
  and was not examined for the same hazard.

## The alternative, for comparison

A `NOTES.txt` warning plus a release-note entry naming `--reuse-values`, with
`--reset-then-reuse-values` as the documented repair (Owner 1 verified that recovers a broken release
on the spot). Cheaper, and it ships no template risk — but it depends on the operator reading it,
and this failure is silent precisely when they have not.
