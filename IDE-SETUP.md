# IDE Setup Guide — Windsurf & VS Code

How to use headroom, rtk, and memstack when vibe coding inside **Windsurf** or **VS Code** (Cline / Continue).

---

## Compatibility at a glance

| | Claude Code CLI | Windsurf | VS Code + Cline | VS Code + Continue |
|---|:---:|:---:|:---:|:---:|
| **rtk** — native init | ✅ hook | ✅ `.windsurfrules` | ✅ `.clinerules` | ⚠️ manual |
| **headroom** — proxy | ✅ | ⚠️ no base URL override | ✅ custom base URL | ✅ custom base URL |
| **headroom** — MCP | ✅ | ✅ | ✅ | ✅ agent mode only |
| **memstack** — skills | ✅ `.claude/skills` | ⚠️ manual copy | ⚠️ manual copy | ⚠️ manual copy |
| **memstack** — CLAUDE.md | ✅ auto-read | ❌ not read | ❌ not read | ❌ not read |
| **memstack** — DB | ✅ | ✅ via terminal | ✅ via terminal | ✅ via terminal |
| Runs shell commands | ✅ | ✅ Cascade terminal | ✅ agentic loop | ✅ agent mode |

**Bottom line:**
- **rtk** works great in all three — one command sets it up per IDE
- **headroom** works everywhere via the proxy; MCP works in all three
- **memstack** needs a small workaround in Windsurf and VS Code because they don't read `CLAUDE.md` or `.claude/skills/` — use their own rules files instead

---

## RTK

RTK has first-class support for both IDEs via `rtk init`.

### Windsurf

```bash
# Run once in your project root
rtk init --agent windsurf
```

Creates `.windsurfrules` in the project root. Cascade reads this and knows to prefix shell commands with `rtk`.

Verify it worked — Cascade will now run `rtk ls ./src` instead of `ls ./src` automatically.

---

### VS Code + Cline

```bash
# Run once in your project root
rtk init --agent cline
```

Creates `.clinerules` in the project root. Cline reads `.clinerules` automatically at session start.

---

### VS Code + Continue

Continue does not have an `rtk init` target yet. Add the instruction manually to Continue's rules:

```bash
mkdir -p .continue/rules
cat > .continue/rules/rtk.md << 'EOF'
## Shell commands
Use rtk wrappers for all shell operations:
- `rtk ls` instead of `ls`
- `rtk grep` instead of `grep`
- `rtk git status` and `rtk git log` instead of plain git
- `rtk read <file>` to read files
- `rtk test <runner>` to run tests (failures only)
EOF
```

---

## headroom

### Option A — Proxy (recommended for Windsurf)

Windsurf routes API calls through Codeium's infrastructure even with BYOK, so you can't set `ANTHROPIC_BASE_URL` directly. The workaround is to run headroom in proxy mode and use a custom model provider endpoint.

```bash
# Terminal: start headroom proxy
headroom proxy --port 8787
```

Then in Windsurf Settings → AI → Custom Model Provider, set:
- **Endpoint URL:** `http://localhost:8787`
- **Model:** `claude-sonnet-4-6` (or whichever Claude model you use)
- **API Key:** your Anthropic key

All Cascade requests now flow through headroom automatically.

---

### Option B — Proxy (VS Code + Cline or Continue)

Both Cline and Continue support a custom base URL natively.

**Cline:**

In Cline settings, switch provider to **OpenAI Compatible** and set:
- Base URL: `http://localhost:8787`
- API Key: your Anthropic key
- Model: `claude-sonnet-4-6`

Or set it in VS Code `settings.json`:
```json
{
  "cline.openAiCompatible.baseUrl": "http://localhost:8787"
}
```

**Continue:**

In `.continue/config.yaml`:
```yaml
models:
  - title: Claude via headroom
    provider: openai
    model: claude-sonnet-4-6
    apiBase: http://localhost:8787
    apiKey: your-anthropic-key
```

---

### Option C — MCP server (all three IDEs)

Run headroom as an MCP server so the AI can call it as a tool directly.

**Windsurf** — edit `~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "headroom": {
      "command": "headroom",
      "args": ["mcp"]
    }
  }
}
```

**VS Code + Cline** — open Cline panel → MCP Servers tab → Configure, then add:

```json
{
  "headroom": {
    "command": "headroom",
    "args": ["mcp"],
    "disabled": false,
    "alwaysAllow": []
  }
}
```

**VS Code + Continue** — create `.continue/mcpServers/headroom.yaml`:

```yaml
name: headroom
command: headroom
args:
  - mcp
```

> Note: Continue MCP tools only work in **agent mode**, not in chat mode.

---

## memstack

memstack was built for Claude Code CLI — it reads `.claude/skills/` and `CLAUDE.md` automatically. Windsurf and VS Code don't read those paths, but you can get the same result by dropping the instructions into each IDE's own rules format.

### Windsurf

Create a workspace rule file that mirrors what `CLAUDE.md` would tell Claude Code:

```bash
mkdir -p .windsurf/rules

cat > .windsurf/rules/memstack.md << 'EOF'
## Session memory
This project uses memstack for persistent memory stored in memstack/db/memstack.db.

At the start of every session:
1. Run: python3 memstack/db/memstack-db.py search "<current topic>"
2. Load the results as context before doing anything else.

At the end of every session:
1. Ask the user to confirm key decisions made
2. Save each one: python3 memstack/db/memstack-db.py add-insight '<json>'

## Saving an insight (JSON format)
{"project": "project-name", "type": "decision", "content": "What was decided and why."}

## Searching memory
python3 memstack/db/memstack-db.py search "your query"
python3 memstack/db/memstack-db.py stats
EOF
```

Windsurf rule files have a **6,000 character limit** per file and **12,000 characters total** across all rules. Keep them concise.

---

### VS Code + Cline

```bash
mkdir -p .clinerules

cat > .clinerules/memstack.md << 'EOF'
## Session memory (memstack)
Memory DB: memstack/db/memstack.db

Start of session: search for relevant context
  python3 memstack/db/memstack-db.py search "<topic>"

End of session: save key decisions
  python3 memstack/db/memstack-db.py add-insight '{"project":"<name>","type":"decision","content":"<what was decided>"}'

Check stats:
  python3 memstack/db/memstack-db.py stats
EOF
```

Cline reads all files in `.clinerules/` automatically.

---

### VS Code + Continue

```bash
mkdir -p .continue/rules

cat > .continue/rules/memstack.md << 'EOF'
## Session memory (memstack)
At session start, search: python3 memstack/db/memstack-db.py search "<topic>"
At session end, save: python3 memstack/db/memstack-db.py add-insight '{"project":"<name>","type":"decision","content":"<summary>"}'
EOF
```

---

### memstack DB — works identically in all IDEs

The actual DB operations are just Python CLI calls. These work in any terminal inside any IDE:

```bash
# Search past context
python3 memstack/db/memstack-db.py search "authentication"

# Save a decision
python3 memstack/db/memstack-db.py add-insight \
  '{"project":"my-app","type":"decision","content":"Use RS256 for JWT. Validate in middleware."}'

# View stats
python3 memstack/db/memstack-db.py stats

# Export all memory to markdown
python3 memstack/db/memstack-db.py export-md my-app
```

---

## Full setup per IDE — step by step

### Windsurf from scratch

```bash
# 1. Install tools
./scripts/install.sh

# 2. Set up rtk for Windsurf
rtk init --agent windsurf

# 3. Set up memstack rules
mkdir -p .windsurf/rules
# paste the memstack.md rule from above

# 4. Add headroom MCP to Windsurf
# Edit ~/.codeium/windsurf/mcp_config.json (add "headroom" entry from above)

# 5. Init memstack DB
python3 memstack/db/memstack-db.py init

# 6. Start headroom proxy (optional — for full JSON compression)
headroom proxy --port 8787 &
# Then set Custom Model Provider in Windsurf Settings → AI
```

---

### VS Code + Cline from scratch

```bash
# 1. Install tools
./scripts/install.sh

# 2. Set up rtk for Cline
rtk init --agent cline

# 3. Set up memstack rules
mkdir -p .clinerules
# paste the memstack.md rule from above

# 4. Add headroom MCP to Cline
# Open Cline panel → MCP Servers → Configure (add headroom entry from above)

# 5. Init memstack DB
python3 memstack/db/memstack-db.py init

# 6. Start headroom proxy (optional)
headroom proxy --port 8787 &
# Then in Cline settings set provider to OpenAI Compatible, Base URL: http://localhost:8787
```

---

## What still works best in Claude Code CLI

| Feature | Claude Code CLI | Windsurf / VS Code |
|---------|:---------:|:---------:|
| CLAUDE.md auto-loaded | ✅ | ❌ (use IDE rules files) |
| `.claude/skills/` auto-loaded | ✅ | ❌ (paste skills manually if needed) |
| rtk via hook (transparent) | ✅ PreToolUse hook | ⚠️ rules-based (AI must follow instruction) |
| memstack skills (77 skills) | ✅ auto-contextual | ⚠️ manual invocation |
| headroom wrap | ✅ `headroom wrap claude` | ❌ not applicable |

The 77 memstack skills (security, deploy, SEO, etc.) are designed around Claude Code's skill-loading system. In Windsurf or Cline you can still use them by pasting the skill content into a prompt or rules file, but they won't load contextually.

For heavy vibe coding sessions, **Claude Code CLI gives you the most seamless experience** with all three tools. Windsurf and VS Code + Cline are close behind — rtk and the headroom proxy work well; memstack requires a small one-time rules setup.
