#!/usr/bin/env bash
# op-icon.sh - offline lucide icon resolver for Operon task creation.
#
# No CLI call, no network. It reads the plugin's generated tag corpus
# (.obsidian/plugins/operon/src/generated/lucide-icon-tags.ts, 1694 icons, every
# one tagged) and answers in a single awk process: ~15 ms fixed plus ~2 ms per
# query. All queries of one dictation belong in ONE call.
#
# LANGUAGE RULE (read this before using it):
#   The corpus is English and always will be, whatever language the task was
#   dictated in. Do NOT build per-language synonym tables: the model already
#   translates for free. Read the meaning of the task, then pass 2-4 English
#   concept words. Words inside one query are ALTERNATIVES, the best-scoring one
#   wins, so redundancy is the error budget:
#       a task about paying a bill    -> query "invoice bill receipt payment"
#       a medical appointment         -> query "doctor medical appointment health"
#       a task about fixing a defect  -> query "bug defect error fix"
#
# Modes:
#   op-icon.sh "bug defect" "meeting calendar"    lookup: TSV query<TAB>id,id,id
#   op-icon.sh --first "bug defect"               best id only, or "-"
#   op-icon.sh --validate bug rocket no-such      id<TAB>ok|missing
#   op-icon.sh --rewrite  < lines > lines         resolve taskIcon::"?query"
#                                                 tokens inside compact lines
#   --top N        candidates per query in lookup mode (default 3)
#
# Scoring (tuned for auto-assign, not for mirroring the in-app icon picker):
#   0 id is the word   1 word is an exact tag   2 word inside id   3 word inside a tag
#   ties: shorter id first, then alphabetical. Words shorter than 2 chars are ignored.
#
# Failure policy: if the corpus is missing the script says so on stderr and
# --rewrite DROPS the icon token instead of writing junk, so the task is still
# created. An unresolved query yields "-" and no taskIcon.
#
# Exit codes: 0 ok (even when nothing matched), 2 usage, 3 corpus not found.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REL=".obsidian/plugins/operon/src/generated/lucide-icon-tags.ts"

find_corpus() {
  if [ -n "${OPERON_ICON_TAGS:-}" ]; then
    [ -f "$OPERON_ICON_TAGS" ] && { printf '%s\n' "$OPERON_ICON_TAGS"; return 0; }
    return 1
  fi
  local dir="$HERE"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/$REL" ] && { printf '%s\n' "$dir/$REL"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

MODE="lookup" ; TOP=3
while [ $# -gt 0 ]; do
  case "$1" in
    --first) MODE="first" ;;
    --validate) MODE="validate" ;;
    --rewrite) MODE="rewrite" ;;
    --top) shift; TOP="${1:-3}" ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) echo "op-icon.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

CORPUS="$(find_corpus || true)"
if [ -z "$CORPUS" ]; then
  echo "op-icon.sh: lucide tag corpus not found ($REL). Set OPERON_ICON_TAGS." >&2
  # Fail open on rewrite: strip icon tokens so the create still goes through.
  [ "$MODE" = "rewrite" ] && sed -E 's/[[:space:]]*taskIcon::"\?[^"]*"//g'
  exit 3
fi

# Shared corpus loader: ids[] and tags[] (tags[i] excludes the id itself, so an
# exact-tag test cannot be fooled by the id's own quotes).
read -r -d '' LOAD <<'AWK' || true
FNR == NR {
  if (match($0, /^\t"[^"]+"/)) {
    n++
    ids[n] = substr($0, RSTART + 2, RLENGTH - 3)
    tags[n] = tolower(substr($0, RSTART + RLENGTH))
  }
  next
}
AWK

read -r -d '' SCORE <<'AWK' || true
function score_all(query,   nw, W, w, i, k, s, hit) {
  nw = split(tolower(query), W, /[^a-z0-9]+/)
  for (i = 1; i <= n; i++) {
    s = 9; hit = 0
    for (k = 1; k <= nw; k++) {
      w = W[k]
      if (length(w) < 2) continue
      if (ids[i] == w) { s = 0; hit++; continue }
      if (index(tags[i], "\"" w "\"") > 0) { if (s > 1) s = 1; hit++; continue }
      if (index(ids[i], w) > 0) { if (s > 2) s = 2; hit++; continue }
      if (index(tags[i], w) > 0) { if (s > 3) s = 3; hit++ }
    }
    # Best bucket decides, then how many of the query words the icon covers,
    # then the shorter id. Coverage is what keeps a 4-word query from landing
    # on an icon that merely shares one generic tag.
    sc[i] = (s == 9) ? 99999 : s * 100 - hit * 10 + length(ids[i]) / 100
  }
}
function pick(want,   out, p, i, bi, bs) {
  out = ""
  for (p = 0; p < want; p++) {
    bi = 0; bs = 999
    for (i = 1; i <= n; i++) if (sc[i] < bs) { bs = sc[i]; bi = i }
    if (bi == 0 || bs >= 99999) break
    out = out (out == "" ? "" : ",") ids[bi]
    sc[bi] = 999
  }
  return out
}
AWK

case "$MODE" in
  validate)
    [ $# -gt 0 ] || { echo "op-icon.sh: --validate needs at least one icon id" >&2; exit 2; }
    for raw in "$@"; do
      id="${raw#lucide-}"
      if grep -qE "^[[:space:]]+\"${id}\":" "$CORPUS"; then printf '%s\tok\n' "$id"
      else printf '%s\tmissing\n' "$id"; fi
    done
    exit 0 ;;

  rewrite)
    awk "$LOAD
$SCORE"'
{
  line = $0
  while (match(line, /taskIcon::"\?[^"]*"/)) {
    tok = substr(line, RSTART, RLENGTH)
    q = substr(tok, 13, length(tok) - 13)
    score_all(q)
    id = pick(1)
    if (id == "") {
      printf "op-icon.sh: no icon matched %s\n", q > "/dev/stderr"
      sub(/[ \t]*taskIcon::"\?[^"]*"/, "", line)
    } else {
      sub(/taskIcon::"\?[^"]*"/, "taskIcon::\"" id "\"", line)
      printf "# icon: %s -> %s\n", q, id > "/dev/stderr"
    }
  }
  print line
}' "$CORPUS" -
    exit 0 ;;

  lookup|first)
    [ $# -gt 0 ] || { echo "op-icon.sh: give at least one query" >&2; exit 2; }
    QF="$(mktemp -t opicon)"
    trap 'rm -f "$QF"' EXIT
    printf '%s\n' "$@" >"$QF"
    awk -v top="$TOP" -v mode="$MODE" "$LOAD
$SCORE"'
{
  if ($0 == "") next
  score_all($0)
  out = pick(mode == "first" ? 1 : top)
  if (out == "") out = "-"
  if (mode == "first") print out
  else printf "%s\t%s\n", $0, out
}' "$CORPUS" "$QF"
    exit 0 ;;
esac
