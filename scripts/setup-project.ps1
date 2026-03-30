# =============================================================================
# setup-project.ps1 — Add vibekit to any existing project (Windows)
#
# ⚠️  UNTESTED ON WINDOWS — community contributions welcome.
#     Verified on: macOS/Linux via setup-project.sh
#     For a guaranteed working setup on Windows, use WSL2 instead:
#       wsl --install -d Ubuntu
#       then run: bash ~/git/vibekit/scripts/setup-project.sh
#
# Usage (from inside your project in PowerShell):
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned  # run once if needed
#   & "$HOME\git\vibekit\scripts\setup-project.ps1"
#
# Or add a global alias to your PowerShell profile:
#   Add-Content $PROFILE 'function llm-setup { & "$HOME\git\vibekit\scripts\setup-project.ps1" }'
#   Then just run: llm-setup
# =============================================================================

$ErrorActionPreference = "Stop"

# ── Colours ───────────────────────────────────────────────────────────────────
function ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function skip { param($msg) Write-Host "  [ · ] $msg" -ForegroundColor Cyan }
function warn { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function err  { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red; exit 1 }
function step { param($msg) Write-Host "`n> $msg" -ForegroundColor Yellow }

$TOOLS_DIR   = Split-Path -Parent $PSScriptRoot
$PROJECT_DIR = (Get-Location).Path
$PROJECT_NAME = Split-Path -Leaf $PROJECT_DIR

Write-Host ""
Write-Host "=============================================" -ForegroundColor White
Write-Host "  vibekit — Project Setup (Windows)"
Write-Host "  ⚠  UNTESTED — use WSL2 for verified setup" -ForegroundColor Yellow
Write-Host "  Project : $PROJECT_NAME"
Write-Host "  Path    : $PROJECT_DIR"
Write-Host "=============================================" -ForegroundColor White

# ── Sanity check ──────────────────────────────────────────────────────────────
if ($PROJECT_DIR -eq $TOOLS_DIR) {
    err "Run this from your project directory, not from inside vibekit."
}

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
step "Checking prerequisites"

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    err "Python not found. Install from https://python.org (check 'Add to PATH')"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    err "Git not found. Install from https://git-scm.com"
}
ok "python, git"

# Check for cargo (needed for rtk on Windows)
$HAS_CARGO = [bool](Get-Command cargo -ErrorAction SilentlyContinue)
if (-not $HAS_CARGO) {
    warn "cargo not found — rtk will be installed via pre-built binary instead"
}

# ── 2. headroom — install or upgrade ─────────────────────────────────────────
step "headroom"
$headroomInstalled = python -c "import headroom" 2>$null
if ($LASTEXITCODE -eq 0) {
    $current = python -c "import headroom; print(headroom.__version__)" 2>$null
    pip install --upgrade "headroom-ai[all]" --quiet 2>$null
    $new = python -c "import headroom; print(headroom.__version__)" 2>$null
    if ($current -ne $new) {
        ok "headroom upgraded $current -> $new"
    } else {
        skip "headroom already up to date ($current)"
    }
} else {
    Write-Host "  Installing headroom-ai[all] (includes PyTorch, may take a few minutes)..."
    pip install "headroom-ai[all]" --quiet 2>$null
    ok "headroom installed"
}

# Resolve headroom binary path
$HEADROOM_BIN = (Get-Command headroom -ErrorAction SilentlyContinue)?.Source
if (-not $HEADROOM_BIN) {
    $HEADROOM_BIN = "$env:APPDATA\Python\Scripts\headroom.exe"
}

# ── 3. rtk — install or upgrade ───────────────────────────────────────────────
step "rtk"
if (Get-Command rtk -ErrorAction SilentlyContinue) {
    $rtkVer = rtk --version 2>$null
    skip "rtk already installed ($rtkVer)"
} elseif ($HAS_CARGO) {
    Write-Host "  Installing rtk via cargo (this may take a few minutes)..."
    cargo install --git https://github.com/rtk-ai/rtk --quiet
    ok "rtk installed via cargo"
} else {
    # Fallback: download pre-built binary
    $rtkUrl = "https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-pc-windows-msvc.exe"
    $rtkDest = "$env:USERPROFILE\.local\bin\rtk.exe"
    New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null
    Write-Host "  Downloading rtk binary..."
    Invoke-WebRequest -Uri $rtkUrl -OutFile $rtkDest -ErrorAction SilentlyContinue
    if (Test-Path $rtkDest) {
        ok "rtk binary downloaded to $rtkDest"
        warn "Add $env:USERPROFILE\.local\bin to your PATH to use rtk"
    } else {
        warn "Could not download rtk binary — install manually from https://github.com/rtk-ai/rtk"
    }
}

# ── 4. memstack — clone or update ─────────────────────────────────────────────
step "memstack"
$MEMSTACK_DIR = Join-Path $PROJECT_DIR ".claude\skills"

if (Test-Path (Join-Path $MEMSTACK_DIR ".git")) {
    git -C $MEMSTACK_DIR pull --quiet
    $hash = git -C $MEMSTACK_DIR rev-parse --short HEAD
    skip "memstack updated ($hash)"
} else {
    New-Item -ItemType Directory -Force -Path (Join-Path $PROJECT_DIR ".claude") | Out-Null
    git clone https://github.com/cwinvestments/memstack $MEMSTACK_DIR --quiet
    ok "memstack cloned"
}

$initResult = python "$MEMSTACK_DIR\db\memstack-db.py" init 2>&1
if ($initResult -match '"ok": true') {
    ok "memstack DB ready"
} else {
    warn "memstack DB init: $initResult"
}

# ── 5. rtk — wire into project ────────────────────────────────────────────────
step "rtk project hook"
if (Get-Command rtk -ErrorAction SilentlyContinue) {
    $env:RTK_TELEMETRY_DISABLED = "1"
    echo "" | rtk init -g 2>$null
    ok "rtk hook registered"

    # Auto-update ~/.claude/settings.json
    $SETTINGS = Join-Path $env:USERPROFILE ".claude\settings.json"
    $RTK_HOOK = Join-Path $env:USERPROFILE ".claude\hooks\rtk-rewrite.sh"

    if (Test-Path $RTK_HOOK) {
        $settingsDir = Split-Path $SETTINGS
        New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null

        if (Test-Path $SETTINGS) {
            $settings = Get-Content $SETTINGS | ConvertFrom-Json
        } else {
            $settings = @{}
        }

        # Add PreToolUse hook if not present
        $hookEntry = @{ type = "command"; command = $RTK_HOOK }
        $matcher   = @{ matcher = "Bash"; hooks = @($hookEntry) }

        if (-not $settings.hooks) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue @{} }
        if (-not $settings.hooks.PreToolUse) { $settings.hooks | Add-Member -NotePropertyName PreToolUse -NotePropertyValue @() }

        $alreadySet = $settings.hooks.PreToolUse | Where-Object { $_.hooks.command -eq $RTK_HOOK }
        if (-not $alreadySet) {
            $settings.hooks.PreToolUse += $matcher
            $settings | ConvertTo-Json -Depth 10 | Set-Content $SETTINGS
            ok "settings.json updated with rtk hook"
        } else {
            skip "rtk hook already in settings.json"
        }
    }
} else {
    warn "rtk not in PATH — skipping hook setup"
}

# ── 6. .gitignore ─────────────────────────────────────────────────────────────
step ".gitignore"
$GITIGNORE = Join-Path $PROJECT_DIR ".gitignore"
$MARKER = "# vibekit"

if ((Test-Path $GITIGNORE) -and (Select-String -Path $GITIGNORE -Pattern "vibekit" -Quiet)) {
    skip ".gitignore already updated"
} else {
    Add-Content $GITIGNORE "`n# vibekit`n.claude/skills/db/*.db`n.claude/skills/db/*.db-shm`n.claude/skills/db/*.db-wal"
    ok ".gitignore updated"
}

# ── 7. headroom proxy ─────────────────────────────────────────────────────────
step "headroom proxy"

# Set ANTHROPIC_BASE_URL persistently
$existing = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")
if ($existing -eq "http://localhost:8787") {
    skip "ANTHROPIC_BASE_URL already set"
} else {
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://localhost:8787", "User")
    $env:ANTHROPIC_BASE_URL = "http://localhost:8787"
    ok "ANTHROPIC_BASE_URL set as user environment variable"
}

# Start proxy if not already running
$proxyRunning = netstat -ano | Select-String ":8787" | Select-String "LISTENING"
if ($proxyRunning) {
    skip "headroom proxy already running on :8787"
} elseif ($HEADROOM_BIN -and (Test-Path $HEADROOM_BIN)) {
    Start-Process -FilePath $HEADROOM_BIN -ArgumentList "proxy --port 8787" -WindowStyle Hidden
    Start-Sleep -Seconds 1
    $proxyRunning = netstat -ano | Select-String ":8787" | Select-String "LISTENING"
    if ($proxyRunning) {
        ok "headroom proxy started on :8787"
    } else {
        warn "headroom proxy did not start — run manually: headroom proxy --port 8787"
    }
} else {
    warn "headroom binary not found — run manually: headroom proxy --port 8787"
}

# ── 8. CLAUDE.md ──────────────────────────────────────────────────────────────
step "CLAUDE.md"
$CLAUDE_MD = Join-Path $PROJECT_DIR "CLAUDE.md"
$MARKER = "## Shell commands (vibekit)"

if ((Test-Path $CLAUDE_MD) -and (Select-String -Path $CLAUDE_MD -Pattern "vibekit" -Quiet)) {
    skip "CLAUDE.md already configured"
} else {
    $claudeContent = @"

## Shell commands (vibekit)
Before using rtk, verify it is installed: where rtk
If installed, use rtk for all shell ops: rtk ls, rtk grep, rtk git status/log, rtk test <runner>
If not installed, fall back to standard commands and remind the user to run: vibekit\scripts\setup-project.ps1

## Session memory (vibekit)
Before using memstack, verify it exists: Test-Path .claude\skills\db\memstack-db.py
If available:
  - Session start: python .claude\skills\db\memstack-db.py search "<topic>"
  - Session end: python .claude\skills\db\memstack-db.py add-insight '{\"project\":\"$PROJECT_NAME\",\"type\":\"decision\",\"content\":\"<what was decided>\"}'
If not available, remind the user to run: vibekit\scripts\setup-project.ps1
"@
    Add-Content $CLAUDE_MD $claudeContent
    ok "CLAUDE.md updated"
}

# ── Done ──────────────────────────────────────────────────────────────────────
$headroomVer = python -c "import headroom; print(headroom.__version__)" 2>$null
$rtkVer = (Get-Command rtk -ErrorAction SilentlyContinue) ? (rtk --version) : "not in PATH"
$memstackHash = git -C $MEMSTACK_DIR rev-parse --short HEAD 2>$null

Write-Host ""
Write-Host "=============================================" -ForegroundColor White
Write-Host "  ✓ $PROJECT_NAME is ready" -ForegroundColor Green
Write-Host ""
Write-Host "  headroom  $headroomVer"
Write-Host "  rtk       $rtkVer"
Write-Host "  memstack  $memstackHash"
Write-Host "  proxy     http://localhost:8787"
Write-Host ""
Write-Host "  ⚠  This script is UNTESTED on Windows." -ForegroundColor Yellow
Write-Host "     If something broke, please open an issue:" -ForegroundColor Yellow
Write-Host "     https://github.com/ready1/vibekit/issues" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Restart Claude Code to pick up the new CLAUDE.md."
Write-Host "=============================================" -ForegroundColor White
