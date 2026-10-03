#!/usr/bin/env bash
# fm-gardener.sh - sample closed-task pipeline findings into a ranked candidate-cluster report.
# Usage: fm-gardener.sh [--help]
# Reads the newest 20 <FM_HOME>/data/<task>/nm-*-findings.txt snapshots whose task
# is closed in the backlog (one tasks-axi list call). Findings use id, severity,
# file, line, description, and authority fields, as key=value text or JSON lines.
# Clusters share the first six lowercase words of the description. Clusters with
# two or more hits print with their snapshot count and file paths as evidence.
# Clusters are candidates for a cause review, not causes. It files no tasks and
# edits no project or preference file. The run record is <FM_HOME>/state/fm-gardener.tsv.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOME_DIR=${FM_HOME:-$ROOT}
DATA_DIR=${FM_DATA_OVERRIDE:-$HOME_DIR/data}
STATE_DIR=${FM_STATE_OVERRIDE:-$HOME_DIR/state}

if [ "${1:-}" = --help ]; then
  sed -n '2,10p' "$0" | sed 's/^# //'
  exit 0
fi
[ "$#" -eq 0 ] || { printf 'fm-gardener: unexpected argument: %s\n' "$1" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'fm-gardener: python3 is required\n' >&2; exit 2; }
[ -d "$DATA_DIR" ] || { printf 'fm-gardener: data directory is missing: %s\n' "$DATA_DIR" >&2; exit 2; }
mkdir -p "$STATE_DIR"
CLOSED=$(FM_HOME="$HOME_DIR" "$ROOT/bin/fm-tasks-axi.sh" list --state 'done' --limit 500) \
  || { printf 'fm-gardener: cannot read closed tasks\n' >&2; exit 2; }

python3 - "$DATA_DIR" "$STATE_DIR" "$CLOSED" <<'PY'
import json
import os
import re
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

data_dir, state_dir = Path(sys.argv[1]), Path(sys.argv[2])
closed = {line.strip().split(",", 1)[0] for line in sys.argv[3].splitlines() if line.startswith("  ") and "," in line}
window = 20
candidates = [p for p in data_dir.glob("*/nm-*-findings.txt") if p.parent.name in closed]
files = sorted(candidates, key=lambda p: (-p.stat().st_mtime, str(p)))[:window]
fields_re = re.compile(r"\b(id|severity|file|line|description|authority)\s*[:=]\s*(.*?)(?=\s+\b(?:id|severity|file|line|description|authority)\s*[:=]|$)", re.I)
hits = defaultdict(int)
snapshots = defaultdict(set)
paths = defaultdict(set)
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
        words = re.findall(r"[a-z0-9]+(?:[-_'][a-z0-9]+)*", finding["description"].lower())
        if not words:
            continue
        key = " ".join(words[:6])
        hits[key] += 1
        snapshots[key].add(source.name)
        paths[key].add(finding["file"].strip().replace("\\", "/"))
        finding_count += 1

ranked = sorted((k for k in hits if hits[k] >= 2), key=lambda k: (-hits[k], k))
print("candidate clusters for cause review (not causes):")
for key in ranked:
    print(f"{key} | hits={hits[key]} | snapshots={len(snapshots[key])} | paths={','.join(sorted(paths[key]))}")

completed = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
result = "candidates" if ranked else ("sampled" if finding_count else "empty")
summary = f"result={result} files={len(files)} findings={finding_count} clusters={len(hits)} candidates={len(ranked)}"
record = f"completed_at={completed}\t" + summary.replace(" ", "\t") + "\n"
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
print(summary)
PY
