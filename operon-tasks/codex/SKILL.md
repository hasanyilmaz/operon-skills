---
name: operon-tasks
description: "Daily Operon task work against the live Runtime - create single tasks or whole subtask trees, update fields, complete/reopen/cancel, transition mid-pipeline, set reminders, pin, start/stop timers, edit tracker sessions, batch-update up to 64 tasks, move, convert, and delete, plus fast lists and lookups. Built for dictation-first use: one dictated intent becomes one command. Use for any request to add, change, finish, find, or remove a task in the vault."
---

# Operon tasks

One dictated intent, one command. Every row of the router in section 4 is a
single call; reaching for anything slower than the router is the bug.

Every write goes through Operon's own mutation pipeline, so the index, parent
rollups, repeat series, reminders and trackers all stay consistent. Hand-editing
task markdown does not do that: setting a finished status by hand leaves
`dates.completed` null, omits `Finished`, and leaves `datetimeModified` stale,
silently.

Shorthand used below:

```bash
OP="$(cd .codex/skills/operon-tasks/scripts && pwd -P)"
```

**Every `<Pipeline.Status>`, `<path>` and `<ID>` in this document is a
placeholder.** Nothing in these examples is a working value for this vault.
Resolve real values with section 2 before you run anything.

---

## 0. Preflight

One call, once per session.

```bash
operon health
```

Must show `Phase: ready` and `Admission: reads yes, writes yes`. Exit 3 means
Obsidian is closed or the vault is not open: say so, do not loop.

---

## 1. Routing: pipeline, status, priority

**Every task is routed by reading the user's own descriptions. Never by guessing
from a pipeline's name.** The user authored a description for each pipeline and
each priority level, and those descriptions are the specification. This step is
mandatory on every single task, including one-line ones, and applies equally to
`op-do.sh transition --to` targets.

```bash
$OP/op-catalog.sh --statuses
```

That prints each pipeline's exact `Pipeline.Status` values together with its
authored description, then the full priority ladder with its descriptions. It is
one local read off a 900s cache, so it costs no extra round-trip. Read it,
decide, then act. Do not skip it because the request looks obvious.

There is no default pipeline. `defaultPipelineId` and `defaultStatusId` are both
null in this vault, so nothing picks one for you and no value in this document is
a suggestion.

### How to read the descriptions

1. **The "Do not use..." sentences are binding.** Most descriptions name the
   pipelines they are explicitly *not* for. A match on the positive half does not
   survive a hit on the negative half. Check the exclusions before committing.
2. **Ask what the tracked work object is**, which is the test several descriptions
   state outright. A book's reading lifecycle is the book; a session spent reading
   it is not. An appointment is the occasion itself; a task that merely has a
   clock time is not.
3. **A date or a time is not a routing signal.** Two descriptions warn against
   exactly this inference. Scheduling lives in `datetimeStart` and
   `dateScheduled`, not in the pipeline choice.
4. **Status meaning lives inside the pipeline description**, in its closing
   sentence: statuses carry no description of their own. Pick the status by where
   the work actually stands, not always the first one. Something already agreed
   and dated is planned, not an idea.
5. **A pipeline with no authored description** gets judged from its status labels
   alone. Treat it as a weak match: prefer a described pipeline that genuinely
   fits.

### Priority

Choose a priority on every task, from the ladder in the same output. Each level's
description states when to pick the neighbouring level instead, so read the
comparison rather than the label. Omitting `priority::` silently accepts the
default, which is a real choice made by not looking: only let it stand when the
default's own description actually fits the work.

Do not confuse importance with urgency. A task tonight at 22:00 is not important
because it is soon.

### When it is genuinely ambiguous

If two pipelines still fit after their exclusions have been applied, ask the user
which one. That question costs one turn. A task filed under the wrong pipeline
pollutes their boards until they find it.

---

## 2. Exact strings

```bash
$OP/op-catalog.sh              # routing sheet + canonical keys by owning command
$OP/op-catalog.sh --statuses   # routing sheet: pipelines + descriptions + priority ladder
$OP/op-catalog.sh --bare       # only the Pipeline.Status labels, no descriptions
$OP/op-catalog.sh --force      # bypass the 15 min cache after a settings change
```

Use `--statuses` when choosing a pipeline, status or priority. `--bare` is only
for re-checking spelling of a value you have already reasoned about.

Cached in `~/.cache/operon-skill/`, 900s TTL, validated against the live
`settingsFingerprint`. **The cache is only checked against the live fingerprint
after the TTL expires.** If the user says they just changed Operon settings, run
`--force`; you cannot detect it otherwise.

---

## 3. From dictation to a task line

Spoken input packs several fields into one sentence. "I've got a one hour
catch-up with Sarah tomorrow at two" carries a description, a `datetimeStart`, an
`estimate` and an `assignees` at once. The job is not to tidy the prose. It is
to route each piece to where it belongs and leave only the irreducible action in
the description.

Route every piece of the sentence in this order. Running it backwards turns
`note` into a dumping ground.

1. Does it have a field? → the field
2. Is it needed to perform the task? → the description
3. Neither, but worth keeping? → `note`
4. None of those → drop it

### The description

- **Action plus object, nothing else.** Anything with a field goes to the field.
- **Keep what makes it doable, drop what only schedules it.** Ask: can I perform
  this without that detail? "Stop by the bookshop" without the book is not
  doable, so the book stays. "Tomorrow at four" is scheduling, so it goes to
  `datetimeStart`.
- **Imperative, no first person.** "I need to", "I have to", "I'm going to" and
  "I want to" all drop out. Possessives are noise, the list is already the
  user's: "I need to walk my dog" → "Walk the dog". The same shape applies in
  whatever language the user dictates in.
- **Strip dictation filler**: "um", "like", "you know", "sort of", "I guess",
  repeated words.
- **Keep the user's language and their words.** Do not translate. Do not expand a
  title you are not certain of ("Dune" stays "Dune").
- **Several actions stay one task when they happen in one place at one time.**
  Split them only when they are genuinely separable.

| Dictated | description | routed to fields |
|---|---|---|
| "I've got a meeting tomorrow at two, about an hour, with Sarah" | Meeting with Sarah | `datetimeStart` `datetimeEnd` `estimate` `assignees` |
| "I need to walk my dog, around six, two hours at the park" | Take the dog to the park | `datetimeStart` `datetimeEnd` `estimate` |
| "stop by the bookshop and ask if Dune came in" | Stop by the bookshop and ask if Dune came in | one trip, one task |

### Time: start, end, estimate, scheduled

`datetimeStart`, `datetimeEnd` and `estimate` are three views of one interval, so
**any two of them determine the third, and the third gets written too.** Both
rows above show it: "tomorrow at two, about an hour" is a start, an end and an
estimate, not two fields and a gap. Compute the missing one and put it in the
same call.

- `datetimeEnd` = `datetimeStart` + `estimate`
- `estimate` = `datetimeEnd` - `datetimeStart`
- `datetimeStart` = `datetimeEnd` - `estimate`

Nothing derives this for you, not at create time and not on update, so a task
left with only two of the three reads as half-specified on every board, agenda
and timeline that consults the one you skipped. `estimate` is seconds: one hour
is `3600`.

**`dateScheduled` rides along with `datetimeStart`, always**, same date as the
start unless the user said otherwise. The creation adapter never derives it
(§12), so a create with a start time and no `dateScheduled` silently lands a
timed task with no scheduled date.

One of the three alone is not a gap to fill. "At eleven" with no duration stays
`datetimeStart` plus `dateScheduled`: do not invent an interval the user did not
dictate.

### The note

`note` takes what has no field and does not belong in the description:

- why: `note::"before the match starts"`
- a precondition: `note::"bookshop closes at six"`
- an alternative no field can hold: `note::"Saturday works too if that falls through"`
  (`dateScheduled` takes one value)
- an assumption you made resolving vague dictation:
  `note::"user said 'around two', read as 14:00"`
- detail that would make the description unreadable on a board

**Never copy a field's value into `note`.** Fields are updated by mutations,
notes are not, so a note that restates a field becomes a silent lie the first
time the task moves. Recording an assumption does not break that rule: writing
down *what the user said* is information no field can carry; restating *what the
field already holds* is a second source of truth.

`note` is one line. It lives inline as `{{note:: ...}}` and cannot hold newlines.

Say it in one line in your reply when you rewrote the description substantially.
Silently rewriting what the user said is the same class of error as silently
substituting a placement.

### Multi-intent sentences

One dictated sentence often carries several intents. Map each to its own router
row and run them **sequentially**, never in one parallel Bash block: writes must
not overlap.

| Dictated | Commands, in order |
|---|---|
| "finish the Sarah meeting, then move the bookshop one to Friday" | `$OP/op-do.sh complete --find "Sarah"` then `$OP/op-do.sh update --find "bookshop" dateDue::"<friday>"` |
| "start the clock on the draft and pin it" | `$OP/op-do.sh timer-start --find "draft"` then `$OP/op-do.sh pin --id <id from the target echo>` |
| "push those three tasks to next week" | one `$OP/op-do.sh batch-update -` heredoc with three `--id` lines |
| "new task: draft the report, due tomorrow, and set a reminder" | ONE create call carrying `dateDue` and `reminderRules` together (never create-then-remind) |

A `--find` mutation echoes `# target: <id> <status> <description>` to stderr.
Reuse that id for the follow-up intents in the same sentence instead of
resolving the same task twice.

---

## 4. The router

Match the dictated intent to a row, run the one command, done. Every row
presumes the section 1 routing read (cached, costs nothing). If a row fails,
its detail section is linked; do not improvise around a failure.

| Intent | Command | Calls |
|---|---|---|
| Create one task | `operon task create "<desc>" status::"<Pipeline.Status>" priority::"<P>" [fields...]`, or `batch-create` when you want the id or an icon | 1 |
| Create 2-64 tasks | `$OP/op-do.sh batch-create -` heredoc, §8 | 1 |
| Give a task an icon and color | add `taskIcon::"?english concept words" taskColor::"RRGGBB"` to the same line, §5 | 0 extra |
| Subtask tree | parent create, then children via `batch-create` with `parentTask::"<ID>"` | 2 |
| Update, id known | `$OP/op-do.sh update --id <ID> key::"v" [--clear "key"]` | 1 |
| Update, by prose | `$OP/op-do.sh update --find "<prose>" key::"v"` | 1 |
| Update 2-64 tasks | `$OP/op-do.sh batch-update -` heredoc, §8 | 1 |
| Reschedule / move in time | `$OP/op-do.sh update ... dateScheduled::"..." datetimeStart::"..." datetimeEnd::"..."` | 1 |
| Complete / reopen / cancel | `$OP/op-do.sh complete\|reopen\|cancel (--id\|--find)` (`reopen` usually needs `--any`) | 1 |
| Mid-pipeline status move | `$OP/op-do.sh transition (--id\|--find) --to "<Pipeline.Status>" [key::"v"...]` | 1 |
| Timer start / stop on a task | `$OP/op-do.sh timer-start\|timer-stop (--id\|--find)` | 1 |
| Timer start / stop, no task | `$OP/op-do.sh timer-start` / `timer-stop` (no target) | 1 |
| What is the timer doing | `operon timer state` | 1 |
| Log a past work session | `$OP/op-do.sh session-add (--id\|--find) --start "..." --end "..."` | 1 |
| Fix a recorded session's times | `$OP/op-do.sh session-update (--id\|--find) --session N --start "..." --end "..."` | 1 |
| Add / change / drop a reminder | `$OP/op-do.sh reminder-add\|reminder-replace\|reminder-remove (--id\|--find) ...` | 1 |
| Pin / unpin | `$OP/op-do.sh pin\|unpin (--id\|--find)` | 1 |
| Today's agenda | `$OP/op-id.sh "" --scope happens-today --limit 20` | 1 |
| Overdue sweep | `$OP/op-id.sh "" --scope overdue --limit 25` | 1 |
| Find a task / get its id | `$OP/op-id.sh "<prose>"` (add `--one` / `--one-row` for exactly one) | 1 |
| Conditional list | `$OP/op-q.sh --status ... --priority ... --due-to ...` | 1 |
| Every task in one note | `$OP/op-q.sh --file "<path>"` (never one query per task) | 1 |
| Project subtree | `$OP/op-id.sh "" --project-tree <ID> --limit 50` | 1 |
| Read note/tags/reminders etc. | typed `task get` one-liners, §6 | 1 |
| Move a task line in the vault | `operon task relocate --id <ID> --target-file "<path>" --line N` (§10 for candidates) | 1-2 |
| Delete / convert / remove session | manual confirmation gate, §10. Never automated. | preview + user |

---

## 5. Create

Everything in one command. Compact create previews and applies in a single
process when the plan is routine and warning-free. `status::` and `priority::`
come from the section 1 routing read.

```bash
operon task create "<description>" status::"<Pipeline.Status>" \
  priority::"<Priority>" dateDue::"2026-08-15"
```

A dated block with reminders, still one command:

```bash
operon task create "Meeting with Sarah" status::"<Pipeline.Status>" \
  priority::"<Priority>" dateScheduled::"2026-07-30" \
  datetimeStart::"2026-07-30T14:00:00" datetimeEnd::"2026-07-30T15:00:00" \
  estimate::"3600" assignees::"Sarah" reminderRules::"datetimeStart.1h"
```

**Do not pass `inline` or `file` unless the user asked for one.** With no
keyword the Runtime picks from the user's `defaultToFileTask` setting. **Do not
research placement**: `configured-default` resolves representation and placement
from the user's live settings, correctly, including creating the per-day
`## [[YYYY-MM-DD]]` heading itself. Probing settings or placement candidates
before a create is wasted turns.

Fields accepted at create time: `status priority dateDue dateScheduled dateStarted
datetimeStart datetimeEnd estimate assignees contexts tags note links location
taskIcon taskColor parentTask reminderRules reminderDatetimes repeat
datetimeRepeatEnd`. Reminders travel inside the create plan; never split them
into a follow-up call.

Need the new id: use `batch-create` even for one task. It prints
`operonId  filePath` per created task, still one call. (The plain compact
create's `--json` output is the apply envelope, which contains **no**
`createEffects` and no id at all.)

```bash
$OP/op-do.sh batch-create - <<'EOF'
"<description>" status::"<Pipeline.Status>" priority::"<Priority>"
EOF
```

### Several tasks: one call

```bash
$OP/op-do.sh batch-create - <<'EOF'
"Draft the notes" status::"<Pipeline.Status>" priority::"A" dateDue::"2026-08-15"
"Review with team" status::"<Pipeline.Status>" dateDue::"2026-08-16"
"Publish" status::"<Pipeline.Status>"
EOF
```

1-64 lines, each an optional `inline `/`file ` prefix, then a **quoted**
description, then `key::"value"` pairs. No blank lines. op-do previews, checks
the plan, and applies it in the same process, then prints `operonId  filePath`
per created task.

### Icons: `taskIcon::"?concept words"`

Give every created task an icon. Write a `?` query instead of an icon id and
op-do.sh resolves it offline against the plugin's lucide tag corpus (1694
icons), inside the same process: no extra call, about 15 ms.

```bash
$OP/op-do.sh batch-create - <<'EOF'
"<description>" status::"<Pipeline.Status>" taskIcon::"?invoice bill receipt payment"
"<description>" status::"<Pipeline.Status>" taskIcon::"?doctor medical appointment health"
EOF
```

**The corpus is English, the user is not.** Whatever language the dictation is
in, you translate it into **2-4 English concept words** and pass those. The
words are alternatives, best match wins, so extra words are free insurance and a
single word is the main failure mode (`?invoice` finds nothing, `?invoice bill
receipt payment` finds `receipt`). Never write per-language synonym tables: a
vault can be dictated in any language and you already translate for free.

Resolution is best-effort by design. No match means the icon is dropped with a
warning on stderr and the task is still created. Where it works: `batch-create`,
`update`, `transition`, that is every op-do.sh path. Plain `operon task create`
does **not** expand `?` tokens, so route creates that want an icon through
`batch-create` (which you likely want anyway, for the id).

To see candidates before committing, or to check an id you already have in mind:

```bash
$OP/op-icon.sh "release deploy ship version"      # query<TAB>id,id,id
$OP/op-icon.sh --validate rocket ship             # id<TAB>ok|missing
```

### Colors: `taskColor::"RRGGBB"`

Pair every icon with a color. Write the hex straight into the line, bare, no
`#`, no lookup, no script: it costs nothing but the characters.

```bash
"<description>" status::"<Pipeline.Status>" taskIcon::"?invoice bill receipt payment" taskColor::"D97706"
```

The color must agree with the icon and the description, never contradict them.
Read the meaning, then pick: money warm amber/gold, health teal/green, urgent or
broken red, deadlines and admin slate, learning and reading indigo/violet,
travel sky, social and gifts pink/rose, routine chores zinc. These are anchors
for consistency, not a permitted list: the same concept should get the same
color next week, and an unlisted concept just gets the hex that fits it.

Hex only. Palette **names do not work**: `taskColor::"blue"` is written as
`#blue` and renders as nothing.

### A parent with children

compact lines are flat: `parentTask` only accepts an id that already exists.
Two sequential calls:

```bash
PARENT=$($OP/op-do.sh batch-create - <<'EOF' | cut -f1
"Release checklist" status::"<Pipeline.Status>" priority::"<Priority>"
EOF
)

$OP/op-do.sh batch-create - <<EOF
"Draft the notes" parentTask::"$PARENT" priority::"A"
"Review with team" parentTask::"$PARENT"
EOF
```

A child created without an explicit priority **inherits its parent's priority**,
not the system default.

### The one create failure worth knowing

Under `daily-notes` inline save mode, if today's daily note does not exist yet
**and** the core daily-notes plugin has a template configured, the Runtime
returns:

```
Configured Daily Note creation requires template processing; provide an exact existing target.
```

This vault does have a daily-note template configured, so this is real. Do not
pre-check for it: run the command, and if that error comes back, ask the user to
open today's daily note in Obsidian, then retry. Never substitute a different
file on your own.

---

## 6. Find and read

```bash
$OP/op-id.sh "<prose>"                       # candidates, TSV
$OP/op-id.sh "<prose>" --one                 # bare id, or exit 4 with candidates
$OP/op-id.sh "<prose>" --one-row             # full row incl. locator, or exit 4
$OP/op-id.sh "" --scope happens-today --limit 20
$OP/op-id.sh "<prose>" --any                 # include done/cancelled (reopen needs this)
$OP/op-q.sh --open --limit 20
$OP/op-q.sh --status "<Pipeline.Status>" --priority S --due-to 2026-08-31
$OP/op-q.sh --parent <ID> --open
$OP/op-q.sh --file "<path>"                  # every task in one note, ONE query
$OP/op-q.sh --open --limit 20 --cursor last  # next page, repeat the SAME flags
operon task get --id <ID>
operon timer state
```

`op-id.sh` TSV: `operonId  Pipeline.Status  priority  representation  filePath
lineNumber  description`. `lineNumber` is zero-based, exactly what mutation
locators expect. `op-q.sh` TSV: `id  Pipeline.Status  priority  due  parentId
description`.

`op-id.sh` searches **open tasks by default**: finished archive/journal entries
often quote a live task's description verbatim, and the open-only default keeps
them out of `--one` resolution. `--any` turns that off.

**One file, one query.** When several target tasks live in the same note, one
`op-q.sh --file` call lists them all; then mutate with `batch-update`. Never
resolve them one by one.

### Reading fields that plain `task get` hides

`operon task get --id <ID>` omits `note tags contexts assignees links location
taskIcon taskColor estimate` and shows no reminders. For those, the typed route:

```bash
echo '{"contractVersion":1,"requestId":"tg","kind":"task-get","consistency":"live-verified","selector":{"kind":"operon-id","operonId":"<ID>"},"include":["writable-fields"]}' \
  | operon task get --input - --json \
  | jq -r '.result.task.writableFields[] | select(.present) | "\(.canonicalKey)\t\(.value)"'
```

```bash
echo '{"contractVersion":1,"requestId":"tr","kind":"task-get","consistency":"live-verified","selector":{"kind":"operon-id","operonId":"<ID>"},"include":["reminder-items"]}' \
  | operon task get --input - --json \
  | jq -r '.result.task.reminderItems[] | "\(.collection)\t\(.expectedValue)"'
```

`include` takes `writable-fields`, `reminder-items`, or both. One catch:
`priority` comes back as the stable id (`pr_c`), not the label (`C`).

---

## 7. Which command owns the field

**These restrictions apply to updates; at create time everything goes in the one
create call.**

| Field | Route |
|---|---|
| description, tags, priority, dateDue, dateScheduled, dateStarted, datetimeStart, datetimeEnd, estimate, assignees, contexts, note, links, location, taskIcon, taskColor, custom fields | `op-do.sh update` |
| status | `op-do.sh complete` / `reopen` / `cancel` / `transition --to` |
| parentTask, blocking, blockedBy | `op-do.sh update`, relationship keys only, never mixed with the fields above |
| repeat, datetimeRepeatEnd, dates on a recurring task | `op-do.sh update --scope this-task\|this-and-following`, never mixed |
| reminderDatetimes, reminderRules | `op-do.sh reminder-add` / `reminder-replace` / `reminder-remove` |
| pinned | `op-do.sh pin` / `unpin` |
| activeTracker | `op-do.sh timer-start` / `timer-stop` |
| trackers (history) | `op-do.sh session-add` / `session-update`; removal is gated, §10 |
| representation | `operon task convert`, gated, §10 |
| locator | `operon task relocate`, §10 |

Canonical keys only. The vault's visible names are different: `Tier`=`priority`,
`Up`=`contexts`, `Notes`=`note`, `Deadline`=`dateDue`, `Scheduled`=`dateScheduled`,
`People`=`assignees`, `ParentId`=`parentTask`.

---

## 8. Mutating with op-do

```
$OP/op-do.sh <verb> (--id <ID> | --find "prose") [verb args...] [--preview-only] [--json]
```

One process does everything: prose resolution, locator fetch, intent building,
preview, plan triage, apply. Plans expire in 5 minutes, so preview and apply
must never be separated across turns; op-do keeps them seconds apart.

### Targeting

- `--id <ID>` is used verbatim, zero lookups.
- `--find "prose"` resolves through the native finder with `--one` strictness:
  open-only by default (`--any` widens), and among several hits only an exact
  case-sensitive description match wins. Anything else is **exit 4 with a
  candidate TSV and zero mutations**. Disambiguate by re-running with `--id`
  from the candidate list; do not retry `--find` with fuzzier text.
- Every `--find` mutation echoes `# target: <id> <status> <description>` to
  stderr before writing, so the transcript shows what was touched.
- `--scope` narrows `--find` (`overdue`, `happens-today`, `recent`); on the
  `update` verb it is the recurrence scope instead. `--project-tree <ID>`
  narrows to one subtree.

### Examples

```bash
$OP/op-do.sh update --find "bookshop" dateDue::"2026-08-22"
$OP/op-do.sh update --id <ID> contexts::"Operon; Release" --clear "dateScheduled"
$OP/op-do.sh complete --find "release notes"
$OP/op-do.sh reopen --find "shipped thing" --any
$OP/op-do.sh transition --find "draft" --to "<Pipeline.Status>"
$OP/op-do.sh transition --id <ID> --to "<Pipeline.Status>" note::"handed over" priority::"B"
$OP/op-do.sh timer-start --find "draft"
$OP/op-do.sh timer-stop
$OP/op-do.sh session-add --id <ID> --start "2026-07-28T09:00:00" --end "2026-07-28T10:30:00"
$OP/op-do.sh session-update --id <ID> --session 1 --start "2026-07-28T09:15:00" --end "2026-07-28T10:30:00"
$OP/op-do.sh reminder-add --id <ID> reminderRules::"dateDue.30m"
$OP/op-do.sh reminder-replace --id <ID> --current "dateDue.30m" reminderRules::"dateDue.1h"
$OP/op-do.sh pin --find "launch checklist"
$OP/op-do.sh update --id <ID> taskIcon::"?workout gym fitness"
```

Batches read stdin, 1 line per task (`batch-update` needs 2-64, `batch-create`
1-64), and produce ONE atomic plan:

```bash
$OP/op-do.sh batch-update - <<'EOF'
--id "<ID>" dateScheduled::"2026-08-04" --clear "datetimeStart"
--id "<ID>" dateScheduled::"2026-08-04"
--id "<ID>" priority::"D" note::"parked"
EOF
```

### Verb notes

- `transition --to` targets follow section 1 routing like any status choice. The
  current status is sealed automatically as `expectedStatusId` (`--expect`
  overrides), so a concurrent move invalidates the plan instead of overwriting.
  Field changes given alongside ride in the same atomic plan; each field once.
- `timer-start`/`timer-stop` without a target control an **unassigned** timer.
  `--expect-active "<datetime>"` seals against a raced running timer.
- `reminder-*` takes exactly one item per call. Rules are `anchor.offset`,
  lowercase units, and the anchor must exist on the task
  (`dateDue dateScheduled dateStarted datetimeStart datetimeEnd`).
- Sessions are 1-based, oldest-first. Datetimes are local-naive, canonical
  `HH:mm:ss` (a `HH:mm` input stays valid, seconds default to `00`), no `Z`.
- `taskIcon::"?concept words"` is resolved offline before the plan is built
  (§5). It never adds a call and never fails a write: an unmatched query is
  dropped with a stderr warning. A literal id (`taskIcon::"bug"`) is passed
  through untouched.
- Already-finished / already-pinned and friends return `no-change`: success, not
  an error. Never retry.
- `--preview-only` stops at the sealed plan and prints it; nothing is written.
  op-do refuses to auto-apply any plan carrying warnings, confirmation
  requirements, or non-routine risk (exit 4): show that plan to the user.
- On apply failure: **never retry, never re-run.** op-do prints the exact
  `operon plan recover <planRef>` command; run that and report.

---

## 9. Update semantics

```bash
$OP/op-do.sh update --id <ID> priority::"A" note::"Slipped one week"
$OP/op-do.sh update --id <ID> contexts::"Operon; Release"           # replaces the whole list
$OP/op-do.sh update --id <ID> --clear "dateScheduled"               # key::"" is invalid
$OP/op-do.sh update --id <ID> estimate::"5400"                      # seconds
$OP/op-do.sh update --id <ID> contexts::"planning\; phase 2; review"  # \; literal semicolon
$OP/op-do.sh update --id <ID> tags::"cli; beta"                     # tags cannot contain spaces
```

Lists use `; `. Each key may appear once per command. `no-change` is success.

**Every write replaces, none append.** `note::"B"` on a task whose note is `A`
leaves `B` and nothing else. To add to an existing note or list, read the current
value with the `writable-fields` call in section 6, merge it yourself, then write
the merged value in one update.

Relationships, own route, never mixed with general fields:

```bash
$OP/op-do.sh update --id <ID> parentTask::"<PARENT_ID>"
$OP/op-do.sh update --id <ID> blocking::"<ID>; <ID>"
$OP/op-do.sh update --id <ID> --clear "blockedBy"
```

Recurrence, own route, `--scope` mandatory once a task recurs:

```bash
$OP/op-do.sh update --id <ID> repeat::"mode=schedule|freq=week|interval=1|days=mo"
$OP/op-do.sh update --id <ID> --scope this-task dateScheduled::"2026-08-03"
$OP/op-do.sh update --id <ID> --scope this-and-following --clear "repeat"
```

---

## 10. Move, convert, delete: manual gates

```bash
operon task relocate --id <ID> --target-file "<path>" --line 42   # one-based, blank line
operon task delete   --id <ID> --preview-only
operon task convert  --id <ID> --to file --template "<visible template name>" --target-file "<path>"
```

Relocate `--line` must hit a live blank-line candidate; get candidates with:

```bash
echo '{"contractVersion":1,"requestId":"pc","kind":"context","consistency":"live-verified","purpose":"mutation-readiness","projection":"placement-candidates","placement":{"mode":"lines","filePath":"<path>"},"limit":10}' \
  | operon context --input - --json | jq -c '.result.placement.lines[] | {line: (.locator.lineNumber + 1), heading, label: .contextLabel}'
```

**`task delete`, File→Inline `convert`, and `timer session remove` are never
automated.** op-do refuses them by design. Preview, show the user what the plan
touches, then hand them the plain command for their own terminal, which prompts
for the literal `DELETE`, `CONVERT`, or `REMOVE`. Destructive plans expire in
**60 seconds**, and the confirm token must never be derived.

**Deletion is blocked while the task has relationships.** Clear `parentTask`,
`blocking` and `blockedBy` first.

---

## 11. Speed and safety rules

| Rule | Why |
|---|---|
| **Never run two writes at once.** Not two agents, not two terminals, not a background `&`, not two op-do calls in one Bash block. | Measured 0 of 6 succeed; one run left a permanently unrecoverable plan. op-do serializes internally, nothing serializes across processes. |
| Reads may share one Bash block. | Six concurrent reads take 0.099 s. |
| **No `--help`, no `schema get`, no probing during task work.** | This document is the reference. A measured transition cost 15 calls by rediscovering shapes it should have had. |
| Put every field in the create call. | A create with reminders is one command, not three. |
| Use the batch verbs above one target. | Cost is per plan, not per task. |
| **planRef lives at `.client.planRef`** in typed/stdin preview envelopes, never inside `.result`. | `.result.plan.planId` is an internal UUID that `plan apply` rejects. |
| **Plans expire: 5 min routine, 60 s destructive.** Preview and apply live in the same process; never carry a planRef across turns. | An expired plan is dead; the mutation never happened. |
| Never retry a mutation. | On `outcome-unknown` the only correct command is `operon plan recover <planRef>`. A failed *preview* wrote nothing and may be re-run once. |
| Do not re-read to "verify" a write. | The CLI already reports the applied state. |
| A slow call is not a hung call. | Two 20 s stalls were measured against a 0.78 s median. Wait. |
| Do not research placement before a create. | `configured-default` resolves it live and correctly. |
| **Always route from the authored descriptions** (`--statuses`), never from a pipeline's name. | The user wrote them, and they contain binding "Do not use..." exclusions. The read is cached and free. |
| Set `priority::` deliberately on every create. | Omitting it silently accepts the default. That is a choice made by not looking. |
| **Two of `datetimeStart`/`datetimeEnd`/`estimate` given means all three written, and `datetimeStart` always brings `dateScheduled`.** | Nothing derives them for you at create time. Half an interval reads as wrong, not as missing, on every board and agenda (§3). |
| Icons come from a `?` query, never from memory. | `taskIcon` is unvalidated free text: an invented id applies cleanly and renders nothing. The query is offline and free. |
| Colors come straight from meaning, no lookup, and must match the icon. | A hex costs 10 characters in a line you are already writing. A color that fights its icon is worse than no color. |
| One file, one query. | `op-q.sh --file` lists every task in a note in one call. |
| Ambiguous `--find` is exit 4 with candidates. | Continue with `--id` from the list; never rerun with fuzzier text, never fuzzy-mutate. |
| Never report a previewed plan as done. | `--preview-only` writes nothing. Only an applied plan changed the vault. |

Exit codes: `0` ok/no-change, `2` your syntax or a refused destructive verb,
`3` runtime unavailable, `4` fail-closed guard (ambiguous target, plan needs
review), `5` runtime failure or apply-uncertain, `70` CLI bug.

---

## 12. Notes worth knowing

- **`dateScheduled` must accompany `datetimeStart` at create time.** The Runtime
  derives one from the other only on update; the creation adapter never calls
  that rule. A task created with `datetimeStart` alone ends up with a time and no
  scheduled date, silently. On update it is derived automatically.
- **Two of `datetimeStart`/`datetimeEnd`/`estimate` means writing all three.**
  Nothing computes the third at any point in the pipeline, at create or at
  update, so the arithmetic is yours (§3).
- `estimate` is seconds. `datetimeStart`/`End` are local-naive, no `Z`, no
  offset; the canonical form carries seconds (`YYYY-MM-DDTHH:mm:ss`); a `HH:mm`
  input stays valid (seconds default to `00`), but write seconds in new values.
- `tags` items cannot contain spaces or `# , [ ] { } | \ ^`. Use `contexts` for
  anything with a space.
- `assignees` in this vault is plain text (`Sarah`), not wikilinks.
- `task convert --to file` can fail with exit 70 and `Predicted effects must be
  unique` on some tasks. Runtime contract bug, not your command.
- Custom fields behave like built-ins in compact syntax and in op-do.
- The icon corpus is the plugin's build artifact
  `.obsidian/plugins/operon/src/generated/lucide-icon-tags.ts`. op-icon.sh walks
  up from its own directory to find it and honours `OPERON_ICON_TAGS`. If the
  build moves it, icon queries warn loudly and writes continue without an icon;
  they never break.
- `taskIcon` is a free-text field: the Runtime does **not** validate icon ids, so
  an invented id applies cleanly and renders as nothing. That is exactly why
  icons go through `?` queries or `op-icon.sh --validate`, never straight from
  memory.
- `taskColor` is free text too, normalized by stripping a leading `#`. Any hex
  applies, inside the user's palette or not, which is why it needs no lookup.
- Writing `taskIcon`/`taskColor` suppresses two fallbacks: a subtask inherits the
  parent's icon and color only when its own are empty, and a task with no icon
  shows its status or priority icon instead. Setting them is a deliberate
  override, so leave both empty when the user asks for a bare task.
- Deeper reference, contracts, and typed JSON routes live in the `operon-cli`
  skill if it is installed. This skill does not need it.
