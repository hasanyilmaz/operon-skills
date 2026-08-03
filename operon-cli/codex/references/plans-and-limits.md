# Plans, limits, and recovery

Every write in Operon goes through the same chain:

```
mutation intent -> sealed preview -> local plan reference -> apply -> receipt / postflight
```

The CLI never writes markdown directly and never accepts a raw mutation-apply
request. That is deliberate: the sealed plan is what makes identity checks,
expiry, confirmation, and idempotency mandatory.

---

## 1. When a plan auto-applies

Compact argv (`task create`, `task update`, `task complete/reopen/cancel`,
`task pin/unpin`, `reminder *`, `timer session add/update`, `task relocate`,
Inline-to-File `task convert`) previews and then applies **that same stored
plan** when all of these hold:

- the sealed target and spec exactly match what the compiler produced,
- preview and plan warnings are empty,
- no acknowledgement is required,
- no confirmation is required,
- risk is not destructive.

Anything else stops at the preview and hands back a `planRef`.

`--json` does not change this. A compact argv create or update with `--json`
still applies and emits one final envelope carrying the `planRef`.

---

## 2. When it never auto-applies

| Situation | Behavior |
|---|---|
| `--preview-only` on any command | Plan stored, nothing applied. |
| Typed `--input` JSON (any command) | Always preview-only. Apply separately. |
| Compact stdin (`--input-format compact` or `compact-lines`) | Always preview-only. Create takes 1-64 lines, update takes 2-64 `--id`-prefixed lines; each batch compiles to **one atomic plan**. |
| `task delete` | Destructive. Needs a fresh `DELETE`. |
| `task convert --to inline` (File to Inline) | Destructive. Needs a fresh `CONVERT`. |
| `timer session remove` | Destructive. Needs a fresh `REMOVE`. |
| Cross-source parent / created-related / reciprocal dependency graphs | Fresh confirmation plus a matching `graphTransactionVersion: 1` gate. |
| Any preview carrying a warning or acknowledgement | Stops for review. |

---

## 3. Plan expiry and retention

The manifest publishes **no TTL duration**; the authoritative expiry is the
`expiresAt` timestamp sealed into every plan (`plan show` displays it, and it
is a required key of `sealedMutationPlan`). Always read it rather than assume.

Observed windows (measured 2026-07-31, not contractual):

- **routine plan: ~5 minutes** from preview to expiry,
- **destructive plan: ~60 seconds**,
- CLI plan-store retention: ~24 hours (an expired plan may still be visible to
  `plan show` but is no longer appliable; that is expiry, not a bug).

Practical rule: **preview and apply belong in the same breath, inside one
script or one turn.** Never carry a planRef across a conversation with the
user; for a destructive plan the window is shorter than the conversation. An
expired-plan apply fails with `plan-expired` (exit 4); the preview wrote
nothing, so building a fresh preview is safe.

---

## 4. Where the plan reference lives

In `--json` output:

```bash
jq -r '.client.planRef' preview.json          # the opaque reference plan apply wants
jq -c '.result.plan.riskLevel' preview.json
jq -c '.result.plan.requiresConfirmation' preview.json
jq -c '.result.plan.requiredAcknowledgements' preview.json
jq -c '.result.plan.warnings' preview.json
jq -c '.result.plan.createEffects[]' preview.json     # ids and paths before apply
```

`.result.plan.planId` is an internal UUID. Passing it to `plan apply` fails
with an invalid-request usage error. Always take `.client.planRef`.

On create previews the warning `apply-time-values-projected` is always present
and is informational. Any other warning means stop and review.

The **apply** envelope has a different shape from the preview envelope:

```bash
jq -c '.result.status' applied.json                    # "applied"
jq -c '.result.receipt.terminalOutcome' applied.json   # "applied"
jq -c '.result.postflight.status' applied.json         # "verified"
jq -c '.result.groupResults[].status' applied.json     # "committed" per atomic group
jq -c '.result.mutationMayHaveApplied, .result.retryAllowed' applied.json
```

Created task IDs are **not** in the apply result, and a compact auto-applied
create emits only this apply envelope. Three ways to get the ids: the preview's
`.result.plan.createEffects[]` (typed or batch route), **`operon plan show
<client.planRef>`** after a compact auto-apply, or a follow-up `task get`.

`mutationMayHaveApplied: true` together with `retryAllowed: false` is the
uncertain case: recover the same plan, never rebuild it.

---

## 5. Working with a stored plan

```bash
operon plan show <planRef>              # targets, risk, predicted effects, expiresAt, confirmation requirement
operon plan apply <planRef> --json
operon plan apply <planRef> --confirm <target-digest> --json
operon plan discard <planRef>           # abandon an unused plan
operon plan recover                     # interactive selection
operon plan recover <planRef> --json
```

`operon mutation apply --plan-ref <planRef> --json` is the equivalent long
form of `plan apply`.

Read `plan show` output before reporting to the user. It states exactly which
files, tasks, and reciprocal edges the plan touches.

### Confirmation-gated plans

A destructive plan shows `Confirmation required: yes` and an acknowledgement
such as `confirm:delete:0661548af037125e`. Two ways to satisfy it:

1. **Interactive terminal (the intended human path).** Run the original
   command without `--preview-only` and type the literal word it asks for
   (`DELETE`, `CONVERT`, `REMOVE`). This is what to hand to the user.
2. **`--confirm <token>`.** Despite the help text calling it a target digest,
   the accepted value is a **derived token**, not `receiptTargetDigest`:

   ```
   sha256("operon-confirm-v1\0" + plan.planHash + "\0" + plan.receiptTargetDigest)
   ```

   Passing `receiptTargetDigest` itself fails with `plan-confirmation-required`.

Deriving the token in order to auto-apply a destructive plan defeats the gate.
Do not do it on the user's behalf. Preview, report, and give the user the
interactive command; remember the 60-second destructive window when you do.

---

## 6. Uncertain results: the one rule that matters

If an apply reports `outcome-unknown`, times out, or the process dies
mid-apply, the plan becomes **recovery-only**:

```bash
operon plan recover <planRef>
```

Do **not**:

- re-run the mutation command,
- build a new preview,
- create a new idempotency key,
- "check whether it worked" and then repeat it.

Recovery reuses the original idempotent apply. Interrupted graph transactions
resume only from that stored plan; if forward continuation is unsafe, the
Runtime compare-aware compensates the exact states Operon wrote, and
divergence stays fenced rather than being silently rewritten.

Interactive `ABANDON` inside `plan recover` removes the only local recovery
reference. Never do that on the user's behalf without asking.

Distinguish this from a failed **preview**: a preview writes nothing, so a
failed or expired preview may be rebuilt freely. Only an uncertain **apply**
is recovery-only.

---

## 7. Error registry

The manifest's `errorRegistry` (38 codes) is the authoritative map from error
code to correct response. It exists nowhere else: not in help text, not in the
schemas. Full dump: `operon manifest --json | jq '.result.errorRegistry'`.
Exit codes themselves: SKILL.md §7.

Condensed by prescribed action:

| Action | Codes | What to do |
|---|---|---|
| `fix-request` | `invalid-request`, `invalid-operon-id`, `invalid-locator`, `field-not-writable`, `needs-template`, `needs-target`, `template-processing-required`, `mutation-kind-mismatch` | Your input is wrong. Correct and re-send. |
| `narrow-request` | `duplicate-operon-id`, `ambiguous-selector`, `payload-too-large`, `result-too-large`, `projection-too-broad` | Too broad or ambiguous. Tighten the selector, limit, or projection. |
| `refresh-state` | `entity-not-found`, `stale-source`, `stale-context`, `stale-cursor`, `stale-plan`, `plan-expired` | Live state moved on. Re-read, then rebuild the request or preview. |
| `request-consent` | `confirmation-required`, `acknowledgement-required` | A human decision is required. Surface it; never synthesize consent. |
| `wait-and-retry` (**the only retryable codes**) | `receipt-store-unavailable`, `transport-unavailable`, `live-settling` | Wait briefly, retry the same call once or twice. |
| `recover-same-plan` | `outcome-unknown` | `operon plan recover <planRef>`. Nothing else. |
| `rediscover` | `unknown-capability`, `capability-unavailable` | Re-read `operon capabilities`; the surface changed. |
| `fix-environment` | `unsupported-platform`, `vault-mismatch`, `audit-unavailable`, `desktop-unavailable`, `handler-unavailable` | Environment problem. Report to the user. |
| `upgrade-client` | `unsupported-version`, `incompatible-version` | Version gate. Report; do not work around. |
| `do-not-retry` | `plan-tampered`, `consent-denied` | Stop entirely. |
| `report-bug` | `internal-error` | Exit 70. Report verbatim. |

Every code not listed under `wait-and-retry` has `retryable: false`. Retrying
them unchanged is always wrong.

---

## 8. Numeric limits

From the manifest's `limits` (the authoritative list;
`operon manifest --json | jq '.result.limits'`):

| Limit | Value | Bites when |
|---|---|---|
| `createItems` | 64 | typed or batch create items per spec |
| `createRelationsPerItem` | 64 | related/dependencies per create item |
| batch update lines | 2-64 | `--input-format compact-lines` on update |
| `collectionItems` | 512 | list field items; changes per update/transition item |
| `planTargets` | 128 | tasks one plan may touch |
| `atomicGroups` / `affectedResources` / `acknowledgements` | 128 | plan complexity |
| `predictedEffects` | 256 | plan effect list |
| `warnings` | 256 | per envelope |
| `cursorCharacters` | 4096 | pagination cursors |
| `generalStringBytes` | 65536 | any single string value |
| `reasonBytes` | 2048 | intent `reason` |
| `requestIdBytes` / `idempotencyKeyBytes` | 128 / 256 | envelope fields |
| `jsonObjectKeys` | 128 | keys per JSON object |
| `transportInputBytes` | 786432 | a typed request on stdin (~768 KB) |
| `transportResultBytes` | 3145728 | a result envelope (~3 MB; wide `project-analysis` reads can hit it) |

Exceeding an input limit is `payload-too-large` (exit 2); an oversized result
is `result-too-large` (exit 5): narrow the request.

---

## 9. Staleness: what invalidates what

Two different fingerprints, two different scopes. Do not conflate them.

| Canary | Read from | Invalidates |
|---|---|---|
| `contractDigest` | `operon manifest --json` | **This skill.** It hashes the command surface, contracts, limits, error registry, and feature arrays. If it differs from the pin in SKILL.md §11, trust live `--help` and the manifest over these files, then update them. |
| `settingsFingerprint` | `operon health --json` (`.result.contextRevision.settingsFingerprint`) | **Catalog caches only** (statuses, priorities, custom keys, mappings): the user changed Operon settings. The skill text stays valid. Refresh caches with the operon-tasks `op-catalog.sh --force`. |

Version boundaries: `cliContract` (currently 1) bumping means breaking change;
`contractPolicy.deprecationRemoval` is `cli-2.0-or-runtime-v2`, so within
contract 1 drift is additive and only the digest catches it. Capability gates
(`temporalCreateVersion`, `typedCreateVersion`, `compactUpdateBatchVersion`,
`graphTransactionVersion`) must be advertised by **both** the CLI manifest and
the live Runtime Catalog, or the operation fails closed.

---

## 10. Reporting to the user after a mutation

State what actually happened, using the CLI's own words:

- applied, with the task ID and the resulting status or field values,
- previewed only, with the `planRef`, what it would do, and its `expiresAt`,
- no-change, with why it was already satisfied,
- failed, with the exit code and the verbatim message.

Do not report success for a plan that was only previewed.
