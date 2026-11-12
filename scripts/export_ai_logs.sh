#!/bin/bash
# Copies this project's Claude Code session logs into ai-logs/ with secrets and personal data redacted.
# Re-run it at the very end of the work so the final logs are included.
cd "$(dirname "$0")/.." || exit 1
SRC="$HOME/.claude/projects/$(pwd | sed 's#[/_.]#-#g')"
[ -d "$SRC" ] || { echo "No Claude logs found at $SRC"; exit 1; }
mkdir -p ai-logs

KEY=$(grep '^OPENROUTER_API_KEY=' .env 2>/dev/null | cut -d= -f2-)
export KEY

for f in "$SRC"/*.jsonl; do
  out="ai-logs/$(basename "$f")"
  perl -pe '
    BEGIN { $k = $ENV{KEY} // ""; }
    s/\Q$k\E/<API_KEY>/g if length($k) > 8;
    s/sk-or-[A-Za-z0-9_\-]+/<API_KEY>/g;
    s/Bearer\s+[A-Za-z0-9._\-]{16,}/Bearer <API_KEY>/g;
    s/gh[opsu]_[A-Za-z0-9]{20,}/<GITHUB_TOKEN>/g;
    s/user_[A-Za-z0-9]{20,}/<USER_ID>/g;
    s/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/<EMAIL>/g;
  ' "$f" > "$out"
  echo "exported $(basename "$f") -> $out"
done

# Safety check: fail loudly if the key still appears anywhere.
if [ -n "$KEY" ] && grep -rqF -- "$KEY" ai-logs; then
  echo "ERROR: API key still present in ai-logs/ — deleting export."; rm -rf ai-logs/*.jsonl; exit 1
fi
echo "Done. Review ai-logs/ before sharing."
