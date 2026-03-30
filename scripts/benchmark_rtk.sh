#!/usr/bin/env bash
# =============================================================================
# benchmark_rtk.sh — Measure RTK CLI output byte reduction
#
# Compares raw command output size vs rtk-wrapped output for common
# agent shell operations: directory listing, file reading, git, grep.
#
# Usage:
#   ./scripts/benchmark_rtk.sh                   # uses ./memstack as target
#   ./scripts/benchmark_rtk.sh /path/to/repo     # use a specific git repo
#   ./scripts/benchmark_rtk.sh --json            # machine-readable output
# =============================================================================

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT_DIR/memstack"
JSON_OUT=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUT=true ;;
    --*)    echo "Unknown flag: $arg"; exit 1 ;;
    *)      TARGET_DIR="$arg" ;;
  esac
done

# ── Checks ────────────────────────────────────────────────────────────────────
if ! command -v rtk &>/dev/null; then
  echo "Error: rtk not found. Run ./scripts/install.sh first."
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: target directory not found: $TARGET_DIR"
  echo "Run ./scripts/install.sh first to clone memstack, or pass a git repo path."
  exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# Run a command and return byte count
byte_count() { eval "$1" 2>/dev/null | wc -c | tr -d ' '; }

# Compute reduction %
reduction() {
  python3 -c "
raw=$1; comp=$2
if raw == 0:
    print('N/A')
else:
    r = (1 - comp/raw) * 100
    print(f'{r:.1f}%')
" 2>/dev/null || echo "N/A"
}

declare -a NAMES RAW_VALS RTK_VALS

run_case() {
  local name="$1"
  local raw_cmd="$2"
  local rtk_cmd="$3"
  local raw rtk
  raw=$(byte_count "$raw_cmd")
  rtk=$(byte_count "$rtk_cmd")
  NAMES+=("$name")
  RAW_VALS+=("$raw")
  RTK_VALS+=("$rtk")
}

# ── Test cases ────────────────────────────────────────────────────────────────

# Directory listing — small structured dir
if [[ -d "$TARGET_DIR/skills" ]]; then
  run_case "ls skills/ (dir listing)" \
    "ls -la '$TARGET_DIR/skills'" \
    "rtk ls '$TARGET_DIR/skills'"
fi

# Directory listing — larger dir
if [[ -d "$TARGET_DIR/db" ]]; then
  run_case "ls db/ (small dir)" \
    "ls -la '$TARGET_DIR/db'" \
    "rtk ls '$TARGET_DIR/db'"
fi

# File read — Python source
DB_PY="$TARGET_DIR/db/memstack-db.py"
if [[ -f "$DB_PY" ]]; then
  run_case "read memstack-db.py (code)" \
    "cat '$DB_PY'" \
    "rtk read '$DB_PY'"
fi

# File read — Markdown
README="$TARGET_DIR/README.md"
if [[ -f "$README" ]]; then
  run_case "read README.md (markdown)" \
    "cat '$README'" \
    "rtk read '$README'"
fi

# Git status
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
  run_case "git status" \
    "git -C '$TARGET_DIR' status" \
    "rtk git -C '$TARGET_DIR' status"

  run_case "git log -20" \
    "git -C '$TARGET_DIR' log --oneline -20" \
    "rtk git -C '$TARGET_DIR' log -n 20"
fi

# Grep — search for function definitions
if [[ -d "$TARGET_DIR/db" ]]; then
  run_case "grep 'def ' db/" \
    "grep -rn 'def ' '$TARGET_DIR/db/'" \
    "rtk grep 'def ' '$TARGET_DIR/db/'"
fi

# ── Output ────────────────────────────────────────────────────────────────────

if [[ "$JSON_OUT" == "true" ]]; then
  echo "["
  for i in "${!NAMES[@]}"; do
    raw="${RAW_VALS[$i]}"
    rtk="${RTK_VALS[$i]}"
    red_pct=$(python3 -c "raw=$raw; rtk=$rtk; print(round((1-rtk/raw)*100,1) if raw>0 else 0)" 2>/dev/null || echo 0)
    comma=""
    [[ $i -lt $((${#NAMES[@]} - 1)) ]] && comma=","
    printf '  {"case": "%s", "raw_bytes": %s, "rtk_bytes": %s, "reduction_pct": %s}%s\n' \
      "${NAMES[$i]}" "$raw" "$rtk" "$red_pct" "$comma"
  done
  echo "]"
else
  echo ""
  echo "=== RTK Benchmark ==="
  echo "Target: $TARGET_DIR"
  echo ""
  printf "%-35s %12s %12s %10s\n" "Command" "Raw (bytes)" "RTK (bytes)" "Reduction"
  printf "%-35s %12s %12s %10s\n" "-------" "-----------" "-----------" "---------"

  for i in "${!NAMES[@]}"; do
    raw="${RAW_VALS[$i]}"
    rtk="${RTK_VALS[$i]}"
    red=$(reduction "$raw" "$rtk")
    # Format numbers with commas
    raw_fmt=$(printf "%'d" "$raw" 2>/dev/null || echo "$raw")
    rtk_fmt=$(printf "%'d" "$rtk" 2>/dev/null || echo "$rtk")
    printf "%-35s %12s %12s %10s\n" "${NAMES[$i]}" "$raw_fmt" "$rtk_fmt" "$red"
  done

  echo ""
  echo "Notes:"
  echo "  - rtk ls: most effective on uniform/structured directories"
  echo "  - rtk read: passthrough for code (agent needs full content)"
  echo "  - rtk git: compact summaries for status/log"
  echo "  - rtk grep: groups matches by file to reduce repetition"
  echo "  - Large flat dirs (many unrelated files) may get LARGER — rtk adds grouping overhead"
fi
