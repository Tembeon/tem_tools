# scope_generator_mcp

MCP server for [scope_generator](../scope_generator). Lets Claude generate Scopes via tool calls.

## Install

```bash
dart compile exe bin/scope_generator_mcp.dart -o scope_generator_mcp
```

## Setup

**~/.claude/mcp.json:**
```json
{
  "mcpServers": {
    "scope_generator_mcp": {
      "command": "/path/to/scope_generator_mcp",
      "args": ["/path/to/flutter/project"]
    }
  }
}
```

One server = one project.

**Project needs scope_generator** (`analysis_options.yaml`):
```yaml
plugins:
  scope_generator:
    git:
      url: https://github.com/Tembeon/tem_tools.git
      path: scope_generator
      ref: 2025.01.09
```

## Tools

| Tool | Description |
|------|-------------|
| `generate_scope` | Generate InheritedModel-based Scope widget for a controller. Creates `*_scope.dart` and `*_scope_controller.dart` |
| `add_scope_aspect` | Expose a state field as aspect so widgets can subscribe to specific changes only |

## Build

```bash
dart pub get
dart compile exe bin/scope_generator_mcp.dart -o scope_generator_mcp
```
