#!/usr/bin/env bash
# =============================================================================
# setup-project.sh — Add vibekit to any existing project
#
# Clone vibekit once, then call this script from any project root.
# Safe to re-run — skips steps already done, pulls updates on repeat runs.
#
# Usage (from inside your project):
#   bash ~/git/vibekit/scripts/setup-project.sh
#
# Or add a shortcut to your shell profile:
#   alias llm-setup='bash ~/git/vibekit/scripts/setup-project.sh'
#   Then just run: llm-setup
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
skip() { echo -e "${CYAN}  · $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $*${NC}"; }

# ── Resolve paths ─────────────────────────────────────────────────────────────
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # vibekit root
PROJECT_DIR="$(pwd)"                                            # the project calling this
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo ""
echo "============================================="
echo "  vibekit — Project Setup"
echo "  Project : $PROJECT_NAME"
echo "  Path    : $PROJECT_DIR"
echo "============================================="

# ── Sanity check — don't run inside vibekit itself ───────────────────
if [[ "$PROJECT_DIR" == "$TOOLS_DIR" ]]; then
  err "Run this from your project directory, not from inside vibekit."
fi

# ── 1. Check prerequisites ────────────────────────────────────────────────────
step "Checking prerequisites"

command -v python3 &>/dev/null || err "python3 not found. Install via: brew install python"
command -v git    &>/dev/null || err "git not found."
command -v brew   &>/dev/null || err "Homebrew not found. Install from brew.sh"
ok "python3, git, brew"

# ── 2. headroom — install or upgrade ─────────────────────────────────────────
step "headroom"
if python3 -c "import headroom" &>/dev/null; then
  CURRENT=$(python3 -c "import headroom; print(headroom.__version__)" 2>/dev/null || echo "unknown")
  pip install --upgrade "headroom-ai[all]" --quiet 2>/dev/null
  NEW=$(python3 -c "import headroom; print(headroom.__version__)" 2>/dev/null || echo "unknown")
  if [[ "$CURRENT" != "$NEW" ]]; then
    ok "headroom upgraded $CURRENT → $NEW"
  else
    skip "headroom already up to date ($CURRENT)"
  fi
else
  echo "  Installing headroom-ai[all] (includes PyTorch, may take a few minutes)..."
  pip install "headroom-ai[all]" --quiet 2>/dev/null
  ok "headroom $(python3 -c "import headroom; print(headroom.__version__)") installed"
fi

# Resolve absolute path to headroom binary for use later
HEADROOM_BIN="$(command -v headroom 2>/dev/null || echo "")"
if [[ -z "$HEADROOM_BIN" ]]; then
  # Try common pip install locations
  for candidate in \
    "$HOME/.pyenv/shims/headroom" \
    "$HOME/.local/bin/headroom" \
    "/usr/local/bin/headroom" \
    "/opt/homebrew/bin/headroom"; do
    [[ -x "$candidate" ]] && HEADROOM_BIN="$candidate" && break
  done
fi
[[ -z "$HEADROOM_BIN" ]] && warn "Could not locate headroom binary — proxy will need to be started manually" || true

# ── 3. rtk — install or upgrade ───────────────────────────────────────────────
step "rtk"
if command -v rtk &>/dev/null; then
  CURRENT=$(rtk --version 2>/dev/null || echo "unknown")
  brew upgrade rtk 2>/dev/null && ok "rtk upgraded" || skip "rtk already up to date ($CURRENT)"
else
  brew install rtk
  ok "rtk $(rtk --version) installed"
fi

# ── 4. memstack — clone or update ─────────────────────────────────────────────
step "memstack"
MEMSTACK_DIR="$PROJECT_DIR/.claude/skills"

if [[ -d "$MEMSTACK_DIR/.git" ]]; then
  git -C "$MEMSTACK_DIR" pull --quiet
  skip "memstack updated ($(git -C "$MEMSTACK_DIR" rev-parse --short HEAD))"
else
  mkdir -p "$PROJECT_DIR/.claude"
  git clone https://github.com/cwinvestments/memstack "$MEMSTACK_DIR" --quiet
  ok "memstack cloned"
fi

# Init DB (idempotent — won't overwrite existing data)
INIT_RESULT=$(python3 "$MEMSTACK_DIR/db/memstack-db.py" init 2>&1)
if echo "$INIT_RESULT" | grep -q '"ok": true'; then
  ok "memstack DB ready"
else
  warn "memstack DB init: $INIT_RESULT"
fi

# ── 5. rtk — wire into this project + auto-update settings.json ───────────────
step "rtk project hook"
echo "" | RTK_TELEMETRY_DISABLED=1 rtk init -g &>/dev/null || true   # suppress prompts and manual instructions

# Auto-write the PreToolUse hook into ~/.claude/settings.json
SETTINGS="$HOME/.claude/settings.json"
RTK_HOOK_SCRIPT="$HOME/.claude/hooks/rtk-rewrite.sh"

if [[ -f "$RTK_HOOK_SCRIPT" ]]; then
  python3 - "$SETTINGS" "$RTK_HOOK_SCRIPT" << 'PYEOF'
import sys, json, os

settings_path = sys.argv[1]
hook_script   = sys.argv[2]

# Load or start fresh
if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            settings = {}
else:
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    settings = {}

hook_entry = {"type": "command", "command": hook_script}
matcher    = {"matcher": "Bash", "hooks": [hook_entry]}

hooks = settings.setdefault("hooks", {})
pre   = hooks.setdefault("PreToolUse", [])

# Check if already present
already = any(
    any(h.get("command") == hook_script for h in m.get("hooks", []))
    for m in pre
)

if not already:
    pre.append(matcher)
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
    print("updated")
else:
    print("already present")
PYEOF
  RESULT=$?
  if [[ $RESULT -eq 0 ]]; then
    ok "rtk hook registered + settings.json updated"
  else
    warn "rtk hook installed but could not auto-update settings.json — add manually"
  fi
else
  skip "rtk hook script not found — run: rtk init -g"
fi

# ── 6. .gitignore — add memstack DB entries ───────────────────────────────────
step ".gitignore"
GITIGNORE="$PROJECT_DIR/.gitignore"
MARKER="# vibekit"

if [[ -f "$GITIGNORE" ]] && grep -q "$MARKER" "$GITIGNORE"; then
  skip ".gitignore already updated"
else
  cat >> "$GITIGNORE" << 'EOF'

# vibekit
.claude/skills/db/*.db
.claude/skills/db/*.db-shm
.claude/skills/db/*.db-wal
EOF
  ok ".gitignore updated"
fi

# ── 7. headroom proxy — add to shell profile ──────────────────────────────────
step "headroom proxy"
PROFILE="${ZDOTDIR:-$HOME}/.zshrc"
[[ "$SHELL" == *"bash"* ]] && PROFILE="$HOME/.bashrc"
PROXY_LINE='export ANTHROPIC_BASE_URL=http://localhost:8787'

if grep -q "ANTHROPIC_BASE_URL" "$PROFILE" 2>/dev/null; then
  skip "ANTHROPIC_BASE_URL already in $PROFILE"
else
  echo "$PROXY_LINE" >> "$PROFILE"
  ok "Added ANTHROPIC_BASE_URL to $PROFILE"
fi

export ANTHROPIC_BASE_URL=http://localhost:8787

# Start the proxy if not already running
if lsof -ti:8787 &>/dev/null; then
  skip "headroom proxy already running on :8787"
elif [[ -n "$HEADROOM_BIN" ]]; then
  nohup "$HEADROOM_BIN" proxy --port 8787 >/tmp/headroom-proxy.log 2>&1 &
  sleep 1
  lsof -ti:8787 &>/dev/null && ok "headroom proxy started on :8787" \
    || warn "headroom proxy did not start — check /tmp/headroom-proxy.log"
else
  warn "headroom binary not found — start proxy manually once PATH is updated: headroom proxy --port 8787"
fi

# ── 8. CLAUDE.md — append if not already set up ───────────────────────────────
step "CLAUDE.md"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
CLAUDE_MARKER="## Shell commands (vibekit)"

if [[ -f "$CLAUDE_MD" ]] && grep -q "$CLAUDE_MARKER" "$CLAUDE_MD"; then
  skip "CLAUDE.md already configured"
else
  cat >> "$CLAUDE_MD" << EOF

## Shell commands (vibekit)
Before using rtk, verify it is installed: command -v rtk
If installed, use rtk for all shell ops: rtk ls, rtk grep, rtk git status/log, rtk test <runner>
If not installed, fall back to standard commands and remind the user to run: bash ~/git/vibekit/scripts/setup-project.sh

## Session memory (vibekit)
Before using memstack, verify it exists: test -f .claude/skills/db/memstack-db.py
If available:
  - Session start: python3 .claude/skills/db/memstack-db.py search "<topic>"
  - Session end: python3 .claude/skills/db/memstack-db.py add-insight '{"project":"$PROJECT_NAME","type":"decision","content":"<what was decided>"}'
If not available, remind the user to run: bash ~/git/vibekit/scripts/setup-project.sh
EOF
  ok "CLAUDE.md updated"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo -e "${GREEN}  ✓ $PROJECT_NAME is ready${NC}"
echo ""
echo "  headroom  $(python3 -c "import headroom; print(headroom.__version__)" 2>/dev/null)"
echo "  rtk       $(rtk --version 2>/dev/null)"
echo "  memstack  $(git -C "$MEMSTACK_DIR" rev-parse --short HEAD 2>/dev/null)"
echo "  proxy     http://localhost:8787"
echo ""
echo "  Restart Claude Code to pick up the new CLAUDE.md."
echo "============================================="
