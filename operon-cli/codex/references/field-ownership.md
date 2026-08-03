# Field ownership and canonical keys

The CLI accepts **canonical keys only**. The names shown in Obsidian's property panel and in task markdown are different. Passing a visible name is a usage error.

The live list comes from `operon catalog` (cached wrapper:
`.codex/skills/operon-tasks/scripts/op-catalog.sh`). This file explains the
structure and the traps. When the two disagree, the live catalog wins.

Two cross-cutting notes:

- **Read visibility is narrower than writability.** Plain `task get --id` omits
  `note`, `tags`, `contexts`, `assignees`, `links`, `location`, `taskIcon`,
  `taskColor`, `estimate`, and all reminders from its projection. A field
  missing there is not proof it is unset: hydrate with
  `include: ["writable-fields"]` (`commands.md` §1).
- **Labels vs stable IDs.** Compact argv takes labels (`priority::"A"`,
  `status::"Pipeline.Status"`). Typed JSON routes take stable IDs (`pr_a`,
  `st_...`), and reads return stable IDs. Per-command targetPolicy:
  `commands.md`.

---

## 1. Visible name to canonical key

| Visible in the vault | Canonical key | Type |
|---|---|---|
| Description | `description` | text |
| Tags | `tags` | list |
| Status | `status` | text (`Pipeline.Status`) |
| Tier | `priority` | text (`S A B C D E F`) |
| Deadline | `dateDue` | date |
| Scheduled | `dateScheduled` | date |
| Started | `dateStarted` | date |
| Finished | `dateCompleted` | date |
| Cancelled | `dateCancelled` | date |
| datetimeStart | `datetimeStart` | datetime |
| datetimeEnd | `datetimeEnd` | datetime |
| Estimate | `estimate` | number, **seconds** |
| Duration | `duration` | number, seconds, read-only |
| People | `assignees` | list |
| Up | `contexts` | list |
| Notes | `note` | text |
| Links | `links` | list |
| Coordinates | `location` | text |
| Icon | `taskIcon` | text |
| Color | `taskColor` | text |
| ParentId | `parentTask` | text (operonId) |
| Blocking | `blocking` | list of operonIds |
| BlockedBy | `blockedBy` | list of operonIds |
| Related | `related` | list |
| ReminderDatetimes | `reminderDatetimes` | list |
| ReminderRules | `reminderRules` | list |
| Trackers | `trackers` | list |
| activeTracker | `activeTracker` | datetime |
| Pinned | `pinned` | checkbox |
| Progress | `progress` | number, read-only |
| Created | `datetimeCreated` | datetime, read-only |
| Updated | `datetimeModified` | datetime, read-only |
| operonId | `operonId` | text, read-only |

---

## 2. Which command owns which key

### `tasks.update` general fields (freely combined in one `task update`)

`description` `tags` `priority` `dateDue` `dateScheduled` `dateStarted` `datetimeStart` `datetimeEnd` `estimate` `assignees` `contexts` `note` `links` `location` `taskIcon` `taskColor` plus every writable custom field.

```bash
operon task update --id abc1234 priority::"A" dateDue::"2026-08-05" contexts::"Operon; Release"
```

### `tasks.transition` (status and its derived dates)

`status` `checkbox` `dateCompleted` `dateCancelled`

Never assignable through `task update`. Use:

```bash
operon task complete --id abc1234
operon task reopen   --id abc1234
operon task cancel   --id abc1234
operon task transition --input - --json  # typed, for any other status (no --id flag)
```

A typed transition's `changes` array may carry general-update fields in the
**same atomic plan** as the status move (`typed-mutations.md`), so "set
priority and move status" does not have to be two calls.

### `tasks.relationship`

`parentTask` `blocking` `blockedBy`

Same `task update` surface, different Runtime mutation. **Cannot be combined with general fields in one command.**

### `tasks.recurrence`

Assignable: `repeat` `datetimeRepeatEnd`.
Read-only series state: `repeatSeriesId` `repeatOccurrenceDate`.

Temporal keys on an already recurring task require `--scope this-task` or `--scope this-and-following`.

### `tasks.reminder`

`reminderDatetimes` `reminderRules`

Only through `operon reminder add|replace|remove`, one item per call. The exception is `task create`, where they are part of the single atomic create plan.

### `timers.control` and `timers.session`

`activeTracker` through `operon timer start|stop`.
`trackers` (completed sessions) through `operon timer session add|update|remove`.

### `tasks.convert` and `tasks.inline-relocate`

`representation` through `operon task convert --to inline|file`.
`locator` through `operon task relocate`.

### Runtime-owned, never assignable

`operonId` `locator` `pinned` `duration` `progress` `totalEstimate` `totalDuration` `directSubtaskCount` `directDoneSubtaskCount` `directOpenSubtaskCount` `treeDescendantCount` `treeDoneDescendantCount` `treeOpenDescendantCount` `datetimeCreated` `datetimeModified` `timezone` `repeatSeriesId` `repeatOccurrenceDate`

`pinned` is Runtime-owned as a value but is changed through the dedicated `task pin` / `task unpin` compare-aware commands. `locator` likewise moves only through `task relocate`.

`related` cannot be set through compact **update**; on typed **create** it is
settable as an array of `createReference` (`typed-mutations.md`).

---

## 3. The three routes cannot be mixed

One `task update` call is exactly one of:

1. general fields (any number, plus `--clear`),
2. relationship keys (any number, plus `--clear`),
3. recurrence keys (with `--scope` when the task recurs).

Mixing fails before Runtime discovery, so it costs a wasted round-trip. Split into separate calls in that order.

---

## 4. Custom fields

Custom fields appear in the catalog with `source: custom`. Writable ones are classified `general-update` and behave exactly like built-ins in compact syntax, using their canonical key. File Task property mappings only affect how a field is serialized into frontmatter, so a visible property named `Deadline` never replaces the canonical key `dateDue`.

Check the current custom set:

```bash
.codex/skills/operon-tasks/scripts/op-catalog.sh | sed -n '/custom fields/p'
```
