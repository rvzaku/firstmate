#!/usr/bin/env bash
# fm-gardener.sh - cluster pipeline findings and queue recurring lint rules.
# Usage: fm-gardener.sh [--help]
# Reads <FM_HOME>/data/*/nm-*-findings.txt and writes its run record to
# <FM_HOME>/state/fm-gardener.tsv. Findings use id, severity, file, line,
# description, and authority fields. Only a short normalized theme label and
# count are printed or copied to a queued task.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOME_DIR=${FM_HOME:-$ROOT}
DATA_DIR=${FM_DATA_OVERRIDE:-$HOME_DIR/data}
STATE_DIR=${FM_STATE_OVERRIDE:-$HOME_DIR/state}

if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then
  sed -n '2,8p' "$0" | sed 's/^# //'
  exit 0
fi
[ "$#" -eq 0 ] || { printf 'fm-gardener: unexpected argument: %s\n' "$1" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'fm-gardener: python3 is required\n' >&2; exit 2; }
[ -d "$DATA_DIR" ] || { printf 'fm-gardener: data directory is missing: %s\n' "$DATA_DIR" >&2; exit 2; }
mkdir -p "$STATE_DIR"

python3 - "$DATA_DIR" "$STATE_DIR" "$ROOT" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

data_dir, state_dir, root = map(Path, sys.argv[1:])
files = sorted(data_dir.glob("*/nm-*-findings.txt"))
fields_re = re.compile(r"\b(id|severity|file|line|description|authority)\s*[:=]\s*(.*?)(?=\s+\b(?:id|severity|file|line|description|authority)\s*[:=]|$)", re.I)
stop = {"a", "an", "and", "are", "as", "at", "be", "been", "being", "by", "for", "from", "in", "is", "it", "of", "on", "or", "that", "the", "this", "to", "was", "were", "with", "without", "should", "must", "can", "could", "not", "use", "using"}
clusters = Counter()
labels = {}
finding_count = 0

def parse_line(line):
    line = line.strip()
    if not line:
        return None
    try:
        value = json.loads(line)
        if isinstance(value, dict):
            return {str(k).lower(): str(v) for k, v in value.items()}
    except json.JSONDecodeError:
        pass
    result = {}
    for match in fields_re.finditer(line.lstrip("-* ")):
        result[match.group(1).lower()] = match.group(2).strip().strip('"')
    return result if result else None

for source in files:
    for raw in source.read_text(errors="replace").splitlines():
        finding = parse_line(raw)
        if not finding or not finding.get("file") or not finding.get("description"):
            continue
        path = finding["file"].strip().replace("\\", "/")
        words = [w.lower() for w in re.findall(r"[A-Za-z][A-Za-z0-9_-]*", finding["description"])]
        words = [w for w in words if w not in stop and not w.isdigit()]
        if not words:
            continue
        theme_words = words[:3]
        label = " ".join(theme_words)
        key = (path, label)
        clusters[key] += 1
        labels[key] = label
        finding_count += 1

def task_id(key):
    digest = hashlib.sha256((key[0] + "\0" + key[1]).encode()).hexdigest()[:10]
    return "gardener-" + digest

ranked = sorted(clusters, key=lambda key: (-clusters[key], key[0], key[1]))
for key in ranked:
    print(f"{key[0]} | {labels[key]} | hits={clusters[key]}")

queued = 0
tasks = Path(root) / "bin/fm-tasks-axi.sh"
for key in ranked:
    count = clusters[key]
    if count < 2:
        continue
    identity = task_id(key)
    existing = subprocess.run([str(tasks), "show", identity], capture_output=True, text=True)
    if existing.returncode == 0:
        continue
    title = "Lint rule: " + labels[key]
    body = f"Add a static lint rule for recurring findings in {key[0]}. The same normalized theme appeared {count} times."
    subprocess.run([str(tasks), "add", identity, title, "--kind", "ship", "--body", body], check=True, stdout=subprocess.DEVNULL)
    queued += 1

completed = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
result = "queued" if queued else ("sampled" if finding_count else "empty")
record = f"completed_at={completed}\tresult={result}\tfiles={len(files)}\tfindings={finding_count}\tthemes={len(clusters)}\tqueued={queued}\n"
state_dir.mkdir(parents=True, exist_ok=True)
fd, temp_path = tempfile.mkstemp(prefix=".fm-gardener.", dir=state_dir, text=True)
try:
    with os.fdopen(fd, "w") as handle:
        handle.write(record)
    os.replace(temp_path, state_dir / "fm-gardener.tsv")
except BaseException:
    try:
        os.unlink(temp_path)
    except FileNotFoundError:
        pass
    raise
print(f"result={result} files={len(files)} findings={finding_count} themes={len(clusters)} queued={queued}")
PY
