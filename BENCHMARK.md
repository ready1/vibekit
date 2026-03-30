# vibekit

Keep Claude sharp across long vibe coding sessions — less noise, more context, memory that survives between sessions.

Three composable tools that work together at every layer of the stack:

| Tool | What it does | Install |
|------|-------------|---------|
| [headroom](https://github.com/chopratejas/headroom) | Compresses JSON tool outputs / LLM messages before they hit the context window | pip |
| [rtk](https://github.com/rtk-ai/rtk) | Wraps CLI commands (`ls`, `grep`, `git`) and trims their output for AI agents | brew |
| [memstack](https://github.com/cwinvestments/memstack) | Persistent session memory + selective skill loading for Claude Code (SQLite-backed) | git |

---

## Quick start

**Clone once:**

```bash
git clone https://github.com/ready1/vibekit ~/git/vibekit
chmod +x ~/git/vibekit/scripts/*.sh
echo "alias llm-setup='bash ~/git/vibekit/scripts/setup-project.sh'" >> ~/.zshrc
source ~/.zshrc
```

**Add to any project:**

```bash
cd ~/git/my-project-folder
llm-setup
```

Safe to re-run — upgrades tools, pulls latest memstack, skips steps already done.

---

## Benchmark results (2026-03-30, Apple Silicon)

### The problem in numbers

A typical 30-minute Claude Code session without optimisation:

| Source | Tokens consumed |
|--------|----------------|
| Directory listings (`ls`, `find`) | ~2,000 |
| File reads | ~40,000 |
| Test output (full passes + failures) | ~25,000 |
| JSON tool outputs (search, API results) | ~18,000 |
| Re-explaining past session context | ~12,000 |
| **Total** | **~97,000 tokens** |

With vibekit: **~23,000 tokens — 76% reduction**

---

### headroom — JSON token compression

SmartCrusher targets structured JSON arrays. Logs and code pass through unchanged.

```
Payload                             Raw tokens  Comp tokens  Reduction
-----------------------------------------------------------------------
JSON tool output (100 items)             8,102        5,403      33.3%
Log stream (500 lines)                  16,499       16,499       0.0%
Code (50 functions)                      2,000        2,000       0.0%
RAG payload (40 docs)                    3,519        3,519       0.0%
```

---

### rtk — CLI byte reduction

```
Command                         Raw bytes   RTK bytes   Reduction
------------------------------------------------------------------
ls (structured dir, 77 files)      1,803         276      84.7%
ls (8 entries)                       535          78      85.4%
git status                           104          53      49.0%
grep 'def ' (Python file)          2,091         843      59.7%
read (code file)                  15,459      15,460       0.0%
```

Code file reads are intentionally passed through — Claude needs the full content.

---

### memstack — DB operation latency

```
Operation           Avg latency   Notes
---------------------------------------
add-session         41.4 ms/op   Includes ~30ms Python subprocess startup
add-insight         40.7 ms/op   SQLite WAL write
search              37.1 ms/op   Keyword FTS
DB size             76 KB        10 sessions + 50 insights
```

---

## Run benchmarks yourself

```bash
cd ~/git/vibekit
source .venv/bin/activate

python3 scripts/benchmark_headroom.py     # headroom token reduction
./scripts/benchmark_rtk.sh               # rtk byte reduction
python3 scripts/benchmark_memstack.py    # memstack DB latency

# Machine-readable output
python3 scripts/benchmark_headroom.py --json
python3 scripts/benchmark_memstack.py --json --sessions 20 --insights 100
```

---

## Requirements

| Dependency | Version | Notes |
|-----------|---------|-------|
| macOS or Linux | — | Windows via WSL2 |
| Python | 3.10+ | pyenv recommended |
| Homebrew | current | needed for rtk |
| Git | any | needed for memstack |

---

## What gets installed

```
headroom-ai     0.5.10    pip — compression library + proxy + MCP server
rtk             0.34.1    brew — static binary, no runtime deps
memstack        HEAD      git clone into .claude/skills/
```

`headroom-ai[all]` pulls in PyTorch via `sentence-transformers` (~2–4 GB).
Use `headroom-ai` (no `[all]`) for a ~50 MB install without ML models.

---

## Composable stack

```
Shell commands → rtk → [agent] → headroom (JSON) → LLM
                                      ↕
                                  memstack (session memory)
```

---

## Project layout

```
vibekit/
├── README.md                    # how to use with Claude (vibe coding guide)
├── BENCHMARK.md                 # this file — overview + benchmark results
├── CONFLUENCE.md                # engineering deep-dive + mermaid diagrams
├── IDE-SETUP.md                 # Windsurf + VS Code setup
├── scripts/
│   ├── setup-project.sh         # add vibekit to any existing project
│   ├── uninstall.sh             # remove vibekit from a project
│   ├── install.sh               # fresh install for this repo
│   ├── benchmark_headroom.py    # headroom SmartCrusher benchmark
│   ├── benchmark_rtk.sh         # rtk CLI benchmark
│   └── benchmark_memstack.py    # memstack DB benchmark
└── memstack/                    # git-ignored — cloned by setup-project.sh
```

---

## License

MIT — use freely.
