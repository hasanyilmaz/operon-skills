#!/usr/bin/env bash
# op-do.sh - one-call mutation dispatcher for daily Operon task work.
#
# One dictated intent, one call: prose-or-id target resolution, intent building,
# preview, triage and apply all happen inside this single process, so plan TTLs
# (5 min routine) never race and writes are naturally serialized.
#
# Usage:
#   op-do.sh <verb> (--id <ID> | --find "prose") [verb args...] [--preview-only] [--json]
#
# Verbs:
#   update            key::"v" ... [--clear "key"] [--scope this-task|this-and-following]
#   complete | reopen | cancel | pin | unpin
#   reminder-add      reminderRules::"anchor.offset" | reminderDatetimes::"YYYY-MM-DDTHH:mm:ss"
#   reminder-replace  --current "old" reminderRules::"new"
#   reminder-remove   reminderRules::"rule" | reminderDatetimes::"dt"
#   session-add       --start "YYYY-MM-DDTHH:mm:ss" --end "YYYY-MM-DDTHH:mm:ss"
#   session-update    --session N --start "..." --end "..."
#   transition        --to "Pipeline.Status" [--expect "Pipeline.Status"] [key::"v" ... --clear "key"]
#                     field changes ride in the SAME atomic plan as the status move
#   timer-start       [target optional: omit --id/--find for an unassigned timer]
#   timer-stop        [--expect-active "datetime" seals against a raced timer]
#   batch-update      stdin: 2-64 lines, each: --id "abc1234" key::"v" ... [--clear "key"]
#   batch-create      stdin: 1-64 lines, each: ["inline "|"file "]"Description" key::"v" ...
#
# Icons: write taskIcon::"?english concept words" anywhere a taskIcon value is
# allowed and op-icon.sh resolves it offline inside this same process (no extra
# call, ~15 ms). The corpus is English, so translate the dictation into 2-4
# concept words yourself, never build per-language tables. No match means the
# icon is dropped with a warning, never a failed write.
#
# Refused verbs (destructive, confirmation-gated, 60s plan TTL): delete, convert,
# session-remove. This script prints the manual command and exits 2.
#
# Target resolution:
#   --id     used verbatim, no lookup
#   --find   op-id.sh --one-row semantics: open-only default (--any widens),
#            exactly-one required, NFC exact-description tiebreak. Ambiguity is
#            exit 4 with a candidate TSV on stderr and ZERO mutations.
#   --scope  finder scope (normal|overdue|happens-today|recent) for --find;
#            for the update verb it is the recurrence scope instead
#   --project-tree ID   narrow --find to one project subtree
#
# Exit codes: 0 ok/no-change, 2 usage/refused, 3 runtime unavailable,
#             4 fail-closed (ambiguous target, plan needs review), 5 runtime
#             failure or APPLY UNCERTAIN (never retry; plan recover), 70 CLI bug.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERB="${1:-}"
if [ "$VERB" = "-h" ] || [ "$VERB" = "--help" ]; then
  sed -n '2,46p' "$0"; exit 0
fi
if [ -z "$VERB" ]; then
  sed -n '2,46p' "$0"; exit 2
fi
shift

case "$VERB" in
  delete|convert|session-remove)
    echo "op-do.sh: '$VERB' is deliberately not automated (destructive, typed confirmation gate)." >&2
    echo "Preview it, show the user the plan, then hand them the command for THEIR terminal:" >&2
    echo "  operon task delete --id <ID>                          # prompts for literal DELETE" >&2
    echo "  operon task convert --id <ID> --to inline ...         # prompts for literal CONVERT" >&2
    echo "  operon timer session remove --id <ID> --session N     # prompts for literal REMOVE" >&2
    echo "Destructive plans expire in 60 seconds. Never derive the confirm token." >&2
    exit 2 ;;
  update|complete|reopen|cancel|pin|unpin|reminder-add|reminder-replace|reminder-remove|session-add|session-update|transition|timer-start|timer-stop|batch-update|batch-create) ;;
  *) echo "op-do.sh: unknown verb '$VERB'. Run op-do.sh --help." >&2; exit 2 ;;
esac

ID="" ; FIND="" ; ANY=0 ; FSCOPE="" ; PROJ_TREE="" ; PREVIEW_ONLY=0 ; RAW=0
TO="" ; EXPECT="" ; CURRENT="" ; SESSION="" ; TSTART="" ; TEND="" ; EXPECT_ACTIVE=""
USCOPE=""
VERB_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --id) shift; ID="${1:-}" ;;
    --find) shift; FIND="${1:-}" ;;
    --any) ANY=1 ;;
    --scope) shift
      if [ "$VERB" = "update" ]; then USCOPE="${1:-}"; else FSCOPE="${1:-}"; fi ;;
    --project-tree) shift; PROJ_TREE="${1:-}" ;;
    --preview-only) PREVIEW_ONLY=1 ;;
    --json) RAW=1 ;;
    --to) shift; TO="${1:-}" ;;
    --expect) shift; EXPECT="${1:-}" ;;
    --current) shift; CURRENT="${1:-}" ;;
    --session) shift; SESSION="${1:-}" ;;
    --start) shift; TSTART="${1:-}" ;;
    --end) shift; TEND="${1:-}" ;;
    --expect-active) shift; EXPECT_ACTIVE="${1:-}" ;;
    --clear) shift; VERB_ARGS+=("--clear" "${1:-}") ;;
    -h|--help) sed -n '2,46p' "$0"; exit 0 ;;
    -) ;;                                    # decorative stdin marker on batch verbs
    *::*) VERB_ARGS+=("$1") ;;
    *) echo "op-do.sh: unexpected argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

# ---------- icon resolution (offline, no extra tool call) ----------
# taskIcon::"?english concept words" is resolved against the plugin's lucide tag
# corpus by op-icon.sh, in this same process. Unresolvable queries are dropped
# with a warning: an icon is never worth failing a write over.
if [ ${#VERB_ARGS[@]} -gt 0 ]; then
  for i in "${!VERB_ARGS[@]}"; do
    case "${VERB_ARGS[$i]}" in
      taskIcon::\?*)
        IQ="${VERB_ARGS[$i]#taskIcon::?}"
        IID="$("${HERE}/op-icon.sh" --first "$IQ" 2>/dev/null || echo -)"
        if [ -z "$IID" ] || [ "$IID" = "-" ]; then
          echo "op-do.sh: no icon matched '$IQ', dropping taskIcon" >&2
          unset 'VERB_ARGS[i]'
        else
          VERB_ARGS[$i]="taskIcon::$IID"
          echo "# icon: $IQ -> $IID" >&2
        fi ;;
    esac
  done
  VERB_ARGS=("${VERB_ARGS[@]+"${VERB_ARGS[@]}"}")   # reindex after a possible unset
fi

# ---------- per-verb argument validation (fail before any Runtime call) ----------
case "$VERB" in
  update)
    [ ${#VERB_ARGS[@]} -gt 0 ] || { echo "op-do.sh: update needs at least one key::\"v\" or --clear" >&2; exit 2; } ;;
  reminder-add|reminder-remove)
    [ ${#VERB_ARGS[@]} -eq 1 ] || { echo "op-do.sh: $VERB takes exactly one reminder item" >&2; exit 2; } ;;
  reminder-replace)
    [ -n "$CURRENT" ] || { echo "op-do.sh: reminder-replace needs --current" >&2; exit 2; }
    [ ${#VERB_ARGS[@]} -eq 1 ] || { echo "op-do.sh: reminder-replace takes exactly one new item" >&2; exit 2; } ;;
  session-add)
    [ -n "$TSTART" ] && [ -n "$TEND" ] || { echo "op-do.sh: session-add needs --start and --end" >&2; exit 2; } ;;
  session-update)
    [ -n "$SESSION" ] && [ -n "$TSTART" ] && [ -n "$TEND" ] || { echo "op-do.sh: session-update needs --session, --start and --end" >&2; exit 2; } ;;
  transition)
    [ -n "$TO" ] || { echo "op-do.sh: transition needs --to \"Pipeline.Status\"" >&2; exit 2; } ;;
esac

# ---------- target resolution ----------
NEED_LOCATOR=0
case "$VERB" in transition|timer-start|timer-stop) NEED_LOCATOR=1 ;; esac

CUR_PS="" ; CUR_STATUS_ID="" ; REPR="" ; FPATH="" ; LNUM="" ; TDESC=""

if [ -n "$FIND" ] && [ -n "$ID" ]; then
  echo "op-do.sh: pass --id or --find, not both" >&2; exit 2
fi

if [ -n "$FIND" ]; then
  FARGS=("$FIND" --one-row)
  [ "$ANY" -eq 1 ] && FARGS+=(--any)
  [ -n "$FSCOPE" ] && FARGS+=(--scope "$FSCOPE")
  [ -n "$PROJ_TREE" ] && FARGS+=(--project-tree "$PROJ_TREE")
  ROW="$("${HERE}/op-id.sh" "${FARGS[@]}")" || exit 4   # candidates already on stderr
  IFS=$'\t' read -r ID CUR_PS _PRIO REPR FPATH LNUM TDESC <<<"$ROW"
  echo "# target: $ID  $CUR_PS  $TDESC" >&2
elif [ -n "$ID" ] && [ "$NEED_LOCATOR" -eq 1 ]; then
  GOT="$(operon task get --id "$ID" --json | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("ok"):
    print("op-do.sh: task get failed for that --id", file=sys.stderr)
    raise SystemExit(4)
t = d["result"]["task"]
loc = t.get("locator") or {}
line = loc.get("lineNumber")
print("%s\t%s\t%s\t%s" % (
    loc.get("representation", "?"), loc.get("filePath", "?"),
    "-" if line is None else line,
    (t.get("workflow", {}).get("status") or {}).get("id", "")))
')" || exit 4
  IFS=$'\t' read -r REPR FPATH LNUM CUR_STATUS_ID <<<"$GOT"
fi

case "$VERB" in
  timer-start|timer-stop) ;;                            # target optional (unassigned timer)
  batch-update|batch-create) ;;                         # targets live inside the stdin lines
  *) [ -n "$ID" ] || { echo "op-do.sh: $VERB needs --id or --find" >&2; exit 2; } ;;
esac

# ---------- shared preview triage + apply ----------
TMPDIR_DO="$(mktemp -d -t opdo)"
trap 'rm -rf "$TMPDIR_DO"' EXIT

triage_and_apply() { # $1 = preview json file, $2 = label for created-effects printing
  local ptmp="$1" what="${2:-}"
  local ref risk confirm warn_count
  read -r ref risk confirm warn_count <<<"$(python3 - "$ptmp" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
if not doc.get("ok"):
    print("op-do.sh: %s" % json.dumps(doc.get("error") or doc)[:600], file=sys.stderr)
    raise SystemExit(5)
# The opaque plan reference lives on the CLI envelope, not inside result.plan.
ref = (doc.get("client") or {}).get("planRef", "")
plan = doc["result"].get("plan") or {}
risk = plan.get("riskLevel", "unknown")
confirm = "yes" if (plan.get("requiresConfirmation") or plan.get("requiredAcknowledgements")) else "no"
warnings = (doc.get("warnings") or []) + (plan.get("warnings") or [])
# Projected timestamps are informational and present on every preview.
blocking = [w for w in warnings
            if (w.get("code") if isinstance(w, dict) else str(w)) != "apply-time-values-projected"]
print("%s %s %s %d" % (ref, risk, confirm, len(blocking)))
PY
)"
  [ -n "$ref" ] || { echo "op-do.sh: no planRef in preview" >&2; exit 5; }

  if [ "$PREVIEW_ONLY" -eq 1 ]; then
    if [ "$RAW" -eq 1 ]; then cat "$ptmp"; else operon plan show "$ref"; fi
    echo "# preview only, not applied. planRef=$ref (expires in ~5 min)" >&2
    return 0
  fi

  if [ "$confirm" = "yes" ] || [ "$risk" = "destructive" ] || [ "$warn_count" -gt 0 ]; then
    echo "op-do.sh: plan needs review (risk=$risk confirm=$confirm warnings=$warn_count)." >&2
    echo "op-do.sh: inspect with 'operon plan show $ref' and surface it to the user." >&2
    exit 4
  fi

  local atmp="$TMPDIR_DO/apply.json"
  if ! operon plan apply "$ref" --json >"$atmp" 2>&1; then
    cat "$atmp" >&2
    echo "op-do.sh: APPLY UNCERTAIN. Do not retry. Run exactly: operon plan recover $ref" >&2
    exit 5
  fi

  if [ "$RAW" -eq 1 ]; then cat "$atmp"; return 0; fi

  python3 - "$ptmp" "$atmp" "$ref" "$what" <<'PY'
import json, sys
preview = json.load(open(sys.argv[1]))
apply_doc = json.load(open(sys.argv[2]))
plan_ref, what = sys.argv[3], sys.argv[4]
res = apply_doc.get("result", {})
status = res.get("status", "?")
postflight = (res.get("postflight") or {}).get("status", "?")
if not apply_doc.get("ok") or status != "applied":
    print("op-do.sh: apply status=%s" % status, file=sys.stderr)
    if res.get("mutationMayHaveApplied") and not res.get("retryAllowed"):
        print("op-do.sh: OUTCOME UNCERTAIN. Run: operon plan recover %s" % plan_ref, file=sys.stderr)
    raise SystemExit(5)
if what == "create":
    # Created ids live in the preview plan, the outcome lives in the apply receipt.
    for c in (preview["result"].get("plan") or {}).get("createEffects", []):
        print("%s\t%s" % (c.get("operonId", "?"), (c.get("locator") or {}).get("filePath", "?")))
print("# applied, postflight %s" % postflight, file=sys.stderr)
PY
}

run_preview() { # $1 = output file; rest = command
  local out="$1"; shift
  if ! "$@" >"$out" 2>"$TMPDIR_DO/preview.err"; then
    cat "$TMPDIR_DO/preview.err" >&2
    [ -s "$out" ] && cat "$out" >&2
    echo "op-do.sh: preview failed" >&2
    exit 5
  fi
}

# ---------- typed routes ----------
if [ "$VERB" = "transition" ]; then
  CAT_JSON="$("${HERE}/op-catalog.sh" --raw)"
  ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${VERB_ARGS[@]+"${VERB_ARGS[@]}"}")"
  INTENT="$TMPDIR_DO/intent.json"
  TO="$TO" EXPECT="$EXPECT" CUR_PS="$CUR_PS" CUR_STATUS_ID="$CUR_STATUS_ID" \
  ID="$ID" REPR="$REPR" FPATH="$FPATH" LNUM="$LNUM" CAT="$CAT_JSON" ARGS="$ARGS_JSON" \
  python3 - "$INTENT" <<'PY'
import json, os, sys, time


def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(2)


def split_list(raw):
    out, buf, i = [], "", 0
    while i < len(raw):
        ch = raw[i]
        if ch == "\\" and i + 1 < len(raw) and raw[i + 1] == ";":
            buf += ";"; i += 2; continue
        if ch == ";":
            out.append(buf.strip()); buf = ""; i += 1; continue
        buf += ch; i += 1
    out.append(buf.strip())
    items = [v for v in out if v]
    if len(items) != len(set(items)):
        die("op-do.sh: duplicate list item in %r" % raw)
    return items


cat = json.load(open(os.environ["CAT"]))["result"]
tax = cat["taxonomy"]
pipes = {p["name"]: p for p in tax["pipelines"]}
prio_by_label = {p["label"]: p["id"] for p in tax["priorities"]}
field_info = {f["canonicalKey"]: f for f in cat["fields"]}


def status_id(token, what):
    if "." not in token:
        die("op-do.sh: %s must be Pipeline.Status, got %r" % (what, token))
    pname, sname = token.split(".", 1)
    p = pipes.get(pname) or die("op-do.sh: unknown pipeline %r. Run op-catalog.sh --statuses." % pname)
    match = [s["id"] for s in p["statuses"] if s["label"] == sname]
    return match[0] if match else die("op-do.sh: unknown status %r. Run op-catalog.sh --statuses." % token)


target_status = status_id(os.environ["TO"], "--to")
expected = ""
if os.environ.get("EXPECT"):
    expected = status_id(os.environ["EXPECT"], "--expect")
elif os.environ.get("CUR_STATUS_ID"):
    expected = os.environ["CUR_STATUS_ID"]
elif os.environ.get("CUR_PS"):
    expected = status_id(os.environ["CUR_PS"], "current status")

changes = []
tokens = json.loads(os.environ["ARGS"])
i = 0
while i < len(tokens):
    tok = tokens[i]
    if tok == "--clear":
        i += 1
        if i >= len(tokens):
            die("op-do.sh: --clear needs a key")
        field = tokens[i]
        info = field_info.get(field) or die("op-do.sh: unknown field %r" % field)
        if info.get("mutationClass") != "general-update":
            die("op-do.sh: %r is not a general-update field; it cannot ride a transition" % field)
        if field == "description":
            die("op-do.sh: description cannot be cleared")
        changes.append({"operation": "clear", "field": field, "valueType": info["valueType"]})
        i += 1
        continue
    if "::" not in tok:
        die("op-do.sh: expected key::\"value\", got %r" % tok)
    field, value = tok.split("::", 1)
    info = field_info.get(field) or die("op-do.sh: unknown field %r" % field)
    if info.get("mutationClass") != "general-update":
        die("op-do.sh: %r is not a general-update field; it cannot ride a transition" % field)
    vt = info["valueType"]
    if field == "priority":
        pid = prio_by_label.get(value) or die(
            "op-do.sh: unknown priority %r. Valid: %s" % (value, " ".join(prio_by_label)))
        coerced = pid
    elif vt == "number":
        try:
            coerced = int(value)
        except ValueError:
            try:
                coerced = float(value)
            except ValueError:
                die("op-do.sh: %s expects a number, got %r" % (field, value))
    elif vt == "list":
        coerced = split_list(value)
    else:
        coerced = value
    changes.append({"field": field, "valueType": vt, "value": coerced})
    i += 1

seen = [c["field"] for c in changes]
if len(seen) != len(set(seen)):
    die("op-do.sh: each field may appear once per transition")

locator = {"representation": os.environ["REPR"], "filePath": os.environ["FPATH"]}
if os.environ["REPR"] == "inline":
    lnum = os.environ.get("LNUM", "-")
    if lnum in ("", "-"):
        die("op-do.sh: inline task locator has no line number")
    locator["lineNumber"] = int(lnum)

spec = {"operation": "transition", "targetStatusId": target_status}
if expected:
    spec["expectedStatusId"] = expected
if changes:
    spec["changes"] = changes

intent = {
    "contractVersion": 1,
    "kind": "mutation-intent",
    "requestId": "opdo-%d" % int(time.time() * 1000),
    "target": {"operonId": os.environ["ID"], "locator": locator},
    "spec": spec,
}
with open(sys.argv[1], "w") as fh:
    json.dump(intent, fh)
PY
  PREV="$TMPDIR_DO/preview.json"
  run_preview "$PREV" operon task transition --input "$INTENT" --json
  triage_and_apply "$PREV" ""
  exit 0
fi

if [ "$VERB" = "timer-start" ] || [ "$VERB" = "timer-stop" ]; then
  OPERATION="${VERB#timer-}"
  INTENT="$TMPDIR_DO/intent.json"
  OPERATION="$OPERATION" ID="$ID" REPR="$REPR" FPATH="$FPATH" LNUM="$LNUM" \
  EXPECT_ACTIVE="$EXPECT_ACTIVE" \
  python3 - "$INTENT" <<'PY'
import json, os, sys, time

spec = {"operation": os.environ["OPERATION"]}
if os.environ.get("EXPECT_ACTIVE"):
    spec["expectedActiveStart"] = os.environ["EXPECT_ACTIVE"]

intent = {
    "contractVersion": 1,
    "kind": "mutation-intent",
    "requestId": "opdo-%d" % int(time.time() * 1000),
    "spec": spec,
}
if os.environ.get("ID"):
    locator = {"representation": os.environ["REPR"], "filePath": os.environ["FPATH"]}
    if os.environ["REPR"] == "inline":
        lnum = os.environ.get("LNUM", "-")
        if lnum in ("", "-"):
            print("op-do.sh: inline task locator has no line number", file=sys.stderr)
            raise SystemExit(2)
        locator["lineNumber"] = int(lnum)
    intent["target"] = {"operonId": os.environ["ID"], "locator": locator}
with open(sys.argv[1], "w") as fh:
    json.dump(intent, fh)
PY
  PREV="$TMPDIR_DO/preview.json"
  run_preview "$PREV" operon timer "$OPERATION" --input "$INTENT" --json
  triage_and_apply "$PREV" ""
  exit 0
fi

if [ "$VERB" = "batch-update" ] || [ "$VERB" = "batch-create" ]; then
  LINES="$TMPDIR_DO/lines.txt"
  cat >"$LINES"
  if grep -q 'taskIcon::"?' "$LINES"; then
    "${HERE}/op-icon.sh" --rewrite <"$LINES" >"$TMPDIR_DO/lines.icon" || true
    [ -s "$TMPDIR_DO/lines.icon" ] && mv "$TMPDIR_DO/lines.icon" "$LINES"
  fi
  N="$(grep -c . "$LINES" || true)"
  if [ "$VERB" = "batch-update" ] && [ "$N" -lt 2 ]; then
    echo "op-do.sh: batch-update needs 2-64 lines (got $N); use 'update' for one task" >&2; exit 2
  fi
  if [ "$N" -lt 1 ] || [ "$N" -gt 64 ]; then
    echo "op-do.sh: $VERB accepts 1-64 lines (got $N)" >&2; exit 2
  fi
  PREV="$TMPDIR_DO/preview.json"
  if [ "$VERB" = "batch-update" ]; then
    run_preview "$PREV" operon task update --input-format compact-lines --input "$LINES" --json
    triage_and_apply "$PREV" ""
  else
    run_preview "$PREV" operon task create --input-format compact-lines --input "$LINES" --json
    triage_and_apply "$PREV" "create"
  fi
  exit 0
fi

# ---------- compact passthrough (the CLI applies warning-free plans itself) ----------
CMD=()
case "$VERB" in
  update)
    CMD=(operon task update --id "$ID")
    [ -n "$USCOPE" ] && CMD+=(--scope "$USCOPE")
    CMD+=("${VERB_ARGS[@]+"${VERB_ARGS[@]}"}") ;;
  complete|reopen|cancel|pin|unpin)
    CMD=(operon task "$VERB" --id "$ID") ;;
  reminder-add)
    CMD=(operon reminder add --id "$ID" "${VERB_ARGS[@]}") ;;
  reminder-replace)
    CMD=(operon reminder replace --id "$ID" --current "$CURRENT" "${VERB_ARGS[@]}") ;;
  reminder-remove)
    CMD=(operon reminder remove --id "$ID" "${VERB_ARGS[@]}") ;;
  session-add)
    CMD=(operon timer session add --id "$ID" --start "$TSTART" --end "$TEND") ;;
  session-update)
    CMD=(operon timer session update --id "$ID" --session "$SESSION" --start "$TSTART" --end "$TEND") ;;
esac
[ "$PREVIEW_ONLY" -eq 1 ] && CMD+=(--preview-only)
[ "$RAW" -eq 1 ] && CMD+=(--json)

"${CMD[@]}"
