---
name: setup
description: Setup scope_generator_mcp for a Flutter project. Downloads binary from GitHub releases and adds MCP config.
---

# Setup scope_generator_mcp

## Arguments

`$ARGUMENTS` — absolute path to Flutter project

## Steps

### 1. Download binary (if needed)

Check if `~/.local/bin/scope_generator_mcp` exists. If not:

```bash
mkdir -p ~/.local/bin
curl -L -o ~/.local/bin/scope_generator_mcp \
  https://github.com/Tembeon/tem_tools/releases/latest/download/scope_generator_mcp-macos
chmod +x ~/.local/bin/scope_generator_mcp
```

For Linux, use `scope_generator_mcp-linux` instead.

### 2. Update mcp.json

Read `~/.claude/mcp.json` (create if doesn't exist).

Add or update `scope_generator_mcp` entry:

```json
{
  "mcpServers": {
    "scope_generator_mcp": {
      "command": "/Users/<username>/.local/bin/scope_generator_mcp",
      "args": ["<project_path_from_arguments>"]
    }
  }
}
```

Use absolute path for command (expand `~`).

### 3. Done

Tell user to restart Claude Code to apply changes.
