# Recipes

End to end sequences using the raw CLI. `OP=.claude/skills/operon-tasks/scripts`
in every example (the maintained wrapper scripts live in the operon-tasks
skill; each recipe also shows the raw command so this reference stands alone).
Every `<Pipeline.Status>` and `<Priority>` is a placeholder: resolve live
values from the catalog first.

---

## 1. Add a quick task

```bash
operon task create "Call the accountant back" status::"<Pipeline.Status>" priority::"<Priority>"
```

One compact call; the Runtime resolves representation and placement from the
user's live settings (`configured-default`). Do not probe placement first.

## 2. Add a properly classified project task

```bash
operon task create file "Operon CLI beta release" \
  status::"<Pipeline.Status>" priority::"A" \
  dateDue::"2026-08-15" dateScheduled::"2026-08-10" \
  contexts::"Operon; Release" tags::"cli; beta" \
  note::"Blocked on live acceptance"
```

## 3. Add a task under an existing project

```bash
PARENT=$($OP/op-id.sh "Operon - Skill Library" --one)
operon task create "Write the operon-task skill" parentTask::"$PARENT" \
  status::"<Pipeline.Status>" priority::"B"
```

## 4. Create with reminder and recurrence, one atomic plan

```bash
operon task create "Standup notes" status::"<Pipeline.Status>" \
  dateDue::"2026-08-03" reminderRules::"dateDue.30m" \
  repeat::"mode=schedule|freq=week|interval=1|days=su"
```

Reminders and recurrence belong **inside** the create plan
(`temporalCreateVersion: 1`). Never create first and attach them in follow-up
calls: that opens a window where the task exists without its reminder.

## 5. Get the operonId of the task you just created

The compact auto-apply envelope contains **no id**. Two routes:

```bash
# Route A: batch stdin (works for one task too) - preview prints ids, then apply
operon task create --input-format compact-lines --input - --json <<'EOF' \
  | jq -r '.result.plan.createEffects[] | "\(.operonId)\t\(.locator.filePath)"; "\(.client.planRef)"'
"Draft the notes" status::"<Pipeline.Status>" priority::"<Priority>"
EOF
operon plan apply <planRef> --json

# Route B: after a compact auto-apply, read the plan it applied
operon task create "Draft the notes" status::"<Pipeline.Status>" --json > out.json
operon plan show "$(jq -r '.client.planRef' out.json)"     # createEffects carry the id
```

The one-call wrapper for route A is `$OP/op-do.sh batch-create -`.

## 6. Push a deadline

```bash
ID=$($OP/op-id.sh "beta release" --one)
operon task update --id "$ID" dateDue::"2026-08-22" note::"Slipped one week"
```

## 7. Clear a field

```bash
operon task update --id "$ID" --clear "dateScheduled"
```

`dateScheduled::""` would be a usage error. `--clear` is the only way.

## 8. Append to a list (read the real current value first)

Lists always **replace**. To append, read the current value through the typed
`task-get` with `writable-fields`. **Never read it from plain
`task get --id`:** the shorthand omits `contexts`, `tags`, `note`, `estimate`
and friends from its projection, so an "append" built on it silently erases
the existing list.

```bash
CUR=$(echo '{"contractVersion":1,"requestId":"r1","kind":"task-get","consistency":"live-verified","selector":{"kind":"operon-id","operonId":"'"$ID"'"},"include":["writable-fields"]}' \
  | operon task get --input - --json \
  | jq -r '.result.task.writableFields[] | select(.canonicalKey=="contexts" and .present) | .value | join("; ")')
operon task update --id "$ID" contexts::"${CUR:+$CUR; }Beta"
```

## 9. Re-parent a task

```bash
operon task update --id "$ID" parentTask::"b5jdsct"
```

Relationship route. Do not add a general field to this command.

## 10. Set a dependency chain

```bash
operon task update --id "$ID" blocking::"def5678; ghi9012"
operon task update --id "$ID" --clear "blockedBy"
```

Both relationship keys can go in one command, but never with `note::` or a
date.

## 11. Change status and fields together, atomically

For complete/reopen/cancel plus a field change, two calls is the compact
answer. For a **mid-pipeline move**, the typed transition carries both in one
atomic plan (`typed-mutations.md`):

```bash
cat > intent.json <<'EOF'
{ "contractVersion": 1, "kind": "mutation-intent", "requestId": "tr-1",
  "target": { "operonId": "abc1234",
              "locator": { "representation": "inline", "filePath": "<path>.md", "lineNumber": 28 } },
  "spec": { "operation": "transition", "targetStatusId": "st_...",
            "expectedStatusId": "st_...",
            "changes": [ { "field": "priority", "valueType": "text", "value": "pr_s" } ] } }
EOF
operon task transition --input intent.json --json   # preview-only
operon plan apply <planRef> --json                  # apply promptly, plans expire
```

One-call wrapper: `$OP/op-do.sh transition --id abc1234 --to "<Pipeline.Status>" priority::"S"`.

## 12. Complete a task

```bash
operon task complete --id "$ID"
```

If the CLI answers no-change, the task was already finished. That is success.

## 13. Start and stop the timer

```bash
# On a task (locator from op-id.sh --one-row or task get)
echo '{"contractVersion":1,"kind":"mutation-intent","requestId":"tm1","target":{"operonId":"'"$ID"'","locator":{"representation":"inline","filePath":"<path>.md","lineNumber":28}},"spec":{"operation":"start"}}' \
  | operon timer start --input - --json
operon plan apply <planRef> --json

# Unassigned (no target at all)
echo '{"contractVersion":1,"kind":"mutation-intent","requestId":"tm2","spec":{"operation":"stop"}}' \
  | operon timer stop --input - --json
operon plan apply <planRef> --json
```

One-call wrapper: `$OP/op-do.sh timer-start --find "draft"` / `timer-stop`.

## 14. Move a scheduled date on a recurring task

```bash
operon task update --id "$ID" --scope this-task dateScheduled::"2026-08-03"
operon task update --id "$ID" --scope this-and-following dateScheduled::"2026-08-03"
```

## 15. Stop a recurrence

```bash
operon task update --id "$ID" --scope this-and-following --clear "repeat"
```

## 16. Swap a reminder

```bash
operon reminder replace --id "$ID" --current "dateDue.30m" reminderRules::"dateDue.1h"
```

## 17. Log a work session you forgot to track

```bash
operon timer session add --id "$ID" --start "2026-07-27T09:00:00" --end "2026-07-27T10:30:00"
```

## 18. Fix a mistyped session

```bash
operon timer session update --id "$ID" --session "1" --start "2026-07-27T09:15:00" --end "2026-07-27T10:30:00"
```

Session 1 is the oldest. Removing one is destructive: preview and ask first.

## 19. Move an inline task to another file

```bash
echo '{"contractVersion":1,"requestId":"pl-1","kind":"context","consistency":"live-verified","purpose":"mutation-readiness","projection":"placement-candidates","placement":{"mode":"lines","filePath":"<path>.md"},"limit":20}' \
  | operon context --input - --json | jq -c '.result.placement.lines[] | {line: (.locator.lineNumber + 1), label: .contextLabel}'

operon task relocate --id "$ID" --target-file "<path>.md" --line "42"
```

Remember the +1: candidate locators are zero-based, `--line` is one-based
(SKILL.md §9.1).

## 20. Turn an inline task into its own note

```bash
operon task convert --id "$ID" --to "file" \
  --template "<visible template name>" --target-file "<path>.md"
```

The reverse direction (file to inline) is destructive and needs an explicit
user CONVERT.

## 21. Delete a task safely

```bash
operon task delete --id "$ID" --preview-only
operon plan show <planRef>
# report to the user; the destructive plan expires in ~60 s, so hand them the
# interactive command to run themselves: operon task delete --id "$ID"
```

## 22. What is due this month

```bash
$OP/op-q.sh --open --due-from 2026-08-01 --due-to 2026-08-31 --limit 50
```

## 23. What is in progress right now

```bash
$OP/op-q.sh --status "<Pipeline.Status>" --status "<Pipeline.Status>" --limit 50
```

## 24. Everything under one project

```bash
ROOT=$($OP/op-id.sh "Plugin Dev - Operon" --one)
$OP/op-q.sh --parent "$ROOT" --open                  # direct children
$OP/op-id.sh "" --project-tree "$ROOT" --limit 50    # whole subtree, ranked
```

## 25. Overdue sweep

```bash
$OP/op-id.sh "" --scope overdue --limit 25
```

## 26. Full picture of one task before deciding

```bash
operon task get --id "$ID"
echo "{\"contractVersion\":1,\"requestId\":\"rel-1\",\"kind\":\"relationship\",\"consistency\":\"live-verified\",\"selector\":{\"kind\":\"operon-id\",\"operonId\":\"$ID\"},\"kinds\":[\"parent\",\"child\",\"blocking\",\"blocked-by\"],\"depth\":1,\"limit\":50}" \
  | operon relationships --input -
```

Both are reads, so run them in one Bash block. Remember `task get` is a
partial projection (`commands.md` §1).

## 27. Bulk update 2-64 tasks, one atomic plan

```bash
operon task update --input-format compact-lines --input - --json <<'EOF'
--id "abc1234" contexts::"Operon; Q3"
--id "def5678" contexts::"Operon; Q3"
--id "ghi9012" contexts::"Operon; Q3" --clear "dateScheduled"
EOF
operon plan apply <planRef> --json
```

One plan, all-or-nothing: a mid-batch failure cannot leave a half-updated set,
which is exactly what a shell loop of single updates risks. Never loop
`task update` when the batch route fits. One-call wrapper:
`$OP/op-do.sh batch-update -`.

## 28. Recover after an interrupted apply

```bash
operon plan recover <planRef>
```

Nothing else. See `plans-and-limits.md` §6.

## 29. Check what changed after a mutation

The apply envelope already reports the result; trust it. When you genuinely
need to re-read, one call:

```bash
operon task get --id "$ID"       # partial projection; hidden fields need the typed get
```

Do not re-run the mutation to "verify" it.
