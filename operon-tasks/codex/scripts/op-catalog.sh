#!/usr/bin/env bash
# op-catalog.sh - compact, cached cheat sheet of the live Operon catalog.
#
# Prints the exact strings needed for compact syntax: Pipeline.Status values with
# the user's own pipeline descriptions, the priority ladder with its descriptions,
# and canonical keys grouped by owning command.
#
# Cache lives outside the vault in ~/.cache/operon-skill/.
# Fresh cache prints instantly. Stale cache is validated against the live
# settingsFingerprint (one cheap health call) before a full refetch.
#
# Usage:
#   op-catalog.sh              full cheat sheet (cached when possible)
#   op-catalog.sh --statuses   routing sheet: pipelines + descriptions + priority ladder
#   op-catalog.sh --bare       only the Pipeline.Status labels, no descriptions
#   op-catalog.sh --force      always refetch
#   op-catalog.sh --ttl 3600   override the freshness window (default 900s)
#   op-catalog.sh --raw        print the path of the cached catalog JSON
set -euo pipefail

CACHE_DIR="${HOME}/.cache/operon-skill"
CAT_JSON="${CACHE_DIR}/catalog.json"
BRIEF="${CACHE_DIR}/catalog-brief.txt"
FP="${CACHE_DIR}/fingerprint.txt"
TTL=900
FORCE=0
MODE="brief"

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --raw) MODE="raw" ;;
    --statuses) MODE="statuses" ;;
    --bare) MODE="bare" ;;
    --ttl) shift; TTL="${1:-900}" ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "op-catalog.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$CACHE_DIR"

file_age() { # seconds since mtime, or a huge number when missing
  [ -f "$1" ] || { echo 999999999; return; }
  local now mt
  now=$(date +%s)
  mt=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0)
  echo $(( now - mt ))
}

render() {
  python3 - "$CAT_JSON" "$MODE" <<'PY'
import json, sys, textwrap

path, mode = sys.argv[1], sys.argv[2]
with open(path) as fh:
    doc = json.load(fh)
res = doc["result"]
tax = res["taxonomy"]
fields = res["fields"]

pipelines = sorted(tax["pipelines"], key=lambda p: p.get("order", 0))
priorities = sorted(tax["priorities"], key=lambda p: p.get("order", 0))


def statuses_of(pl):
    return " ".join(
        "%s.%s" % (pl["name"], st["label"])
        for st in sorted(pl["statuses"], key=lambda s: s.get("order", 0))
    )


def wrap_desc(text, indent="      "):
    return textwrap.fill(
        " ".join(text.split()), width=94,
        initial_indent=indent, subsequent_indent=indent,
    )


def print_routing():
    print("ROUTING  the user authored every description below. Decide from them, not from")
    print("intuition about a pipeline's name. Obey each \"Do not use...\" sentence literally.")
    print("Statuses carry no description of their own: their meaning is the closing sentence")
    print("of the owning pipeline description.")
    print()
    for pl in pipelines:
        print("  " + statuses_of(pl))
        d = pl.get("description")
        print(wrap_desc(d) if d else
              "      (no description authored: judge from the status labels alone)")
        print()
    print("PRIORITY  choose deliberately on every task. Each entry states when to pick the")
    print("neighbouring level instead, so read the comparison, not just the label.")
    print()
    for pr in priorities:
        print("  %s%s" % (pr["label"], "  (default)" if pr.get("isDefault") else ""))
        d = pr.get("description")
        print(wrap_desc(d) if d else "      (no description authored)")
        print()


if mode == "bare":
    print("\n".join("  " + statuses_of(pl) for pl in pipelines))
    raise SystemExit(0)

if mode == "statuses":
    print_routing()
    raise SystemExit(0)


def keys(owner, cls=None):
    out = []
    for f in fields:
        if f.get("mutationOwner") != owner:
            continue
        if cls and f.get("mutationClass") != cls:
            continue
        out.append(f["canonicalKey"])
    return out


def wrap(items, indent="  ", width=96):
    line, lines = indent, []
    for it in items:
        if len(line) + len(it) + 1 > width:
            lines.append(line.rstrip())
            line = indent
        line += it + " "
    if line.strip():
        lines.append(line.rstrip())
    return "\n".join(lines)


custom = [f["canonicalKey"] for f in fields if f.get("source") == "custom"]
ro = [f["canonicalKey"] for f in fields if f.get("mutationClass") == "runtime-owned"]

print_routing()
print("task update  (general fields, freely combined)")
print(wrap(sorted(keys("tasks.update", "general-update"))))
if custom:
    print("  custom fields above: " + " ".join(sorted(custom)))
print()
print("task update  (recurrence, cannot mix with general or relationship fields)")
print("  assignable: repeat datetimeRepeatEnd")
print("  with --scope this-task|this-and-following on a recurring task:")
print("    dateScheduled dateStarted dateDue datetimeStart datetimeEnd estimate")
print("  read-only series state: repeatSeriesId repeatOccurrenceDate")
print()
print("task update  (relationships, cannot mix with general fields)")
print(wrap(sorted(keys("tasks.relationship"))))
print()
print("dedicated commands only")
print("  status dateCompleted dateCancelled checkbox  -> task complete/reopen/cancel/transition")
print("  reminderDatetimes reminderRules              -> reminder add/replace/remove")
print("  trackers activeTracker                       -> timer start/stop, timer session *")
print("  pinned                                       -> task pin/unpin")
print("  representation                               -> task convert")
print("  locator                                      -> task relocate")
print()
print("read-only (runtime-owned, never assignable)")
print(wrap(sorted(ro)))
print()
print("placement: never resolved here. Omit target flags on create and let the")
print("Runtime resolve configured-default from the user's live settings.")
PY
}

refresh() {
  local tmp="${CAT_JSON}.tmp.$$"
  if ! operon catalog --json >"$tmp" 2>"${tmp}.err"; then
    cat "${tmp}.err" >&2
    rm -f "$tmp" "${tmp}.err"
    echo "op-catalog.sh: live catalog read failed (is Obsidian open?)" >&2
    exit 3
  fi
  rm -f "${tmp}.err"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("ok") else 1)' "$tmp" || {
    rm -f "$tmp"
    echo "op-catalog.sh: runtime returned a failed catalog envelope" >&2
    exit 5
  }
  mv "$tmp" "$CAT_JSON"
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["contextRevision"]["settingsFingerprint"])' "$CAT_JSON" >"$FP"
  render >"$BRIEF"
}

live_fingerprint() {
  operon health --json 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["contextRevision"]["settingsFingerprint"])' 2>/dev/null || true
}

if [ "$FORCE" -eq 1 ] || [ ! -f "$CAT_JSON" ] || [ ! -f "$BRIEF" ]; then
  refresh
elif [ "$(file_age "$BRIEF")" -ge "$TTL" ]; then
  live=$(live_fingerprint)
  cached=$(cat "$FP" 2>/dev/null || echo "")
  if [ -n "$live" ] && [ "$live" = "$cached" ]; then
    touch "$BRIEF"
  else
    refresh
  fi
fi

case "$MODE" in
  raw) echo "$CAT_JSON" ;;
  statuses|bare) render ;;
  *) cat "$BRIEF" ;;
esac
