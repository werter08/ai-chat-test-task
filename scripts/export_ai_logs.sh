#!/bin/bash
# Copies this project's Claude Code session logs (~/.claude/projects/<project>/*.jsonl) into ai-logs/ with
# secrets and personal data removed. Re-run it at the very end of the work so the final logs are included.
#
# Removed / redacted:
#   - every embedded image (screenshots can show personal data that text redaction cannot catch)
#   - the OpenRouter API key (exact value from .env, plus sk-or-… / Bearer / GitHub token patterns)
#   - e-mail addresses, the macOS user name / home path, and every literal listed in the gitignored
#     scripts/redact.local.txt (name, handles, Apple team id, …) — nothing personal is hardcoded here
# ai-logs/ is gitignored on purpose: it ships in the zip, not in the public repository.
cd "$(dirname "$0")/.." || exit 1
SRC="$HOME/.claude/projects/$(pwd | sed 's#[/_.]#-#g')"
[ -d "$SRC" ] || { echo "No Claude logs found at $SRC"; exit 1; }
mkdir -p ai-logs

python3 -I - "$SRC" ai-logs <<'PY'
import glob, json, os, re, sys

src, out_dir = sys.argv[1], sys.argv[2]

# Exact key value from .env (never printed).
key = ""
try:
    for line in open(".env", encoding="utf-8"):
        if line.startswith("OPENROUTER_API_KEY="):
            key = line.split("=", 1)[1].strip().strip("'\"")
except OSError:
    pass

exact = [key] if len(key) > 8 and "<" not in key else []
# Personal identifiers: the macOS user name (derived at runtime) plus every literal listed, one per line, in the
# gitignored scripts/redact.local.txt (name, handles, team id, …). Nothing personal is hardcoded in this script.
words = []
home_user = os.path.basename(os.path.expanduser("~"))
if home_user:
    words.append((re.compile(re.escape(home_user), re.I), "<user>"))
try:
    for extra in open("scripts/redact.local.txt", encoding="utf-8"):
        extra = extra.strip()
        if extra and not extra.startswith("#"):
            words.append((re.compile(re.escape(extra), re.I), "<redacted>"))
except OSError:
    pass
patterns = [
    (re.compile(r"sk-or-[A-Za-z0-9_\-]+"), "<API_KEY>"),
    (re.compile(r"Bearer\s+[A-Za-z0-9._\-]{16,}"), "Bearer <API_KEY>"),
    (re.compile(r"gh[opsu]_[A-Za-z0-9]{20,}"), "<GITHUB_TOKEN>"),
    (re.compile(r"user_[A-Za-z0-9]{20,}"), "<USER_ID>"),
    (re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"), "<EMAIL>"),
]

def scrub_text(text):
    for value in exact:
        text = text.replace(value, "<API_KEY>")
    for regex, new in words:
        text = regex.sub(new, text)
    for regex, new in patterns:
        text = regex.sub(new, text)
    return text

def walk(node):
    """Drops images and scrubs every string, recursively."""
    if isinstance(node, dict):
        if node.get("type") == "image":
            return {"type": "text", "text": "[image omitted]"}
        return {scrub_text(k): walk(v) for k, v in node.items()}
    if isinstance(node, list):
        return [walk(v) for v in node]
    if isinstance(node, str):
        return scrub_text(node)
    return node

images = lines = 0
for path in sorted(glob.glob(os.path.join(src, "*.jsonl"))):
    target = os.path.join(out_dir, os.path.basename(path))
    with open(path, encoding="utf-8") as fin, open(target, "w", encoding="utf-8") as fout:
        for raw in fin:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            lines += 1
            try:
                record = json.loads(raw)
            except json.JSONDecodeError:
                fout.write(scrub_text(raw) + "\n")
                continue
            images += raw.count('"type":"image"') + raw.count('"type": "image"')
            fout.write(json.dumps(walk(record), ensure_ascii=False) + "\n")
    print(f"exported {os.path.basename(path)}: {lines} records, images removed (approx.): {images}")
PY
status=$?
[ $status -eq 0 ] || exit $status

# Safety check: fail loudly (and delete the export) if anything sensitive survived.
KEY=$(grep '^OPENROUTER_API_KEY=' .env 2>/dev/null | cut -d= -f2-)
bad=0
if [ -n "$KEY" ] && grep -rqF -- "$KEY" ai-logs; then echo "ERROR: API key still present"; bad=1; fi
HOME_USER=$(basename "$HOME")
if [ -n "$HOME_USER" ] && grep -rqiF -- "$HOME_USER" ai-logs; then echo "ERROR: the macOS user name is still present"; bad=1; fi
if [ -f scripts/redact.local.txt ]; then
  while IFS= read -r needle; do
    case "$needle" in ''|\#*) continue;; esac
    if grep -rqiF -- "$needle" ai-logs; then echo "ERROR: a locally redacted term is still present"; bad=1; fi
  done < scripts/redact.local.txt
fi
if grep -rqE '"type": ?"image"' ai-logs; then echo "ERROR: an image survived"; bad=1; fi
if [ $bad -ne 0 ]; then rm -f ai-logs/*.jsonl; exit 1; fi
echo "Done. Verified: no key, no images, no personal identifiers. ($(du -sh ai-logs | cut -f1))"
