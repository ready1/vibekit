#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — Remove vibekit from a project and restore normal Claude
#
# Run from inside the project you want to clean up.
# Does NOT uninstall headroom or rtk globally — see flags below.
#
# Usage:
#   bash ~/git/vibekit/scripts/uninstall.sh           # project only
#   bash ~/git/vibekit/scripts/uninstall.sh --global  # project + global tools
# =============================================================================

set -euo pipefail

GLOBAL=false
for arg in "$@"; do
  [[ "$arg" == "--global" ]] && GLOBAL=true
done

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
skip() { echo -e "${CYAN}  · $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
step() { echo -e "\n${YELLOW}▶ $*${NC}"; }

echo ""
echo "============================================="
echo "  vibekit — Uninstall"
echo "  Project : $PROJECT_NAME"
echo "  Path    : $PROJECT_DIR"
[[ "$GLOBAL" == "true" ]] && echo "  Mode    : project + global tools" || echo "  Mode    : project only (--global to also remove tools)"
echo "============================================="

# ── 1. Stop headroom proxy ────────────────────────────────────────────────────
step "headroom proxy"
if lsof -ti:8787 &>/dev/null; then
  kill "$(lsof -ti:8787)" 2>/dev/null && ok "headroom proxy stopped" || warn "Could not stop proxy — kill manually: kill \$(lsof -ti:8787)"
else
  skip "headroom proxy not running"
fi

# ── 2. Remove ANTHROPIC_BASE_URL from shell profile ───────────────────────────
step "Shell profile"
for PROFILE in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
  if [[ -f "$PROFILE" ]] && grep -q "ANTHROPIC_BASE_URL" "$PROFILE"; then
    # Remove the line in-place
    sed -i.bak '/ANTHROPIC_BASE_URL/d' "$PROFILE"
    ok "Removed ANTHROPIC_BASE_URL from $PROFILE (backup: ${PROFILE}.bak)"
  fi
done
unset ANTHROPIC_BASE_URL 2>/dev/null || true

# ── 3. Remove memstack from this project ──────────────────────────────────────
step "memstack (.claude/skills/)"
MEMSTACK_DIR="$PROJECT_DIR/.claude/skills"
if [[ -d "$MEMSTACK_DIR" ]]; then
  # Offer to export memory first
  DB="$MEMSTACK_DIR/db/memstack.db"
  if [[ -f "$DB" ]]; then
    EXPORT_PATH="$PROJECT_DIR/memstack-export-$(date +%Y%m%d).md"
    python3 "$MEMSTACK_DIR/db/memstack-db.py" export-md "$PROJECT_NAME" > "$EXPORT_PATH" 2>/dev/null \
      && warn "Memory exported to $EXPORT_PATH before removal — keep this if you want a record" \
      || true
  fi
  rm -rf "$MEMSTACK_DIR"
  ok "Removed .claude/skills/"
  # Remove .claude dir if now empty
  [[ -d "$PROJECT_DIR/.claude" ]] && rmdir "$PROJECT_DIR/.claude" 2>/dev/null && ok "Removed empty .claude/" || true
else
  skip ".claude/skills/ not found"
fi

# ── 4. Remove vibekit block from CLAUDE.md ───────────────────────────
step "CLAUDE.md"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]] && grep -q "vibekit" "$CLAUDE_MD"; then
  # Remove the block between the marker and next ## heading (or end of file)
  python3 - "$CLAUDE_MD" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path) as f:
    content = f.read()
# Remove everything from the vibekit shell block to the next top-level section
cleaned = re.sub(
    r'\n## Shell commands \(vibekit\).*?(?=\n## |\Z)',
    '',
    content,
    flags=re.DOTALL
)
cleaned = re.sub(
    r'\n## Session memory \(vibekit\).*?(?=\n## |\Z)',
    '',
    cleaned,
    flags=re.DOTALL
)
# Remove trailing blank lines
cleaned = cleaned.rstrip() + '\n'
with open(path, 'w') as f:
    f.write(cleaned)
print("done")
PYEOF
  ok "Removed vibekit block from CLAUDE.md"
elif [[ -f "$CLAUDE_MD" ]]; then
  skip "CLAUDE.md exists but has no vibekit block"
else
  skip "No CLAUDE.md found"
fi

# ── 5. Remove .gitignore entries ──────────────────────────────────────────────
step ".gitignore"
GITIGNORE="$PROJECT_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]] && grep -q "vibekit" "$GITIGNORE"; then
  sed -i.bak '/# vibekit/,/\.db-wal/d' "$GITIGNORE"
  ok "Removed vibekit entries from .gitignore (backup: .gitignore.bak)"
else
  skip ".gitignore has no vibekit entries"
fi

# ── 6. Global uninstall (only with --global) ──────────────────────────────────
if [[ "$GLOBAL" == "true" ]]; then
  step "Global tools (--global)"

  if command -v rtk &>/dev/null; then
    brew uninstall rtk && ok "rtk uninstalled" || warn "Could not uninstall rtk via brew"
  else
    skip "rtk not installed"
  fi

  if python3 -c "import headroom" &>/dev/null; then
    pip uninstall headroom-ai -y --quiet && ok "headroom-ai uninstalled"
  else
    skip "headroom-ai not installed"
  fi

  # Remove llm-setup alias from shell profiles
  for PROFILE in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$PROFILE" ]] && grep -q "llm-setup" "$PROFILE"; then
      sed -i.bak '/llm-setup/d' "$PROFILE"
      ok "Removed llm-setup alias from $PROFILE"
    fi
  done
else
  echo ""
  warn "headroom and rtk are still installed globally."
  warn "To also remove them run: bash ~/git/vibekit/scripts/uninstall.sh --global"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================="
echo -e "${GREEN}  ✓ $PROJECT_NAME restored to normal Claude${NC}"
echo ""
echo "  Removed:"
echo "    · headroom proxy (stopped + ANTHROPIC_BASE_URL cleared)"
echo "    · .claude/skills/ (memstack)"
echo "    · CLAUDE.md vibekit blocks"
echo "    · .gitignore vibekit entries"
[[ "$GLOBAL" == "true" ]] && echo "    · rtk (brew)" && echo "    · headroom-ai (pip)"
echo ""
echo "  Restart Claude Code — it will behave as normal."
echo "============================================="
