# Typed mutations (mutation-intent routes)

Typed JSON is for what compact argv cannot express: task graphs, several items
in one atomic plan, body replacement, custom templates, exact placement, and
the two mutations that have **no compact form at all**: `task transition` and
`timer start`/`timer stop`.

Contract source: `.obsidian/plugins/operon/contracts/agent-runtime/v1/mutation.schema.json`
(`$defs`: `createSpec`, `transitionSpec`, `timerSpec`, `updateBatchSpec`,
`exactMutationTarget`, `generalUpdateItem`). Fetch any shape live with
`operon schema get mutation-intent --json`.

---

## The mutation-intent envelope

Every typed `--input` route takes a `mutation-intent`, much smaller than the
raw `mutation-preview-request`:

```json
{
  "contractVersion": 1,
  "kind": "mutation-intent",
  "requestId": "req-1",
  "target": { "...": "required/optional/forbidden per command, see below" },
  "spec": { "...": "one operation" }
}
```

Optional siblings: `requestId` (recommended on every intent), `idempotencyKey`,
`correlationId`, `reason`. Unknown keys are rejected (`inputs: strict`).

**Typed input is always preview-only.** It returns a sealed plan; apply it
separately with `operon plan apply <planRef>` (the planRef is at
`.client.planRef` on the envelope, never inside `.result`). Plans expire, so
preview and apply belong in the same breath: `plans-and-limits.md`.

### The target and its locator

`target` is an `exactMutationTarget`: `{"operonId": "...", "locator": {...}}`,
both keys required when a target is given. The locator is passed **verbatim**
to the Runtime (the CLI does not hydrate it):

```json
{ "representation": "inline", "filePath": "<path>.md", "lineNumber": 28 }
{ "representation": "file",   "filePath": "<path>.md" }
```

`lineNumber` is **zero-based** and only present for inline tasks. Both
`task get --id` and finder rows return exactly this locator shape, ready to
pass through.

---

## Transition (verified 2026-07-31)

`operon task transition --input - --json`. targetPolicy **required**. Moves a
task to any status in its pipeline, and can carry general field changes **in
the same atomic plan**:

```json
{
  "contractVersion": 1,
  "kind": "mutation-intent",
  "requestId": "tr-1",
  "target": {
    "operonId": "abc1234",
    "locator": { "representation": "inline", "filePath": "<path>.md", "lineNumber": 28 }
  },
  "spec": {
    "operation": "transition",
    "targetStatusId": "st_...",
    "expectedStatusId": "st_...",
    "changes": [
      { "field": "note",     "valueType": "text", "value": "handed over" },
      { "field": "priority", "valueType": "text", "value": "pr_b" },
      { "operation": "clear", "field": "dateScheduled", "valueType": "date" }
    ]
  }
}
```

- `operation` and `targetStatusId` are required; both status values are
  **stable IDs** from the catalog, not `Pipeline.Status` labels.
- `expectedStatusId` (optional) seals the expected current status: a concurrent
  move invalidates the plan instead of overwriting. Always set it when you
  know the current status.
- `changes` (optional, max 512, unique by field) takes `generalUpdateItem`s:
  set items `{field, valueType, value}`, clear items
  `{"operation":"clear", field, valueType}`. Only `general-update`-class fields
  are admitted; `description` cannot be cleared.
- **`priority` inside `changes` takes the stable id** (`pr_b`), not the label.
  Lists are JSON arrays; `estimate` is a number of seconds.
- The transition handles compound timer, recurrence, dependency, pin, and
  hierarchy effects itself.

Then:

```bash
operon plan apply <planRef> --json
```

The maintained one-call wrapper for all of this is
`.claude/skills/operon-tasks/scripts/op-do.sh transition`.

---

## Timer control (verified 2026-07-31)

`operon timer start --input - --json` and `operon timer stop --input - --json`.
targetPolicy **optional**: the spec is tiny and the target decides what is
controlled.

```json
{
  "contractVersion": 1,
  "kind": "mutation-intent",
  "requestId": "tm-1",
  "spec": { "operation": "start" }
}
```

```json
{
  "contractVersion": 1,
  "kind": "mutation-intent",
  "requestId": "tm-2",
  "target": {
    "operonId": "abc1234",
    "locator": { "representation": "inline", "filePath": "<path>.md", "lineNumber": 28 }
  },
  "spec": { "operation": "stop", "expectedActiveStart": "2026-07-31T22:00:00" }
}
```

- `spec.operation` is `"start"` or `"stop"`; nothing else is required.
- **No `target` = the unassigned timer** (verified both ways). With a target,
  `start` switches to that task; switching from an already-running timer is
  handled inside the plan.
- `expectedActiveStart` (optional) seals against a raced timer: if the active
  timer's start differs, the plan fails closed instead of stopping the wrong
  run.
- Preview-only, then `plan apply`, like every typed route. Wrapper:
  `op-do.sh timer-start` / `timer-stop`.

---

## Typed create

`operon task create --input <file|->`. targetPolicy **forbidden** at the
envelope level: placement lives inside each item's own `target`.

```json
{
  "contractVersion": 1,
  "kind": "mutation-intent",
  "requestId": "cr-1",
  "spec": { "operation": "create", "items": [ ... ] }
}
```

### One create item

```json
{
  "itemRef": "t1",
  "description": "Draft the release notes",
  "target": { "representation": "file", "mode": "configured-default",
              "templateId": "builtin-minimal-file-task-template:pl_..." },
  "statusId": "st_...",
  "priorityId": "pr_a",
  "tags": ["cli", "beta"],
  "fields": [
    { "kind": "date",     "field": "dateDue",   "value": "2026-08-15" },
    { "kind": "list",     "field": "contexts",  "value": ["Operon", "Release"] },
    { "kind": "text",     "field": "note",      "value": "Blocked on live acceptance" },
    { "kind": "number",   "field": "estimate",  "value": 3600 },
    { "kind": "datetime", "field": "datetimeStart", "value": "2026-08-15T09:00:00" }
  ],
  "parent": { "kind": "existing", "operonId": "b5jdsct" }
}
```

`itemRef` matches `^[A-Za-z0-9][A-Za-z0-9._:-]*$`, unique within the spec.
1 to 64 items per spec, up to 128 `fields` per item. Typed create uses
**stable IDs** (`statusId`, `priorityId`), not `Pipeline.Status` and labels.

### `fields` value kinds

| kind | allowed `field` | value |
|---|---|---|
| `text` | `taskIcon` `taskColor` `note` `location` | string |
| `date` | `dateDue` `dateScheduled` `dateStarted` | `YYYY-MM-DD` |
| `datetime` | `datetimeStart` `datetimeEnd` | local-naive datetime, canonical `HH:mm:ss` |
| `number` | `estimate` | number of seconds |
| `list` | `assignees` `contexts` `links` | array of strings, unique, no `;` inside an item |
| `custom` | any writable custom key | needs `valueType` alongside `value` |

`description`, `tags`, `statusId`, and `priorityId` are item properties, not
`fields` entries.

### `target` shapes

```json
{ "mode": "configured-default" }
{ "representation": "inline", "mode": "configured-default" }
{ "representation": "inline", "mode": "exact-path", "filePath": "<path>.md", "lineNumber": 41 }
{ "representation": "file",   "mode": "configured-default", "templateId": "..." }
{ "representation": "file",   "mode": "exact-path", "filePath": "<path>.md", "templateId": "..." }
```

`lineNumber` is zero-based and inserts before that line; placement candidates
from the `placement-candidates` projection are also zero-based and pass
straight through. (One-based numbers exist only on `relocate`/`convert`
`--line`: SKILL.md §9.1.)

For everyday creates prefer plain compact `operon task create` with no target
flags: `configured-default` placement works in this vault and the Runtime
resolves it live (SKILL.md §4). Reach for typed targets only when the task must
land somewhere specific.

### Other item properties

- `bodyMarkdown`: file tasks only, replaces the note body.
- `related`: array of `createReference`.
- `dependencies`: array of `createDependency`.
- `parent`: a `createReference`. `{"kind":"existing","operonId":"..."}`
  attaches to a live task; referring to another `itemRef` in the same spec
  builds a graph in one plan.

### Finding a deterministic template

```bash
echo '{"contractVersion":1,"requestId":"cc1","kind":"context","consistency":"live-verified","purpose":"creation","projection":"creation-context","limit":20}' \
  | operon context --input - --json \
  | jq -c '.result.policies.creation.fileTaskTemplateCandidates[] | {id, name, kind, pipelineId}'
```

`kind: "builtin-pipeline-minimal"` entries are always deterministic: no
Templater, one per pipeline, initial status baked in. Folder templates may or
may not be.

---

## Typed update and update-batch

Compact argv covers almost every update; the typed route exists for
completeness (`spec.operation: "update"` with `changes`, or `"update-batch"`
with 2-64 `{itemRef, target, changes}` items, unique by itemRef AND by
`target.operonId`, each `changes` 1-512 unique-by-field items). The compact
front door for the batch is `--input-format compact-lines`
(`compact-syntax.md`), which compiles to exactly this spec.

---

## Preview, then apply

```bash
operon task create --input intent.json --json > preview.json
PLAN=$(jq -r '.client.planRef' preview.json)          # .client, not .result
jq -c '{risk: .result.plan.riskLevel, confirm: .result.plan.requiresConfirmation, warnings: .result.plan.warnings}' preview.json

operon plan apply "$PLAN" --json
```

Every create preview carries the warning `apply-time-values-projected`
(timestamps are projected at preview, captured at apply). That one is
informational; treat any **other** warning as stop-and-review.

Created task IDs appear before apply in `.result.plan.createEffects[]`:

```bash
jq -c '.result.plan.createEffects[] | {operonId, path: .locator.filePath}' preview.json
```

Discard a plan you decided not to use: `operon plan discard "$PLAN"`.

---

## Typed Create V1 capability gate

Exact placement, deterministic templates, file body replacement, and task
graphs are admitted only when the CLI manifest and the live creation Catalog
both advertise `typedCreateVersion: 1` with this exact ordered feature list:

```
exact-inline-placement
exact-file-target
deterministic-file-template
file-body-replacement
same-source-task-graph
cross-source-parent-related
```

Cross-source parent, created-related, and reciprocal dependency graphs
additionally require `graphTransactionVersion: 1` and a fresh confirmation. An
interrupted graph transaction resumes only from the same stored plan through
`operon plan recover`.
