---
name: operon-cli
description: Complete reference for the Operon CLI - all 47 commands, compact and typed mutation routes, sealed plan lifecycle, limits, error registry, and recovery. Use for deep or unusual CLI work, typed JSON mutations (transition, timer, graphs), plan mechanics, error recovery, and as the authoritative command reference. For fast daily task work, use the operon-tasks skill instead.
---

# Operon CLI Reference

Complete, truth-accurate reference for the `operon` CLI. The CLI talks to the
running Obsidian instance: every read is fresh, and every write compiles to a
sealed mutation plan that keeps the index, recurrence, trackers, parent
aggregates, and reminders consistent. **Prefer this over editing task markdown
by hand.**

---

## 0. Preflight (one call, always)

```bash
operon health
```

Proceed only when `Phase: ready` and `Admission: reads yes, writes yes`.

| Output | Action |
|---|---|
| `Phase: ready`, writes yes | Continue. |
| `writes no` or phase not ready | Reads only. Report to the user; do not retry in a loop. |
| `command not found` | The CLI is not installed. Stop and tell the user. |
| Exit code 3 (`unavailable`) | Obsidian is closed or the vault is not open. Ask the user to open it. |

Vault selection is automatic (single profile `stratejya`). Never pass `--vault`
or `--profile` unless the user names another vault.

---

## 1. Two skills, one CLI

- **operon-tasks** is the dictation-first daily driver: one dictated intent,
  one call, through its `op-do.sh` dispatcher and maintained wrapper scripts
  (`.claude/skills/operon-tasks/scripts/`: `op-do.sh`, `op-id.sh`, `op-q.sh`,
  `op-catalog.sh`). For fast day-to-day task work, use that skill.
- **operon-cli** (this skill) is the deep reference: every command, the typed
  contracts, plan mechanics, limits, and error recovery. Reach for it when the
  wrappers do not cover the case, when debugging, or when exact contract truth
  matters.

This reference stands alone: every wrapped operation is also documented as its
raw `operon` command.

---

## 2. Quick Reference (all 47 commands)

| Group | Commands | Detail |
|---|---|---|
| Read and inspect | `task get`, `query`, `finder`, `relationships`, `entity resolve`, `context`, `timer state`, `task find` (TTY only) | `references/commands.md` §1 |
| Create | `task create` (compact / batch 1-64 lines / typed) | `references/compact-syntax.md`, `references/typed-mutations.md` |
| Update | `task update` (compact / batch 2-64 lines / typed) | `references/compact-syntax.md` |
| Lifecycle | `task complete`, `reopen`, `cancel`, `transition` (typed-only) | `references/commands.md` §4 |
| Reminders | `reminder add`, `replace`, `remove` | `references/commands.md` §5 |
| Pin | `task pin`, `unpin` | `references/commands.md` §6 |
| Timer | `timer start`/`stop` (typed-only, target optional), `timer session add/update/remove` | `references/commands.md` §7 |
| Structure | `task relocate`, `task convert`, `task delete` | `references/commands.md` §8 |
| Plans | `plan show`, `apply`, `recover`, `discard`, `mutation preview`, `mutation apply` | `references/plans-and-limits.md` |
| Health and meta | `health`, `capabilities`, `diagnostics`, `catalog`, `manifest`, `schema list/get`, `version`, `doctor`, `setup`, `profile list/default/remove`, `completion` | `references/commands.md` §10 |

Three commands have **no compact argv form** and take only typed
`mutation-intent` input: `task transition`, `timer start`, `timer stop`
(`references/typed-mutations.md`).

---

## 3. Which command owns the field

The single biggest source of failed calls. `task update` does **not** own
status, reminders, pins, trackers, or conversions. Summary; full map with
traps: `references/field-ownership.md`.

| Want to change | Command |
|---|---|
| description, tags, priority, dates, datetimes, estimate, assignees, contexts, note, links, location, taskIcon, taskColor, custom fields | `operon task update --id X key::"V"` |
| status | `task complete` / `reopen` / `cancel` / `transition` (typed transition can carry field changes atomically) |
| parentTask, blocking, blockedBy | `task update`, relationship route, never mixed with general fields |
| repeat, datetimeRepeatEnd, dates on a recurring task | `task update --scope this-task\|this-and-following`, never mixed |
| reminderDatetimes, reminderRules | `reminder add` / `replace` / `remove`, one item per call |
| pinned | `task pin` / `unpin` |
| activeTracker | `timer start` / `stop` (typed) |
| trackers (sessions) | `timer session add` / `update` / `remove` |
| representation | `task convert` |
| locator | `task relocate` |
| operonId, duration, progress, totals, subtask counts, created/modified, timezone, series state | nothing; Runtime-owned, read only |

Canonical keys only. The visible property names in the vault are different:
`Tier`=`priority`, `Up`=`contexts`, `Notes`=`note`, `Deadline`=`dateDue`,
`Scheduled`=`dateScheduled`, `Started`=`dateStarted`, `People`=`assignees`,
`ParentId`=`parentTask`, `Coordinates`=`location`, `Icon`=`taskIcon`,
`Color`=`taskColor`.

---

## 4. Creating tasks in this vault

Use the compact form, with no target flags, and let the Runtime resolve
placement:

```bash
operon task create "Draft the release notes" status::"<Pipeline.Status>" \
  priority::"<Priority>" dateDue::"2026-08-01"
```

With no `inline`/`file` keyword the intent carries
`target.mode: "configured-default"` and the Runtime picks representation and
placement from the user's live settings. Under `specific-file` save mode it
creates that day's `## [[YYYY-MM-DD]]` heading itself. Do not probe settings
or placement candidates first.

**One real failure.** Under `daily-notes` save mode, if that day's note does
not exist yet *and* the core daily-notes plugin has a template configured, the
Runtime returns `Configured Daily Note creation requires template processing;
provide an exact existing target.` Handle it when it happens: ask the user to
open the daily note, then retry. Do not pre-check, and do not substitute
another file.

`dateScheduled` is **not** derived from `datetimeStart` at create time
(`scheduling-rules.ts` only runs on update), so pass both when a task has a
start time. Reminders and repeat can go in the same create call;
`temporalCreateKeys` is advertised live.

The typed JSON route still exists for graphs, body replacement, exact
placement, and custom templates: `references/typed-mutations.md`.

---

## 5. Compact syntax in one screen

```
operon task create [inline|file] "Description" [canonicalKey::"VALUE" ...]
operon task update (--id "ID"|--description "EXACT") (key::"VALUE"|--clear "key")...
```

- Assignments split at the **first** `::`. Lists use `; ` (`\;` for a literal
  semicolon). Each canonical key at most once per command, counting `--clear`.
- `key::""` is invalid and never means clear. Use `--clear "key"`.
- `estimate` is **seconds**. Datetimes are local-naive, canonical form
  `YYYY-MM-DDTHH:mm:ss` (a `HH:mm` input stays valid, seconds default to `00`);
  `Z` and offsets are rejected.
- `reminderRules` is `anchor.offset` with lowercase units (`dateDue.30m`);
  `repeat` is the normalized rule form.
- **Batch**: create takes 1-64 lines, update takes 2-64 `--id`-prefixed lines,
  via `--input-format compact-lines --input -`; each batch is one atomic
  preview-only plan.

Full grammar, batch line format, and edge cases:
`references/compact-syntax.md`.

---

## 6. Apply policy (agreed with the vault owner)

Compact argv **previews and then automatically applies** a plan that is
unchanged, warning-free, unacknowledged, unconfirmed, and non-destructive.
That is the normal path and it is allowed here, including with `--json`.
Typed `--input` and all stdin batch forms are **always preview-only**: apply
the returned planRef separately, promptly.

**Plans expire.** Read `expiresAt` from the plan; observed windows are
~5 minutes for a routine plan and **~60 seconds for a destructive one**
(measured 2026-07-31; the manifest publishes no duration). Preview and apply
belong in the same breath, never across turns.

**These never auto-apply. Preview them, report the plan, and ask the user
before applying:**

| Operation | Why |
|---|---|
| `operon task delete` | Destructive. Needs a fresh `DELETE` confirmation. |
| `operon task convert --to inline` (File to Inline) | Destructive. Needs `CONVERT`. |
| `operon timer session remove` | Destructive. Needs `REMOVE`. |

Run those with `--preview-only`, show the user what the plan touches, then
hand them the plain interactive command to run themselves (it prompts for the
literal `DELETE`, `CONVERT`, or `REMOVE` in their terminal). The `--confirm`
token can be derived, but deriving it to apply a destructive plan yourself
defeats the gate. Do not.

**Uncertain results are never retried.** If a call reports `outcome-unknown`,
times out, or dies mid-apply:

```bash
operon plan recover <planRef>
```

Do not re-run the mutation, do not build a new preview, do not create a new
idempotency key. There is exactly one correct next command and it is
`plan recover`. (A failed or expired *preview* wrote nothing and may be
rebuilt freely.)

---

## 7. Exit codes (canonical table)

| Code | Meaning | What to do |
|---|---|---|
| 0 | success | Applied, previewed, or a legitimate no-change. Continue. |
| 2 | usage | Your syntax or a canonical key is wrong. Fix it, do not retry as is. |
| 3 | unavailable | Obsidian closed, runtime not ready, capability missing. Report; do not loop. |
| 4 | refused | Fail-closed guard: ambiguous target, zero matches, capability gate, confirmation required, expired plan. Read the message. |
| 5 | runtimeFailure | Runtime error, including `outcome-unknown` (recover the plan). Report the message verbatim. |
| 70 | internal | CLI bug. Report verbatim. |
| 130 | interrupted | The process was interrupted. If it was mid-apply, treat as uncertain: `plan recover`. |

The manifest's 38-entry error registry maps every error code to its correct
response, including the only three retryable codes:
`references/plans-and-limits.md` §7.

---

## 9. Hard rules

1. **Line numbers split by route.** Typed create placement, placement
   candidates, finder rows, and every mutation `target.locator` are
   **zero-based**. Only `task relocate --line` and `task convert --line` take
   **one-based** human numbers. This is the canonical statement; everything
   else points here.
2. **`task get --id` is a partial projection.** It omits `note`, `tags`,
   `contexts`, `assignees`, `links`, `location`, `taskIcon`, `taskColor`,
   `estimate`, and all reminders. Never conclude a field is unset from it, and
   never rebuild a list from it; hydrate with `include: ["writable-fields"]`.
3. **Typed JSON uses stable IDs** (`st_...`, `pr_...`), compact argv uses
   labels. Reads return stable IDs (`priority: pr_c`).
4. **`operon session` does not exist in CLI 1.0.0.** The manifest declares the
   protocol, but the command is not implemented. Do not use or document it as
   usable.
5. **The apply envelope carries no created ids.** After a compact auto-applied
   create, get the id from `operon plan show <client.planRef>` or use the
   batch route whose preview prints `createEffects`
   (`references/recipes.md` §5).
6. **Inputs strict, outputs additive** (`contractPolicy`): an unknown key in a
   request is exit 2; an unknown key in a result is ignored safely.
7. **planRef lives at `.client.planRef`** on the JSON envelope.
   `.result.plan.planId` is an internal UUID that `plan apply` rejects.
8. **Never two concurrent writes.** Reads batch freely; writes are strictly
   sequential, no `&`, no parallel agents.

---

## 10. References

Load on demand. Do not read them all up front.

| File | Read it when |
|---|---|
| `references/commands.md` | Any command's exact usage, flags, targetPolicy, or semantics. All 47 commands, grouped. |
| `references/compact-syntax.md` | Writing any compact create or update, batch lines, escaping, `--scope`, relationships. |
| `references/typed-mutations.md` | Typed `mutation-intent` routes: create graphs and templates, the transition intent, the timer intent. |
| `references/field-ownership.md` | Which canonical key matches a visible property, which command owns a field. |
| `references/plans-and-limits.md` | Plan lifecycle, expiry, confirmation tokens, error registry, numeric limits, staleness canaries. |
| `references/recipes.md` | End to end scenarios. Check here first for anything multi-step. |

## 11. Is this skill still current?

Verified against contractDigest
`d280747a21f46add48d70193205c4dc642b1e0f38447209611174e33beff5927`
(operon-cli 1.0.0, plugin 3.0.0, 2026-07-31). Check:

```bash
operon manifest --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["contractDigest"])'
```

Same digest: this skill is authoritative. Different: trust live `--help` and
the manifest over these files, regenerate the help corpus with
`scripts/help-dump.sh`, update the affected sections, then re-pin the digest
here.

`settingsFingerprint` changing does **not** stale this skill; it only
invalidates catalog caches (statuses, priorities, custom keys). Refresh those
with the operon-tasks `op-catalog.sh --force`.
