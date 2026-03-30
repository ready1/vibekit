# How to Use headroom, rtk, and memstack While Vibe Coding with Claude

This guide is for developers using Claude Code to build things fast. These three tools keep your context window lean so Claude stays sharp across long sessions — fewer "I lost track of what we were doing" moments.

---

## Adding to an existing project

Already have Claude running in a project (e.g. `your-project`)? Two steps:

> **Windows users:** `setup-project.ps1` is included but **untested**. For a guaranteed working setup use WSL2 (`wsl --install -d Ubuntu`) and follow the macOS/Linux steps below. If you test it on Windows natively, please open an issue at [github.com/ready1/vibekit](https://github.com/ready1/vibekit/issues).

**Step 1 — clone vibekit once (skip if already done):**

**macOS / Linux:**
```bash
git clone https://github.com/ready1/vibekit ~/git/vibekit
chmod +x ~/git/vibekit/scripts/*.sh

# Optional alias so you never need to type the full path again
echo "alias llm-setup='bash ~/git/vibekit/scripts/setup-project.sh'" >> ~/.zshrc
source ~/.zshrc
```

**Windows (untested — WSL2 recommended instead):**
```powershell
git clone https://github.com/ready1/vibekit $HOME\git\vibekit
# Add alias to PowerShell profile
Add-Content $PROFILE 'function llm-setup { & "$HOME\git\vibekit\scripts\setup-project.ps1" }'
```

**Step 2 — run setup from inside your project:**

**macOS / Linux:**
```bash
cd ~/git/my-project-folder
llm-setup        # if you added the alias
# or
bash ~/git/vibekit/scripts/setup-project.sh
```

**Windows (untested):**
```powershell
cd $HOME\git\my-project-folder
llm-setup
# or
& "$HOME\git\vibekit\scripts\setup-project.ps1"
```

The script handles everything: installs/upgrades headroom and rtk globally, clones memstack into `.claude/skills/`, initialises the DB, wires rtk into the project, updates `.gitignore`, starts the headroom proxy, and patches `CLAUDE.md` with defensive instructions.

**Re-run any time** to pull updates — it skips steps already done and upgrades tools that are out of date.

**Sharing with your team:** commit `CLAUDE.md` to the repo. Any dev who pulls it and doesn't have the tools will see Claude warn them to run:
```bash
bash ~/git/vibekit/scripts/setup-project.sh
```

---

## The problem they solve

When you're vibe coding — letting Claude write, run, and iterate on code — Claude's context window fills up fast:

- `ls` on a big folder dumps 300 lines Claude doesn't need
- A failed test run pastes 2,000 lines of output
- You start session 3 of a project and Claude has no memory of session 1

These tools fix each of those problems.

---

## Tool 1 — rtk

**What it does:** Wraps shell commands and shrinks their output before it enters Claude's context.

Instead of `ls ./src` returning 300 lines of filenames, `rtk ls ./src` returns a compact tree. Instead of a full test run pasting every passing test, `rtk test npm test` shows failures only.

**How much it helps:** 50–85% smaller output on directory listings and git commands.

---

### Using rtk while vibe coding

The simplest approach: add a `CLAUDE.md` to your project telling Claude to always use `rtk`. Claude reads this file automatically at the start of every session.

```markdown
<!-- .claude/CLAUDE.md or CLAUDE.md in project root -->
## Shell commands
Always use rtk wrappers:
- `rtk ls` instead of `ls`
- `rtk grep` instead of `grep`
- `rtk git status` and `rtk git log` instead of plain git
- `rtk read <file>` to read files
- `rtk test <runner>` to run tests (shows failures only)
```

That's it. Claude will use rtk for every shell operation automatically.

**Common commands:**

```bash
# See what's in a directory (compact tree instead of flat list)
rtk ls ./src

# Search for code (results grouped by file, no repetitive headers)
rtk grep "useState" ./src

# Git status (clean one-liner summary)
rtk git status

# Git log (one line per commit)
rtk git log -n 20

# Run tests — only shows failures, skips passing output
rtk test npm test
rtk test pytest
rtk test cargo test

# Read a file (falls back to full content when Claude needs it)
rtk read src/index.ts
```

**When not to use it:**
- `rtk ls ~/Downloads` or any huge flat folder — rtk adds grouping overhead and can make output bigger, not smaller. Stick to project directories.
- You generally don't need `rtk read` for files you're actively editing — Claude will read those in full anyway.

---

## Tool 2 — headroom

**What it does:** Compresses JSON payloads and tool outputs before they go into Claude's context. When Claude runs a search that returns 100 results as JSON, headroom can shrink that by ~33% before Claude ever reads it.

It works at the Python level — you use it in your app code or agent pipeline, not as a shell command.

**How much it helps:** ~33% reduction on JSON arrays. Logs, code, and plain text pass through unchanged.

---

### Using headroom while vibe coding

**Option A — Zero code change: run the proxy**

Start headroom as a local proxy and point Claude's API calls at it. Every request gets automatically compressed.

```bash
# Terminal 1: start the proxy
headroom proxy --port 8787

# Terminal 2: tell your app to use the proxy
export ANTHROPIC_BASE_URL=http://localhost:8787

# Now run Claude Code or your app as normal — compression happens transparently
claude
```

**Option B — Wrap Claude Code directly**

```bash
headroom wrap claude
```

This intercepts Claude Code's tool outputs and compresses them before they enter context. Nothing else changes in your workflow.

**Option C — Use it in your own Python agent**

If you're vibe coding an AI agent or tool-calling script:

```python
from headroom import SmartCrusher, SmartCrusherConfig
import json

sc = SmartCrusher(SmartCrusherConfig())

# You got back a big JSON tool result (search, DB query, API response, etc.)
tool_output = json.dumps(your_results)

result = sc.crush(tool_output)

# Use the compressed version in your LLM messages
compressed = result.compressed if result.was_modified else tool_output
print(f"Saved {len(tool_output) - len(compressed)} chars | strategy: {result.strategy}")
```

**Option D — MCP server (Claude Code integration)**

Add headroom as an MCP server so Claude Code can call it as a tool directly:

```json
// ~/.claude/settings.json
{
  "mcpServers": {
    "headroom": {
      "command": "headroom",
      "args": ["mcp"]
    }
  }
}
```

Then in a session you can ask Claude: *"compress this tool output before processing it"* and it will call the headroom MCP tool.

**What gets compressed vs what doesn't:**

| Content type | Compressed? | Why |
|-------------|-------------|-----|
| JSON arrays (search results, DB rows, API lists) | Yes — ~33% | SmartCrusher summarises numeric sequences and deduplicates uniform items |
| Logs | No | Text passthrough — use rtk at the shell layer instead |
| Code files | No | Claude needs the full content |
| RAG document chunks | No | Prose passthrough |

---

## Tool 3 — memstack

**What it does:** Gives Claude a persistent memory across sessions. When you finish a coding session, memstack saves what you decided, what patterns you used, and what the project context was. Next session, Claude loads that memory back in — without you having to re-explain everything.

It also ships 77 specialist skills (security audits, deployment checklists, SEO, writing) that load automatically when relevant, rather than bloating every session with tools Claude doesn't need.

---

### Using memstack while vibe coding

**Setup (one-time per project):**

```bash
git clone https://github.com/cwinvestments/memstack .claude/skills
python3 .claude/skills/db/memstack-db.py init
```

That's it. The skills are now available to Claude Code automatically.

**During a session — saving memory:**

You don't have to do anything special. At the end of a session, you can ask Claude to save what was decided:

> *"Save today's session context to memstack — we switched to RS256 for JWT signing and moved token validation into middleware."*

Or save it yourself:

```bash
python3 .claude/skills/db/memstack-db.py add-insight '{"project":"my-app","type":"decision","content":"Use RS256 for JWT. Validate in middleware, not handlers. 15min access token expiry."}'
```

**At the start of a new session — loading memory:**

Ask Claude to recall past context:

> *"Search memstack for what we decided about authentication."*

Or use the built-in skill directly in Claude Code:

```
/memstack-search authentication
/memstack-search JWT
/memstack-search deployment
```

**Checking what's stored:**

```bash
python3 .claude/skills/db/memstack-db.py stats
# → {"sessions": 12, "insights": 47, "projects": 3, "db_size_kb": 88.0}

python3 .claude/skills/db/memstack-db.py search "JWT signing"
```

**The 77 skills — what they do:**

Skills are markdown prompt files that Claude loads contextually. You don't manage them manually. When you're working on deployment, the deployment skills load. When you're doing a security review, the security skills load.

Example skills available:
- `/security-audit` — OWASP checklist, secrets scanning, dependency review
- `/deploy-checklist` — pre-deployment safety checks
- `/db-review` — schema safety, migration checks
- `/write-docs` — API docs, changelogs, README generation
- `/code-review` — complexity, duplication, test coverage

Use them by typing the skill name in a Claude Code session.

---

## Putting it all together in a vibe coding session

Here's a typical session with all three tools active:

**1. Project CLAUDE.md (set once, applies every session):**

```markdown
## Shell commands
Use rtk for all shell ops: rtk ls, rtk grep, rtk git status/log, rtk test <runner>

## Memory
Project memory is in .claude/skills/db/memstack.db.
At the start of each session, search memstack for relevant context.
At the end of each session, save key decisions as insights.

## Context
Use headroom proxy (port 8787) if running as a standalone agent.
```

**2. Start a session:**

```bash
# Optional: start headroom proxy for automatic JSON compression
headroom proxy --port 8787 &

# Start Claude Code
claude
```

**3. First message to Claude at the start of a session:**

> *"Search memstack for context on this project before we start."*

Claude runs `/memstack-search` and loads what was decided last time — no re-explaining needed.

**4. During the session:**

Claude uses `rtk ls`, `rtk grep`, `rtk git` automatically (because of CLAUDE.md). Large JSON outputs get compressed by the headroom proxy.

**5. End of session:**

> *"Save today's session to memstack — summarise the key decisions we made."*

Claude writes a structured insight to the DB. Next session picks it up.

---

## Quick reference

| Situation | Tool | Command |
|-----------|------|---------|
| Claude wastes tokens listing directories | rtk | Add `rtk ls` to CLAUDE.md |
| Test output floods the context | rtk | `rtk test npm test` |
| JSON API/search results are too big | headroom | `headroom proxy` or `headroom wrap claude` |
| Claude forgets last session's decisions | memstack | `/memstack-search <topic>` |
| Want Claude to remember a decision | memstack | Ask Claude to save it, or use `add-insight` |
| Starting a greenfield project | all three | Run `install.sh`, add CLAUDE.md, init memstack |

---

## Installation reminder

```bash
# From this repo — installs all three tools
./scripts/install.sh

# Verify
headroom --version   # → headroom, version 0.5.10
rtk --version        # → rtk 0.34.1
python3 memstack/db/memstack-db.py stats
```

---

## Uninstalling — go back to normal Claude

### Remove from one project only

```bash
cd ~/git/my-project-folder   # the project to clean up
bash ~/git/vibekit/scripts/uninstall.sh
```

This removes everything added to the project and restores Claude to default:

| What | Action |
|------|--------|
| headroom proxy | Stopped, `ANTHROPIC_BASE_URL` removed from shell profile |
| `.claude/skills/` (memstack) | Deleted — **memory exported to `memstack-export-<date>.md` first** |
| `CLAUDE.md` | vibekit blocks removed, rest of file untouched |
| `.gitignore` | vibekit entries removed |
| headroom + rtk binaries | Left installed globally (still available for other projects) |

Restart Claude Code after running — it will behave as normal.

### Remove tools globally too

```bash
bash ~/git/vibekit/scripts/uninstall.sh --global
```

Also uninstalls `headroom-ai` (pip) and `rtk` (brew) from the machine entirely, and removes the `llm-setup` shell alias.

> **Note on memstack memory:** Before deleting `.claude/skills/`, the script exports all stored insights and sessions to a markdown file in the project root. Keep this if you want a record of decisions made during vibe coding sessions.
