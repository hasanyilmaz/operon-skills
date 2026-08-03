#!/usr/bin/env bash
# help-dump.sh - MAINTENANCE ONLY, read-only.
#
# Regenerates the live help corpus for every operon leaf command and compares
# the live contractDigest against the pin in SKILL.md §11. Use it when
# updating the operon-cli reference skill; it is never needed at task time.
#
# Output: ~/.cache/operon-cli-skill/help-corpus-<digest>.txt (disposable,
# digest-keyed; the corpus is deliberately NOT committed into the skill).
# Last line: DIGEST MATCH or DIGEST DRIFT.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$HERE/../SKILL.md"
CACHE_DIR="${HOME}/.cache/operon-cli-skill"
mkdir -p "$CACHE_DIR"

LIVE_DIGEST="$(operon manifest --json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["contractDigest"])')"

OUT="$CACHE_DIR/help-corpus-${LIVE_DIGEST:0:12}.txt"
: > "$OUT"

# All 47 leaf commands (from the manifest's local/runtime/convenience buckets).
CMDS=(
  "version" "setup" "doctor" "completion" "manifest"
  "profile list" "profile default" "profile remove"
  "schema list" "schema get"
  "plan show" "plan apply" "plan recover" "plan discard"
  "task find"
  "health" "capabilities" "diagnostics" "catalog"
  "task get" "query" "finder" "relationships" "entity resolve" "context" "timer state"
  "mutation preview" "mutation apply"
  "task create" "task update" "task complete" "task reopen" "task cancel"
  "task transition" "task pin" "task unpin" "task delete" "task convert" "task relocate"
  "reminder add" "reminder replace" "reminder remove"
  "timer start" "timer stop" "timer session add" "timer session update" "timer session remove"
)

FAILED=0
for c in "${CMDS[@]}"; do
  printf '\n===== operon %s =====\n' "$c" >> "$OUT"
  # shellcheck disable=SC2086  # intentional word splitting of multi-word commands (bash, not zsh)
  if ! operon $c --help >> "$OUT" 2>&1; then
    printf '(HELP FAILED for %s)\n' "$c" >> "$OUT"
    FAILED=$((FAILED + 1))
  fi
done

echo "corpus: $OUT ($(grep -c '^===== ' "$OUT") commands, $FAILED failures)"

PINNED="$(grep -oE '[a-f0-9]{64}' "$SKILL_MD" | head -1 || true)"
if [ "$PINNED" = "$LIVE_DIGEST" ]; then
  echo "DIGEST MATCH ($LIVE_DIGEST)"
else
  echo "DIGEST DRIFT (pinned ${PINNED:-none}, live $LIVE_DIGEST)"
  echo "The skill may be stale: re-verify sections against the corpus and re-pin SKILL.md §11."
fi
