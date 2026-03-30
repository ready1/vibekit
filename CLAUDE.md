# CLAUDE.md — vibekit

Instructions for Claude Code when working in this project.

## Project purpose

Reproducible install + benchmark suite for three LLM token-efficiency tools:
- **headroom** — compresses JSON tool outputs before they enter the LLM context
- **rtk** — trims CLI command output for AI agents
- **memstack** — persistent session memory + skill loading for Claude Code

## Shell commands

Prefer rtk wrappers to keep your own context lean:

```
rtk ls ./scripts          # directory listings
rtk grep "pattern" .      # code search
rtk git status            # git status
rtk git log -n 20         # git log
rtk read scripts/file.py  # file reads (falls back to full when needed)
```

## Running benchmarks

Always activate the venv first:

```bash
source .venv/bin/activate
python3 scripts/benchmark_headroom.py
./scripts/benchmark_rtk.sh
python3 scripts/benchmark_memstack.py
```

For machine-readable output add `--json` to any script.

## Project layout

```
scripts/
  install.sh               # fresh install of all three tools
  benchmark_headroom.py    # headroom SmartCrusher token reduction
  benchmark_rtk.sh         # rtk CLI byte reduction
  benchmark_memstack.py    # memstack DB latency
memstack/                  # git-ignored — cloned by install.sh
.venv/                     # git-ignored — created by install.sh
```

## Key facts

- Python 3.10+ required; venv lives at `.venv/`
- `memstack/` is a git-ignored clone of cwinvestments/memstack — don't edit it directly
- Benchmark scripts are self-contained; they create their own test data
- `install.sh --slim` skips PyTorch (~50 MB vs ~4 GB)

## What NOT to do

- Don't commit `.venv/`, `memstack/`, or `*.db` files (all in .gitignore)
- Don't edit files inside `memstack/` — run `git -C memstack pull` to update it
- Don't run `pip install` outside the venv
