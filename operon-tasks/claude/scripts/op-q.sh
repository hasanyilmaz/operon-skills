#!/usr/bin/env bash
# op-q.sh - bounded task query without hand-writing the request JSON.
#
# Builds a valid task-query request, sends it through `operon query --input -`,
# and prints one tab-separated row per task:
#     operonId  Pipeline.Status  priority  due  parentId  description
#
# Pipeline, status, and priority labels are translated to stable IDs using the
# cached catalog (op-catalog.sh), so no extra Runtime call is needed for that.
#
# Usage:
#   op-q.sh --open --limit 20
#   op-q.sh --text "release notes"
#   op-q.sh --status "<Pipeline.Status>" --status "<Pipeline.Status>"
#   op-q.sh --pipeline <PipelineName> --open --due-to 2026-08-05
#   op-q.sh --parent b5jdsct --open
#   op-q.sh --file "<vault-relative path>.md"
#
# Pipeline and status names differ per vault. Get the live ones from
# op-catalog.sh --statuses; never copy them out of this comment.
#   op-q.sh --open --json | jq '.result.tasks[0]'
#
# Options:
#   --text S           substring match on description
#   --open|--done|--cancelled   checkbox state (repeatable, default: no filter)
#   --pipeline NAME    repeatable, exact pipeline name
#   --status P.S       repeatable, exact Pipeline.Status
#   --priority LABEL   repeatable, exact priority label (S A B C D E F)
#   --due-from DATE    YYYY-MM-DD
#   --due-to DATE      YYYY-MM-DD
#   --parent ID        direct children of one operonId
#   --file PATH        vault-relative source file
#   --limit N          1..250, default 25
#   --cursor S         continue a previous page
#   --json             print the raw CLI envelope instead of TSV
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAT_JSON="$("${HERE}/op-catalog.sh" --raw)"
CURSOR_FILE="$(dirname "$CAT_JSON")/last-cursor.txt"

TEXT="" ; DUE_FROM="" ; DUE_TO="" ; PARENT="" ; FILEPATH="" ; CURSOR=""
LIMIT=25 ; RAW=0
CHECKBOX=() ; PIPELINES=() ; STATUSES=() ; PRIORITIES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --text) shift; TEXT="${1:-}" ;;
    --open) CHECKBOX+=("open") ;;
    --done) CHECKBOX+=("done") ;;
    --cancelled) CHECKBOX+=("cancelled") ;;
    --pipeline) shift; PIPELINES+=("${1:-}") ;;
    --status) shift; STATUSES+=("${1:-}") ;;
    --priority) shift; PRIORITIES+=("${1:-}") ;;
    --due-from) shift; DUE_FROM="${1:-}" ;;
    --due-to) shift; DUE_TO="${1:-}" ;;
    --parent) shift; PARENT="${1:-}" ;;
    --file) shift; FILEPATH="${1:-}" ;;
    --limit) shift; LIMIT="${1:-25}" ;;
    --cursor) shift; CURSOR="${1:-}" ;;
    --json) RAW=1 ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "op-q.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$CURSOR" = "last" ]; then
  CURSOR="$(cat "$CURSOR_FILE" 2>/dev/null || true)"
  [ -n "$CURSOR" ] || { echo "op-q.sh: no stored cursor from a previous run" >&2; exit 2; }
fi

REQ="$(
  CB="$(IFS=$'\n'; echo "${CHECKBOX[*]:-}")" \
  PL="$(IFS=$'\n'; echo "${PIPELINES[*]:-}")" \
  ST="$(IFS=$'\n'; echo "${STATUSES[*]:-}")" \
  PR="$(IFS=$'\n'; echo "${PRIORITIES[*]:-}")" \
  TEXT="$TEXT" DUE_FROM="$DUE_FROM" DUE_TO="$DUE_TO" PARENT="$PARENT" \
  FILEPATH="$FILEPATH" LIMIT="$LIMIT" CURSOR="$CURSOR" CAT="$CAT_JSON" \
  python3 - <<'PY'
import json, os, sys, time

def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(2)


def lines(name):
    return [v for v in os.environ.get(name, "").split("\n") if v.strip()]

cat = json.load(open(os.environ["CAT"]))["result"]["taxonomy"]
pipe_by_name = {p["name"]: p for p in cat["pipelines"]}
prio_by_label = {p["label"]: p["id"] for p in cat["priorities"]}

filters = {}

cb = lines("CB")
if cb:
    filters["checkbox"] = sorted(set(cb))

pipeline_ids = []
for name in lines("PL"):
    p = pipe_by_name.get(name)
    if not p:
        die("op-q.sh: unknown pipeline %r. Run op-catalog.sh for exact names." % name)
    pipeline_ids.append(p["id"])
if pipeline_ids:
    filters["pipelineIds"] = sorted(set(pipeline_ids))

status_ids = []
for token in lines("ST"):
    if "." not in token:
        die("op-q.sh: --status must be Pipeline.Status, got %r" % token)
    pname, sname = token.split(".", 1)
    p = pipe_by_name.get(pname)
    if not p:
        die("op-q.sh: unknown pipeline %r in %r" % (pname, token))
    match = [s["id"] for s in p["statuses"] if s["label"] == sname]
    if not match:
        die("op-q.sh: unknown status %r. Run op-catalog.sh for exact values." % token)
    status_ids.append(match[0])
if status_ids:
    filters["statusIds"] = sorted(set(status_ids))

prio_ids = []
for label in lines("PR"):
    pid = prio_by_label.get(label)
    if not pid:
        die("op-q.sh: unknown priority %r. Valid: %s" % (label, " ".join(prio_by_label)))
    prio_ids.append(pid)
if prio_ids:
    filters["priorityIds"] = sorted(set(prio_ids))

if os.environ.get("TEXT"):
    filters["text"] = os.environ["TEXT"]
if os.environ.get("PARENT"):
    filters["parentOperonId"] = os.environ["PARENT"]
if os.environ.get("FILEPATH"):
    filters["filePath"] = os.environ["FILEPATH"]

due = {}
if os.environ.get("DUE_FROM"):
    due["from"] = os.environ["DUE_FROM"]
if os.environ.get("DUE_TO"):
    due["to"] = os.environ["DUE_TO"]
if due:
    filters["due"] = due

req = {
    "contractVersion": 1,
    "requestId": "opq-%d" % int(time.time() * 1000),
    "kind": "task-query",
    "consistency": "live-verified",
    "limit": int(os.environ.get("LIMIT") or 25),
}
if filters:
    req["filters"] = filters
if os.environ.get("CURSOR"):
    req["cursor"] = os.environ["CURSOR"]

print(json.dumps(req))
PY
)"

OUT="$(printf '%s' "$REQ" | operon query --input - --json)" || true

if printf '%s' "$OUT" | grep -q '"code":"stale-cursor"'; then
  echo "op-q.sh: the stored cursor belongs to a different query. A cursor is bound" >&2
  echo "op-q.sh: to its exact filter set, so page with the SAME flags, or drop --cursor." >&2
  exit 4
fi
if ! printf '%s' "$OUT" | grep -q '"ok":true'; then
  echo "op-q.sh: query failed" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

if [ "$RAW" -eq 1 ]; then
  printf '%s\n' "$OUT"
  exit 0
fi

TMP="$(mktemp -t opq)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$OUT" >"$TMP"

python3 - "$TMP" "$CURSOR_FILE" <<'PY'
import json, os, sys

doc = json.load(open(sys.argv[1]))
if not doc.get("ok"):
    err = doc.get("error") or doc.get("result", {}).get("error") or doc
    print("op-q.sh: %s" % json.dumps(err)[:600], file=sys.stderr)
    raise SystemExit(4)

res = doc["result"]
tasks = res.get("tasks", [])
for t in tasks:
    wf = t.get("workflow", {})
    status = "%s.%s" % (wf.get("pipeline", {}).get("label", "?"),
                        wf.get("status", {}).get("label", "?"))
    print("\t".join([
        t.get("identity", {}).get("operonId", "?"),
        status,
        (t.get("priority") or {}).get("label", "-"),
        (t.get("dates") or {}).get("due", "-"),
        (t.get("relationships") or {}).get("parentOperonId") or "-",
        (t.get("description") or "").replace("\t", " "),
    ]))

page = res.get("page") or {}
summary = "# %s of %s matching tasks" % (
    page.get("returnedCount", len(tasks)), page.get("actualCount", "?"))
cursor = page.get("nextCursor")
if cursor:
    with open(sys.argv[2], "w") as fh:
        fh.write(cursor)
    summary += ", truncated. Next page: op-q.sh <same flags> --cursor last"
print(summary, file=sys.stderr)
PY
