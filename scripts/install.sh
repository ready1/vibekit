#!/usr/bin/env bash
# =============================================================================
# install.sh — Fresh setup for vibekit
# Installs: headroom-ai, rtk, memstack
#
# Usage:
#   ./scripts/install.sh          # full install (headroom[all] with ML models)
#   ./scripts/install.sh --slim   # slim install (headroom without PyTorch)
# =============================================================================

set -euo pipefail

SLIM=false
for arg in "$@"; do
  [[ "$arg" == "--slim" ]] && SLIM=true
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
MEMSTACK_DIR="$ROOT_DIR/memstack"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $*${NC}"; }

echo "============================================="
echo "  vibekit — Fresh Install"
echo "============================================="
[[ "$SLIM" == "true" ]] && warn "Slim mode: skipping ML models (no sentence-transformers / PyTorch)"

# ── 1. Check OS ───────────────────────────────────────────────────────────────
step "Checking OS"
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Darwin) ok "macOS ($ARCH)" ;;
  Linux)  ok "Linux ($ARCH)" ;;
  *)      err "Unsupported OS: $OS. Use macOS, Linux, or WSL2." ;;
esac

# ── 2. Check Python ──────────────────────────────────────────────────────────
step "Checking Python"
if ! command -v python3 &>/dev/null; then
  err "python3 not found. Install via pyenv:\n  brew install pyenv && pyenv install 3.10.14 && pyenv global 3.10.14"
fi
PY_VER=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
if [[ "$PY_MAJOR" -lt 3 || ("$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 10) ]]; then
  err "Python 3.10+ required (found $PY_VER). Run: pyenv install 3.10.14 && pyenv global 3.10.14"
fi
ok "Python $PY_VER"

# ── 3. Check Homebrew ────────────────────────────────────────────────────────
step "Checking Homebrew"
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found — installing now..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
ok "Homebrew $(brew --version | head -1 | cut -d' ' -f2)"

# ── 4. Check Git ─────────────────────────────────────────────────────────────
step "Checking Git"
if ! command -v git &>/dev/null; then
  err "git not found. On macOS: xcode-select --install. On Linux: sudo apt install git"
fi
ok "$(git --version)"

# ── 5. Create Python venv ────────────────────────────────────────────────────
step "Setting up Python virtual environment"
if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
  ok "Created venv at $VENV_DIR"
else
  ok "venv already exists at $VENV_DIR"
fi

# Activate venv for remaining steps
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip --quiet
ok "pip $(pip --version | cut -d' ' -f2)"

# ── 6. Install headroom ───────────────────────────────────────────────────────
step "Installing headroom-ai"
if python3 -c "import headroom" &>/dev/null; then
  CURRENT=$(python3 -c "import headroom; print(headroom.__version__)" 2>/dev/null || echo "unknown")
  ok "headroom already installed (v$CURRENT) — skipping"
else
  if [[ "$SLIM" == "true" ]]; then
    pip install headroom-ai --quiet
  else
    echo "  Installing headroom-ai[all] — this includes PyTorch (~2-4 GB, may take a while)..."
    pip install "headroom-ai[all]" --quiet
  fi
  VERSION=$(python3 -c "import headroom; print(headroom.__version__)" 2>/dev/null || headroom --version | grep -o '[0-9.]*')
  ok "headroom-ai $VERSION installed"
fi

# Also install tiktoken for benchmarking
pip install tiktoken --quiet
ok "tiktoken installed"

# ── 7. Install rtk ────────────────────────────────────────────────────────────
step "Installing rtk"
if command -v rtk &>/dev/null; then
  ok "rtk already installed ($(rtk --version))"
else
  brew install rtk
  ok "rtk $(rtk --version) installed"
fi

# ── 8. Clone memstack ─────────────────────────────────────────────────────────
step "Setting up memstack"
if [[ -d "$MEMSTACK_DIR/.git" ]]; then
  ok "memstack already cloned — pulling latest"
  git -C "$MEMSTACK_DIR" pull --quiet
else
  git clone https://github.com/cwinvestments/memstack "$MEMSTACK_DIR" --quiet
  ok "memstack cloned to $MEMSTACK_DIR"
fi

# Init the SQLite DB
INIT_OUT=$(python3 "$MEMSTACK_DIR/db/memstack-db.py" init 2>&1)
if echo "$INIT_OUT" | grep -q '"ok": true'; then
  ok "memstack DB initialised"
else
  warn "memstack DB init output: $INIT_OUT"
fi

# Optional: semantic search
if [[ "$SLIM" != "true" ]]; then
  step "Installing optional memstack semantic search deps"
  pip install lancedb sentence-transformers --quiet && ok "lancedb + sentence-transformers installed" \
    || warn "Could not install lancedb/sentence-transformers — keyword search only"
fi

# ── 9. Verification ───────────────────────────────────────────────────────────
step "Verification"
PASS=0; FAIL=0

verify() {
  local name="$1"; local cmd="$2"
  if result=$(eval "$cmd" 2>&1); then
    ok "$name: $result"
    ((PASS++))
  else
    warn "FAIL: $name"
    ((FAIL++))
  fi
}

verify "headroom CLI"      "headroom --version"
verify "headroom import"   "python3 -c 'from headroom import SmartCrusher; print(\"SmartCrusher OK\")'"
verify "rtk CLI"           "rtk --version"
verify "tiktoken"          "python3 -c 'import tiktoken; print(tiktoken.__version__)'"
verify "memstack DB"       "python3 $MEMSTACK_DIR/db/memstack-db.py stats | python3 -c \"import sys,json; d=json.load(sys.stdin); print(f'DB OK ({d[\\\"db_path\\\"]})')\""

echo ""
echo "============================================="
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${GREEN}  All checks passed ($PASS/$((PASS+FAIL)))${NC}"
  echo ""
  echo "  Next steps:"
  echo "    source .venv/bin/activate"
  echo "    python3 scripts/benchmark_headroom.py"
  echo "    ./scripts/benchmark_rtk.sh"
  echo "    python3 scripts/benchmark_memstack.py"
else
  echo -e "${YELLOW}  $PASS passed, $FAIL failed — check warnings above${NC}"
fi
echo "============================================="
