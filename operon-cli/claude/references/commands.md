# Command reference (all 47 commands)

Every leaf command of Operon CLI 1.0.0, grouped by what it does, ordered by how
often an agent needs it. Verified against the live help corpus and
`operon manifest --json` on 2026-07-31.

**Source-of-truth ranking when texts disagree:** `operon <cmd> --help` (live)
beats the manifest, which beats the contract schemas, which beat the beta-era
docs in `.obsidian/plugins/operon/packages/operon-cli/docs/`. Do not re-import
prose from those beta docs without checking help first.

Facts stated in SKILL.md are not restated here; link instead. Exit codes:
SKILL.md §7. Line numbering rule: SKILL.md §9.1. Apply policy: SKILL.md §6.

## Index

| Group | Commands |
|---|---|
| §1 Read and inspect | `task get`, `query`, `finder`, `relationships`, `entity resolve`, `context`, `timer state`, `task find` |
| §2 Create | `task create` (compact, batch, typed) |
| §3 Update | `task update` (compact, batch, typed) |
| §4 Lifecycle | `task complete`, `reopen`, `cancel`, `transition` |
| §5 Reminders | `reminder add`, `replace`, `remove` |
| §6 Pin | `task pin`, `unpin` |
| §7 Timer | `timer start`, `stop`, `session add/update/remove` |
| §8 Structure | `task relocate`, `convert`, `delete` |
| §9 Plans | `plan show`, `apply`, `recover`, `discard`, `mutation preview`, `mutation apply` |
| §10 Health and meta | `health`, `capabilities`, `diagnostics`, `catalog`, `manifest`, `schema list/get`, `version`, `doctor`, `setup`, `profile list/default/remove`, `completion` |

### targetPolicy (who needs a task target)

From the manifest, per mutation command: `task create` **forbidden** (no target,
placement comes from the spec); `timer start`/`timer stop` **optional** (no
target = the unassigned timer); all 16 other mutation commands **required**
(`--id`, `--description`, or a typed `target`).

---

## 1. Read and inspect

All reads are non-destructive and safe to run freely. Typed reads take JSON on
stdin:

```bash
echo '<request json>' | operon <command> --input - [--json]
```

Shared required fields on every typed request: `contractVersion: 1`, a
`requestId` matching `^[A-Za-z0-9][A-Za-z0-9._:-]*$`, the `kind`, and
`consistency` (`live-verified` unless you have a reason not to).

Without `--json` you get a compact human table. With `--json` the payload is
under `.result`.

### task get

```bash
# Read one exact task (partial projection, see below)
operon task get --id abc1234
```

```
operon task get --id <operonId> [--json]
operon task get --input <file|-> [--json]
```

**The `--id` shorthand is a PARTIAL projection.** It returns identity, locator,
workflow (status), priority, checkbox, dates, datetimes, relationships,
recurrence, tracker, pinned, and representation. It **omits from the data**
(not just the human rendering):

| Omitted by default | Revealed by |
|---|---|
| `note`, `tags`, `contexts`, `assignees`, `links`, `location`, `taskIcon`, `taskColor`, `estimate` | `include: ["writable-fields"]` |
| all reminders | `include: ["reminder-items"]` |

Never conclude a field is unset from the shorthand output, and never rebuild a
list value from it. Typed form with hydration:

```json
{
  "contractVersion": 1,
  "requestId": "get-1",
  "kind": "task-get",
  "consistency": "live-verified",
  "selector": { "kind": "operon-id", "operonId": "abc1234" },
  "include": ["writable-fields", "reminder-items"]
}
```

`writable-fields` rows carry `canonicalKey`, `present`, `canClear`, `value` and
show what the Runtime will accept for that task. One trap: `priority` comes back
as the **stable id** (`pr_c`), not the label (`C`). Hydrated fields appear only
in `--json` output.

### query (bounded index query)

```json
{
  "contractVersion": 1,
  "requestId": "q-1",
  "kind": "task-query",
  "consistency": "live-verified",
  "limit": 25,
  "filters": {
    "checkbox": ["open"],
    "pipelineIds": ["pl_..."],
    "statusIds": ["st_..."],
    "priorityIds": ["pr_a"],
    "due": { "from": "2026-08-01", "to": "2026-08-31" },
    "parentOperonId": "b5jdsct",
    "filePath": "20 Projects/Release.md",
    "text": "release notes"
  }
}
```

- `limit` 1 to 250; `filters` optional; every filter optional.
- Pipeline, status, and priority filters need **stable IDs**, not labels
  (translate from `operon catalog`).
- `result.page` carries `actualCount`, `returnedCount`, `truncated`,
  `nextCursor`. Send `nextCursor` back as `cursor` for the next page; a cursor
  is bound to its exact filter set (`stale-cursor` otherwise).

### finder (native matcher and ranking)

Same engine as the Task Finder UI: fuzzy matching, ranking, scopes, project
modes.

```json
{
  "contractVersion": 1,
  "requestId": "f-1",
  "kind": "task-finder",
  "consistency": "live-verified",
  "text": "release notes",
  "limit": 10,
  "representations": ["inline", "file"],
  "scope": "normal",
  "project": { "mode": "tree", "rootOperonId": "b5jdsct" },
  "filters": { "checkbox": ["open"], "priorityIds": ["pr_s"] }
}
```

- `text` needs at least 2 characters.
- `scope`: `normal`, `overdue`, `happens-today`, `recent`.
- `project.mode`: `direct` (immediate children) or `tree` (whole subtree).
- Finder `filters` **cannot** contain `text`, `filePath`, or `parentOperonId`;
  use the top-level `text` and `project`.
- Rows come back as `result.rows[]` with `{kind, task, score}`.
- **Each row's `task.locator` carries `representation`, `filePath`, and a
  zero-based `lineNumber`** which can be passed verbatim as the `locator` of a
  typed mutation `target`. This makes finder the cheapest way to build a
  transition or timer target: one read yields both the id and the locator.

### relationships

```json
{
  "contractVersion": 1,
  "requestId": "rel-1",
  "kind": "relationship",
  "consistency": "live-verified",
  "selector": { "kind": "operon-id", "operonId": "abc1234" },
  "kinds": ["parent", "child", "blocking", "blocked-by", "related", "ancestor", "project-member"],
  "depth": 1,
  "limit": 50
}
```

Human output groups edges into Explicit (from a field), Derived (from an index
inverse), and Inferred. `depth` is 0 to 6.

### entity resolve

Turns a loose selector into candidates with confidence scores. **Ambiguous
results are candidates, not mutation targets** (the help text says exactly
this).

```json
{
  "contractVersion": 1,
  "requestId": "e-1",
  "kind": "entity-resolve",
  "consistency": "live-verified",
  "selector": { "kind": "search", "query": "Skill Library", "limit": 5 }
}
```

Selector kinds: `operon-id`, `exact-locator`, `exact-path`, `exact-name`,
`search`. The last three accept an optional `expectedOperonId` for verification.

### context (Context Pack)

One bounded read returning tasks plus relationships plus optionally catalog and
policies, shaped by a projection. Requires both `purpose` and `projection`.

| Projection | Required purpose | Needs | Limits |
|---|---|---|---|
| `exact-task` | any | `selector` | `limit` 1, `depth` 0, no cursor |
| `task-neighborhood` | any | `selector` | `limit` <= 100, `depth` <= 1 |
| `project-analysis` | any | `selector` | `limit` <= 500, `depth` <= 6 |
| `planning-workload` | any | `filters` (no selector, no depth) | `limit` <= 250 |
| `creation-context` | `creation` | optional `targetFilePath` | `limit` <= 100, `depth` <= 1 |
| `mutation-preview` | `mutation-readiness` | `selector` + `mutationKind` | `limit` <= 128 |
| `placement-candidates` | `mutation-readiness` | `placement` only | `limit` <= 100 |

```bash
# Workload sweep
echo '{"contractVersion":1,"requestId":"c-1","kind":"context","consistency":"live-verified","purpose":"planning","projection":"planning-workload","filters":{"checkbox":["open"],"due":{"to":"2026-08-31"}},"limit":50}' \
  | operon context --input - --json

# Placement candidates before a relocate
echo '{"contractVersion":1,"requestId":"p-1","kind":"context","consistency":"live-verified","purpose":"mutation-readiness","projection":"placement-candidates","placement":{"mode":"lines","filePath":"<path>.md"},"limit":20}' \
  | operon context --input - --json | jq -c '.result.placement.lines[]'
```

Placement candidate `locator.lineNumber` is zero-based while `relocate --line`
is one-based (SKILL.md §9.1); the `contextLabel` states the human number.
`placement.mode` is `lines` (needs a `.md` `filePath`) or `files` (optional
`query`).

### timer state

```bash
operon timer state [--consistency live-verified|best-effort] [--json]
```

Current active tracker (assigned task or unassigned), start time, elapsed.
One of only two commands with a `--consistency` flag (the other is `catalog`).

### task find

Interactive TTY picker, one of only two `text-tty-only` commands (with
`completion`). **Never run it from an agent turn**; use `finder` or the
operon-tasks `op-id.sh` wrapper.

---

## 2. Create

```
operon task create [description] [--preview-only]                              # guided, TTY
operon task create [inline|file] "Description" [key::"VALUE"...] [--preview-only] [--json]
operon task create --input-format compact --input <file|-> [--json]            # one record, preview-only
operon task create --input-format compact-lines --input <file|-> [--json]      # 1-64 lines, preview-only
operon task create --input <file|-> [--json]                                   # typed JSON, preview-only
```

targetPolicy **forbidden**: placement never comes from a `--id`; it comes from
the spec (`configured-default` or an exact path). Vault-specific create truth
(configured-default placement, the one daily-notes failure mode,
`dateScheduled` not derived at create time): SKILL.md §4.

```bash
# One task, everything in one call, Runtime resolves placement
operon task create "Draft the release notes" status::"<Pipeline.Status>" \
  priority::"<Priority>" dateDue::"2026-08-01" reminderRules::"dateDue.30m"
```

Human compact argv auto-applies one unchanged safe preview unless
`--preview-only`. All three stdin forms (`compact`, `compact-lines`, typed
JSON) are **always preview-only** and return a planRef at `.client.planRef`.
Grammar and batch lines: `compact-syntax.md`. Graphs, templates, body,
exact placement: `typed-mutations.md`.

**The compact auto-apply `--json` output is the apply envelope and contains no
`createEffects` and no operonId.** Ids live in the preview plan: use the batch
route, or `operon plan show <client.planRef>` afterwards (recipe in
`recipes.md`).

---

## 3. Update

```
operon task update                                                             # guided, TTY
operon task update (--id <id>|--description <exact>) {key::"VALUE"|--clear <key>}... [--preview-only] [--json]
operon task update (--id|--description) --scope <this-task|this-and-following> {temporal keys|--clear}... [--preview-only] [--json]
operon task update (--id|--description) repeat::"<normalized-rule>" [datetimeRepeatEnd::"..."] [--scope this-and-following] [--preview-only] [--json]
operon task update (--id|--description) {parentTask::"<id>"|blocking::"<id>; ..."|blockedBy::"<id>; ..."|--clear <relationship-key>}... [--preview-only] [--json]
operon task update --input-format compact-lines --input <file|-> [--json]      # 2-64 lines, preview-only
operon task update --input <file|-> [--json]                                   # typed JSON, preview-only
```

One command, **three mutation kinds** routed by the keys used (help text states
this): general fields → `task.update`, recurrence keys → `task.recurrence`,
relationship keys → `task.relationship`. The three routes cannot be mixed in
one call.

```bash
# General fields
operon task update --id "abc1234" priority::"<Priority>" note::"Published"
operon task update --id "abc1234" contexts::"Operon; Release" --clear "dateDue"

# Recurrence (scope mandatory on a recurring task)
operon task update --id "abc1234" --scope this-task dateScheduled::"2026-08-04"
operon task update --id "abc1234" repeat::"mode=schedule|freq=week|interval=1|days=mo"

# Relationships (own route, never mixed with general fields)
operon task update --id "abc1234" parentTask::"def5678"
operon task update --id "abc1234" blocking::"def5678; ghi9012" --clear "blockedBy"
```

Human compact argv auto-applies one unchanged warning-free plan unless
`--preview-only`. **Batch**: `--input-format compact-lines` takes 2-64 unique
exact-`--id` records, validates every line before one coherent readiness
request, and returns **one atomic preview-only planRef** with no sequential
fallback (grammar: `compact-syntax.md`). `no-change` is success. Full grammar
and edge cases: `compact-syntax.md`; key ownership: `field-ownership.md`.

---

## 4. Lifecycle

```bash
operon task complete --id "abc1234"                # to the pipeline's finished status
operon task reopen   --id "abc1234"                # to the first non-terminal status
operon task cancel   --id "abc1234"                # to the cancellation status
operon task cancel   --id "abc1234" --preview-only
```

All three are `task.transition` mutations, targetPolicy required, auto-apply
when warning-free.

- `complete` and `cancel` need exactly **one** resolved semantic status in the
  task's current pipeline; zero or several fail closed (a pipeline without a
  cancelled-semantic status cannot `cancel`).
- `reopen` picks the first non-terminal status by pipeline order.
- The current status is sealed as `expectedStatusId`; a concurrent change
  invalidates the plan instead of overwriting.
- Already-complete / already-cancelled / already-open are local `no-change`
  results: no plan, no apply, not an error.
- Compound timer, recurrence, pin, dependency, and parent effects are handled
  inside the transition. Do not try to reproduce them.

### task transition (any other status)

```
operon task transition                     # interactive, TTY
operon task transition --input <file|-> [--json]   # typed, preview-only
```

**No compact argv form, no `--id`, no `--preview-only` flag.** The typed route
takes a `mutation-intent` whose spec can carry general field changes in the
same atomic plan. Full verified intent shape: `typed-mutations.md`. Then
`operon plan apply <planRef>`.

---

## 5. Reminders

```bash
operon reminder add     --id "abc1234" reminderRules::"dateDue.30m"
operon reminder add     --id "abc1234" reminderDatetimes::"2026-08-01T08:30:00"
operon reminder replace --id "abc1234" --current "dateDue.30m" reminderRules::"dateDue.1h"
operon reminder remove  --id "abc1234" reminderRules::"dateDue.1h"
```

- One canonical item per call; multi-item values (`a; b`) are rejected.
- Rules are `anchor.offset` with lowercase units (`dateDue.30m`,
  `datetimeStart.1h`, `dateScheduled.2d`); the anchor field must exist on the
  task. Fixed reminders are local-naive datetimes.
- `replace` and `remove` hydrate the live reminder list, require exactly one
  canonical match, and seal its internal item ID; ambiguity fails closed.
- On **create**, reminders travel inside the single create plan; never split
  them into a follow-up `reminder add`.
- Auto-apply when warning-free; typed `--input` variants preview only.

---

## 6. Pin

```bash
operon task pin   --id "abc1234"
operon task unpin --id "abc1234"
```

Pin is Operon workflow state, not task markdown. Already pinned / unpinned is a
local no-change. The Runtime seals `expectedPinned` and `expectedEntryRevision`
(compare-aware), so warning-free plans auto-apply safely.

---

## 7. Timer

```bash
operon timer state                    # read, no mutation
```

### timer start / stop

```
operon timer start                          # interactive, TTY
operon timer start --input <file|-> [--json]   # typed, preview-only
operon timer stop  [--input <file|-> [--json]]
```

**No compact argv form, no `--id` flag.** targetPolicy **optional**: a typed
intent without a `target` starts or stops the **unassigned** timer; with a
`target` it starts the timer on that task (switching from a running timer is
handled inside the plan). Verified intent shape: `typed-mutations.md`. Then
`plan apply`.

### Completed sessions

```bash
operon timer session add    --id "abc1234" --start "2026-07-27T09:00:00" --end "2026-07-27T10:00:00"
operon timer session update --id "abc1234" --session "1" --start "2026-07-27T09:15:00" --end "2026-07-27T10:30:00"
operon timer session remove --id "abc1234" --session "1"     # destructive, REMOVE gate
```

- Session numbers are **1-based, oldest-first** (sorted by start, then end,
  then stable raw-storage position).
- Datetimes are local-naive, canonical `HH:mm:ss` (a `HH:mm` input
  stays valid, seconds default to `00`); `Z` and offsets are rejected.
- `add` and `update` auto-apply a warning-free unchanged plan; the sealed plan
  pins the raw storage index and exact old range.
- **`remove` is destructive**: fresh `REMOVE` confirmation, never auto-applies
  non-interactively (SKILL.md §6).
- The active timer is untouched by all three.

---

## 8. Structure (relocate, convert, delete)

```bash
# Move an inline task to a live blank-line candidate (one-based --line)
operon task relocate --id "abc1234" --target-file "20 Projects/Release.md" --line "42"

# Inline -> File Task (auto-appliable when warning-free)
operon task convert --id "abc1234" --to "file" \
  --template "Default File Task" --target-file "20 Projects/Release task.md"

# File -> Inline (DESTRUCTIVE: CONVERT confirmation)
operon task convert --id "abc1234" --to "inline" \
  --target-file "20 Projects/Release.md" --line "42"

# Delete (DESTRUCTIVE: DELETE confirmation)
operon task delete --id "abc1234" --preview-only
```

- `--line` is the **one-based** human number and must match a live
  placement candidate (`placement-candidates` projection, §1).
- Template names are exact case-sensitive live Catalog names.
- Deletion moves the source to Obsidian trash, and is blocked while the task
  has relationships (clear `parentTask`/`blocking`/`blockedBy` first).
- Destructive flows (File→Inline convert, delete, session remove): preview,
  show the user, hand them the interactive command; SKILL.md §6.

### Source-transition journal

Relocate, convert, and delete write through one durable source-transition
journal (source, destination, parent aggregates, recurrence, pinned cleanup).
If one is interrupted, the only correct continuation is the same planRef:
`operon plan recover <planRef>`. Never build a replacement preview.

---

## 9. Plans

```bash
operon plan show    <plan-ref> [--json]        # inspect without applying
operon plan apply   <plan-ref> [--confirm <target-digest>] [--json]
operon plan recover [<plan-ref>] [--json]      # after an uncertain apply; interactive ABANDON drops it
operon plan discard <plan-ref> [--json]        # clean up an unused plan
```

- `plan apply` applies one **unchanged** stored plan. Never repeat an uncertain
  apply.
- `plan recover` reuses the original idempotent apply. Interactive `ABANDON`
  removes the only local recovery reference; never do that on the user's
  behalf.
- Plan lifecycle, TTL/expiresAt, confirmation tokens, error registry:
  `plans-and-limits.md`.

### mutation preview / mutation apply (generic typed route)

```bash
operon mutation preview --input <file|-> [--json]     # full mutation-preview-request, sealed preview
operon mutation apply --plan-ref <plan-ref> [--confirm <digest>] [--json]
```

The generic route takes the full `mutation-preview-request` schema (heavier
than the per-command `mutation-intent`). Raw apply input is not accepted:
`mutation apply` only takes a stored plan reference. Prefer the per-command
routes; this pair exists for completeness and tooling.

---

## 10. Health and meta

```bash
operon health                    # lifecycle phase, admission, freshness; --json adds settingsFingerprint
operon capabilities              # 35 runtime capabilities and availability
operon diagnostics               # privacy-safe runtime and transport diagnostics
operon catalog [--consistency live-verified|best-effort]   # pipelines, statuses, priorities, fields, policies
operon manifest --json           # command registry, limits, errorRegistry, exitCodes, contractDigest
operon schema list [--json]      # 68 installed schema entrypoints
operon schema get <schema-id> [--json]    # one schema, e.g. mutation-intent
operon version [--json]
operon doctor [--live] [--repair-security]
operon setup [--vault <path> --name <alias> [--default] [--live]]
operon profile list | profile default <alias> | profile remove <alias>
operon completion <zsh|bash|fish>          # text-tty-only, never modifies shell profiles
```

- `catalog` human output truncates the field list; `--json` is complete
  (~55 KB). The operon-tasks `op-catalog.sh` caches it with fingerprint
  validation.
- `manifest` is the only place the exit-code table, the 38-entry error
  registry, the 20 numeric limits, and `contractDigest` exist. It works
  without a vault.
- Of the 68 schema ids, roughly 24 matter to an agent (the 12 read
  request/result pairs, catalog, timer read, `runtime-health`,
  `mutation-intent`, `mutation-preview-result`, `mutation-result`,
  `mutation-plan-reference`, `plan-show-envelope`, `cli-result`,
  `structured-error`). The 9 `developer-api-*` ids belong to the in-plugin
  Developer API channel, and the 6 `session-*` ids belong to a protocol that
  CLI 1.0.0 does not implement (SKILL.md §9.4).
- Vault selection is automatic with a single profile; pass `--vault`/`--profile`
  only to target a different vault.
