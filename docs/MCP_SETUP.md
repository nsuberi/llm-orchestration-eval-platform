# MCP Setup for Cursor (Jira + GitHub + Shell/FS)

You want Cursor's agent ("Conductor") to:
- read/write Jira issues,
- open/track PRs on GitHub,
- run shell/git commands (worktrees, tests),
- read/write files.

## 1) Configure MCP servers in Cursor

Open Cursor → Settings → MCP (or your MCP client config). Add servers for:

### A) Shell & FS
These let the agent run git/npm/pytest and edit files.
```json
{
  "mcpServers": {
    "fs": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem"] },
    "shell": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-shell"] }
  }
}



