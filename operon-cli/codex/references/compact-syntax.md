# Compact syntax (create, update, batch lines)

The human-readable argv form. It compiles to Operon's typed mutation intent,
gets a sealed preview, and applies that same plan in one call. This is the
fastest correct way to write a task.

Status and priority values below are placeholders; resolve live values from
the catalog before running anything.

---

## 1. Grammar

```
operon task create [inline|file] "Description" [canonicalKey::"VALUE" ...] [--preview-only] [--json]
operon task update (--id "ID" | --description "EXACT") (canonicalKey::"VALUE" | --clear "key")... [--preview-only] [--json]
```

Rules that apply to both:

| Rule | Detail |
|---|---|
| Split point | A token splits at its **first** `::`. Everything after is the value, so `note::"see a::b"` stores `see a::b`. |
| Quoting | Values are shell tokens. Use straight ASCII double quotes. Shell argv loses quote provenance, so the parser accepts the decoded token. |
| Key uniqueness | Each canonical key at most **once**, counting assignments and `--clear` together. |
| Canonical keys only | Visible property names (`Deadline`, `Up`, `Tier`, `Notes`) are rejected. See `field-ownership.md`. |
| Lists | Items separated by `;`, canonicalized to `; `. Order is preserved. Empty items and duplicates are rejected. Escape a literal semicolon as `\;`. |
| Scalars | A `;` inside a text field stays literal. |
| Empty value | `key::""` is a usage error. It never means clear. Use `--clear "key"` (update only). |
| Not markdown | Never pass `{{key:: value}}` containers. Those are Operon's on-disk serialization, not CLI input. |

---

## 2. Value formats

| Key type | Format | Example |
|---|---|---|
| `status` | exact `Pipeline.Status` | `status::"<Pipeline.Status>"` |
| `priority` | exact live label | `priority::"B"` |
| date | `YYYY-MM-DD` | `dateDue::"2026-08-01"` |
| datetime | canonical local-naive `YYYY-MM-DDTHH:mm:ss` (seconds); a `HH:mm` input stays valid, seconds default to `00`. Write seconds in new values. `Z` and offsets are rejected | `datetimeStart::"2026-08-01T09:00:00"` |
| number | plain integer. `estimate` is **seconds** | `estimate::"3600"` |
| list | `; ` separated | `tags::"planning; review"` |
| `parentTask` | one canonical 7-char operonId | `parentTask::"b5jdsct"` |
| `blocking` / `blockedBy` | ordered list of operonIds | `blocking::"def5678; ghi9012"` |
| `reminderRules` | `anchor.offset`, lowercase units | `reminderRules::"dateDue.30m"` |
| `reminderDatetimes` | absolute local datetime | `reminderDatetimes::"2026-08-01T08:30:00"` |
| `repeat` | normalized rule | `repeat::"mode=schedule\|freq=week\|interval=1\|days=mo"` |
| `datetimeRepeatEnd` | datetime, requires `repeat` in the same intent | `datetimeRepeatEnd::"2026-12-31T23:59:00"` |

Escaping a literal semicolon inside a list item:

```bash
operon task update --id abc1234 tags::"planning\; phase 2; review"
# stored as two items: "planning; phase 2" and "review"
```

---

## 3. `task create`

Compact create **works with the configured defaults in this vault**: with no
target flags the intent carries `target.mode: "configured-default"` and the
Runtime resolves representation and placement from the user's live settings
(vault-specific behavior and the one known failure mode: SKILL.md §4).

### Representation token

The optional first positional is exactly `inline` or `file`. It selects
representation only. **Placement stays Runtime-owned**: the compiler asks for
the configured default target for that representation.

```bash
operon task create inline "Review planning"
operon task create file "Publish notes"
operon task create "Follow up"                  # representation omitted, Runtime default
```

Watch the routing trap:

| Command | What happens |
|---|---|
| `operon task create` | Guided interactive wizard. **Do not use in an agent turn**, it needs a TTY. |
| `operon task create inline` | Also the guided wizard, with `inline` read as a description. |
| `operon task create "inline" status::"<Pipeline.Status>"` | Compact. Description is the literal word `inline`. |
| `operon task create inline "Description" ...` | Compact with explicit representation. |

An agent should always pass at least a quoted description plus one assignment,
or an explicit representation token, so the guided wizard can never be reached.

### Worked examples

```bash
# minimal
operon task create "Draft the release notes" status::"<Pipeline.Status>"

# typical project task
operon task create file "Operon CLI beta release" \
  status::"<Pipeline.Status>" priority::"A" \
  dateDue::"2026-08-15" dateScheduled::"2026-08-10" \
  contexts::"Operon; Release" tags::"cli; beta" \
  note::"Blocked on live acceptance"

# child of an existing task
operon task create "Write the changelog entry" parentTask::"c1hvs2p" priority::"B"

# with a reminder, one atomic plan
operon task create "Call the accountant" dateDue::"2026-08-03" reminderRules::"dateDue.1h"

# recurring
operon task create "Weekly review" status::"<Pipeline.Status>" \
  repeat::"mode=schedule|freq=week|interval=1|days=su" datetimeRepeatEnd::"2026-12-31T23:59:00"

# estimate is seconds, not minutes
operon task create "Deep work block" status::"<Pipeline.Status>" estimate::"5400"
```

**The auto-applied `--json` envelope contains no `createEffects` and no
operonId.** When the id is needed, use the batch route below (its preview
prints ids) or `operon plan show <client.planRef>` afterwards.

### Temporal capability gate

`reminderDatetimes`, `reminderRules`, `repeat`, and `datetimeRepeatEnd` are
admitted on create only when the CLI manifest and the live creation Catalog
both advertise `temporalCreateVersion: 1`. If they do not, the call fails
closed with `CREATE_CAPABILITY_UNAVAILABLE`. Do not fall back to a second
reminder or recurrence mutation. They belong in the one create plan.

### What compact create cannot do

Exact file path or line placement, deterministic file templates, file body
replacement, and multi-task graphs. Those need the typed JSON route
(`typed-mutations.md`) and a matching `typedCreateVersion: 1` advertisement.

---

## 4. Batch lines (`--input-format compact-lines`)

Both create and update have a native batch: newline-separated compact records
on stdin, validated line by line **before** one readiness request, compiled
into **one atomic preview-only plan**. There is no sequential fallback: one bad
line rejects the whole batch before anything is previewed.

### Create batch: 1-64 lines

Each line: optional `inline `/`file ` prefix, then a quoted description, then
assignments. No blank lines.

```bash
operon task create --input-format compact-lines --input - --json <<'EOF'
"Draft the notes" status::"<Pipeline.Status>" priority::"A" dateDue::"2026-08-15"
"Review with team" status::"<Pipeline.Status>" dateDue::"2026-08-16"
file "Publish" status::"<Pipeline.Status>"
EOF
```

### Update batch: 2-64 lines

Each line **begins with a quoted exact `--id`**, then the same assignment and
clear grammar. IDs must be unique across the batch. Only general-update fields
are admitted: no recurrence keys, no relationship keys, no `--description`
selectors, no `--scope`.

```bash
operon task update --input-format compact-lines --input - --json <<'EOF'
--id "abc1234" note::"Review first" --clear "location"
--id "def5678" priority::"<Priority>" dateScheduled::"2026-08-04"
EOF
```

### Applying a batch

Both stdin forms are **always preview-only**. The planRef is at
`.client.planRef`; created ids are in the preview's
`.result.plan.createEffects[]`. Apply promptly (plans expire:
`plans-and-limits.md` §3):

```bash
operon plan apply <planRef> --json
```

The maintained one-call wrapper that previews, gates, and applies a batch is
`.codex/skills/operon-tasks/scripts/op-do.sh batch-create` / `batch-update`.

There is also a single-record stdin form, `--input-format compact --input -`
(create only), equally preview-only; it exists for keeping sensitive values
out of argv.

---

## 5. `task update`

Three mutually exclusive routes. **Never mix them in one command.**

### 5a. General fields

```bash
operon task update --id "abc1234" dateDue::"2026-08-05" note::"Pushed one week"
operon task update --id "abc1234" contexts::"Operon; Release" --clear "dateScheduled"
operon task update --description "Prepare release notes" priority::"A"
```

Assignments **replace** the whole value, including whole lists. `--clear "key"`
is repeatable and removes the field. `description` can be replaced but not
cleared.

### 5b. Relationships

```bash
operon task update --id "abc1234" parentTask::"def5678"
operon task update --id "abc1234" blocking::"def5678; ghi9012"
operon task update --id "abc1234" --clear "blockedBy"
operon task update --id "abc1234" blocking::"def5678" --clear "blockedBy"   # several relationship keys, fine
```

- Targets are canonical 7-char operonIds only. Descriptions select the source
  task, never the targets.
- `parentTask` takes zero or one target. `blocking` and `blockedBy` keep the
  supplied order.
- The same target cannot appear in both `blocking` and `blockedBy`.
- Mixing a relationship key with any general field fails before preview.
- If every requested list already matches the live value in the same order,
  the CLI returns `no-change` locally without a Runtime preview.

### 5c. Recurrence and dates on a recurring task

```bash
operon task update --id "abc1234" repeat::"mode=schedule|freq=week|interval=1|days=mo"
operon task update --id "abc1234" --scope this-task dateScheduled::"2026-08-03"
operon task update --id "abc1234" --scope this-and-following estimate::"3600"
operon task update --id "abc1234" --scope this-and-following --clear "repeat"
```

- `--scope` is **mandatory** when the task already recurs and a temporal field
  changes.
- `this-task` touches only the latest materialized open occurrence.
- `this-and-following` atomically updates the task and the repeat-series state.
- Starting recurrence on a non-recurring task defaults to `this-and-following`.
- Scope-eligible keys: `dateScheduled`, `dateStarted`, `dateDue`,
  `datetimeStart`, `datetimeEnd`, `estimate`, plus `repeat` and
  `datetimeRepeatEnd`.
- Cannot be mixed with general or relationship fields.

---

## 6. Target selection

| Selector | Behavior |
|---|---|
| `--id "abc1234"` | Canonical 7-char Operon ID. Always prefer this. |
| `--description "Exact text"` | NFC-normalized, case-sensitive, exact, across the complete live result set. Zero, multiple, truncated, or warning-bearing reads fail closed. Ambiguous matches print their IDs. |

Resolve the ID first (maintained wrapper lives in the operon-tasks skill):

```bash
ID=$(.codex/skills/operon-tasks/scripts/op-id.sh "release notes" --one)
operon task update --id "$ID" priority::"A"
```

---

## 7. No-change and preview behavior

If every requested change already equals the live value, the CLI returns
`no-change` **before** creating a plan. That is a success, not an error. Do
not retry. Auto-apply conditions, `--preview-only`, and plan mechanics:
`plans-and-limits.md`.

---

## 8. Usage errors to expect (exit 2)

Missing description; malformed token or empty key; a key used twice; unknown,
non-writable, or type-incompatible key; bad list escaping; a typed value that
does not parse; `key::""`; compact positional content combined with `--input`;
`--input-format` without `--input`; a mixed general/relationship/recurrence
command; missing `--scope` on a recurring task; unsupported target or
placement request; a batch outside its line bounds (create 1-64, update 2-64);
an update batch line missing its leading `--id`; duplicate ids in a batch.

All of these mean the command was wrong. Fix the command, do not retry it
unchanged.
