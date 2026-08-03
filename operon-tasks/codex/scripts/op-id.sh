#!/usr/bin/env bash
# op-id.sh - turn prose into an exact operonId using the native Operon Task Finder.
#
# Always resolve a target with this before running a mutation. Mutation commands
# take --id; --description needs a unique, case-sensitive, exact match and fails
# closed, which costs a wasted round-trip.
#
# Output (TSV): operonId  Pipeline.Status  priority  representation  filePath  lineNumber  description
# lineNumber is ZERO-based, exactly as mutation locators expect it: pass it
# through verbatim. Only task relocate/convert --line use one-based numbers.
#
# Searches OPEN tasks by default. A vault often holds finished tasks that quote a
# live task's description verbatim (archive, journal or audit entries that are
# themselves Operon tasks), so an unfiltered search matches those copies as well
# as the real task and --one fails with two candidates. Such copies are `done`,
# so the open-only default removes them. Pass --any to search every checkbox
# state, which is what reopening a finished task needs.
#
# Usage:
#   op-id.sh "release notes"
#   op-id.sh "release notes" --one          # print the id alone, or fail with candidates
#   op-id.sh "release notes" --one-row      # print the full TSV row of the one match
#   op-id.sh "review" --limit 5
#   op-id.sh "bug" --scope overdue
#   op-id.sh "phase" --project-tree b5jdsct
#   op-id.sh "shipped thing" --any --one    # include done/cancelled
#
# Options:
#   --one              require exactly one match; print the bare id, else exit 4
#   --one-row          require exactly one match; print its full TSV row, else exit 4
#   --any              drop the open-only default; search every checkbox state
#   --open|--done|--cancelled   explicit checkbox filter (repeatable, overrides the default)
#   --priority LABEL   repeatable exact priority label
#   --inline|--file    restrict representation
#   --scope S          normal (default) | overdue | happens-today | recent
#   --project-tree ID  search inside one project subtree
#   --project-direct ID  search only direct children of one project
#   --limit N          1..250, default 10
#   --json             raw CLI envelope
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAT_JSON="$("${HERE}/op-catalog.sh" --raw)"

TEXT="" ; SCOPE="" ; PROJ_MODE="" ; PROJ_ROOT="" ; LIMIT=10 ; ONE=0 ; RAW=0 ; ANY=0
CHECKBOX=() ; PRIORITIES=() ; REPS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --one) ONE=1 ;;
    --one-row) ONE=2 ;;
    --any) ANY=1 ;;
    --open) CHECKBOX+=("open") ;;
    --done) CHECKBOX+=("done") ;;
    --cancelled) CHECKBOX+=("cancelled") ;;
    --priority) shift; PRIORITIES+=("${1:-}") ;;
    --inline) REPS+=("inline") ;;
    --file) REPS+=("file") ;;
    --scope) shift; SCOPE="${1:-}" ;;
    --project-tree) shift; PROJ_MODE="tree"; PROJ_ROOT="${1:-}" ;;
    --project-direct) shift; PROJ_MODE="direct"; PROJ_ROOT="${1:-}" ;;
    --limit) shift; LIMIT="${1:-10}" ;;
    --json) RAW=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "op-id.sh: unknown option $1" >&2; exit 2 ;;
    *) TEXT="$1" ;;
  esac
  shift
done

if [ -z "$TEXT" ] && [ -z "$PROJ_MODE" ] && [ -z "$SCOPE" ]; then
  echo "op-id.sh: give search text, --scope, or a --project-* root" >&2
  exit 2
fi

if [ "$ANY" -eq 0 ] && [ ${#CHECKBOX[@]} -eq 0 ]; then
  CHECKBOX+=("open")
fi

REQ="$(
  CB="$(IFS=$'\n'; echo "${CHECKBOX[*]:-}")" \
  PR="$(IFS=$'\n'; echo "${PRIORITIES[*]:-}")" \
  RP="$(IFS=$'\n'; echo "${REPS[*]:-}")" \
  TEXT="$TEXT" SCOPE="$SCOPE" PROJ_MODE="$PROJ_MODE" PROJ_ROOT="$PROJ_ROOT" \
  LIMIT="$LIMIT" CAT="$CAT_JSON" \
  python3 - <<'PY'
import json, os, sys, time


def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(2)


def lines(name):
    return [v for v in os.environ.get(name, "").split("\n") if v.strip()]


cat = json.load(open(os.environ["CAT"]))["result"]["taxonomy"]
prio_by_label = {p["label"]: p["id"] for p in cat["priorities"]}

req = {
    "contractVersion": 1,
    "requestId": "opid-%d" % int(time.time() * 1000),
    "kind": "task-finder",
    "consistency": "live-verified",
    "limit": int(os.environ.get("LIMIT") or 10),
}

text = os.environ.get("TEXT", "")
if text:
    if len(text) < 2:
        die("op-id.sh: search text needs at least 2 characters")
    req["text"] = text

filters = {}
cb = lines("CB")
if cb:
    filters["checkbox"] = sorted(set(cb))
prio_ids = []
for label in lines("PR"):
    pid = prio_by_label.get(label)
    if not pid:
        die("op-id.sh: unknown priority %r. Valid: %s" % (label, " ".join(prio_by_label)))
    prio_ids.append(pid)
if prio_ids:
    filters["priorityIds"] = sorted(set(prio_ids))
if filters:
    req["filters"] = filters

reps = lines("RP")
if reps:
    req["representations"] = sorted(set(reps))

scope = os.environ.get("SCOPE")
if scope:
    if scope not in ("normal", "overdue", "happens-today", "recent"):
        die("op-id.sh: --scope must be normal, overdue, happens-today, or recent")
    req["scope"] = scope

mode = os.environ.get("PROJ_MODE")
if mode:
    project = {"mode": mode}
    root = os.environ.get("PROJ_ROOT")
    if root:
        project["rootOperonId"] = root
    req["project"] = project

print(json.dumps(req))
PY
)"

OUT="$(printf '%s' "$REQ" | operon finder --input - --json)" || {
  echo "op-id.sh: finder call failed" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
}

if [ "$RAW" -eq 1 ]; then
  printf '%s\n' "$OUT"
  exit 0
fi

TMP="$(mktemp -t opid)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$OUT" >"$TMP"

python3 - "$TMP" "$ONE" "$TEXT" <<'PY'
import json, sys, unicodedata

doc = json.load(open(sys.argv[1]))
mode = sys.argv[2]              # 0 = list, 1 = bare id, 2 = full row
needle = unicodedata.normalize("NFC", sys.argv[3].strip()) if len(sys.argv) > 3 else ""

if not doc.get("ok"):
    err = doc.get("error") or doc.get("result", {}).get("error") or doc
    print("op-id.sh: %s" % json.dumps(err)[:600], file=sys.stderr)
    raise SystemExit(4)

rows = doc["result"].get("rows", []) or doc["result"].get("tasks", [])
out = []
for row in rows:
    t = row.get("task", row)
    wf = t.get("workflow", {})
    loc = t.get("locator") or {}
    line = loc.get("lineNumber")
    out.append((
        t.get("identity", {}).get("operonId", "?"),
        "%s.%s" % (wf.get("pipeline", {}).get("label", "?"), wf.get("status", {}).get("label", "?")),
        (t.get("priority") or {}).get("label", "-"),
        t.get("representation", "-"),
        loc.get("filePath", "-"),
        "-" if line is None else str(line),   # zero-based, pass through verbatim
        (t.get("description") or "").replace("\t", " "),
    ))

if mode in ("1", "2"):
    winner = None
    if len(out) == 1:
        winner = out[0]
    else:
        # A case-sensitive exact description beats fuzzy neighbours, the same rule
        # the CLI itself uses for --description targeting.
        exact = [r for r in out if unicodedata.normalize("NFC", r[6].strip()) == needle]
        if needle and len(exact) == 1:
            winner = exact[0]
    if winner is not None:
        print(winner[0] if mode == "1" else "\t".join(winner))
        raise SystemExit(0)
    print("op-id.sh: expected exactly one match, got %d" % len(out), file=sys.stderr)
    for r in out:
        print("  " + "\t".join(r), file=sys.stderr)
    raise SystemExit(4)

for r in out:
    print("\t".join(r))
print("# %d candidates" % len(out), file=sys.stderr)
PY
