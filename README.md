# tem_tools

Dart/Flutter utilities.

## Tools

| Tool | Description | Updated at |
|---------|-------------|------------|
| [json](json) | Type-safe JSON parsing with path traversal (`user.profile.name`) | 25.12.03 |
| [copy](copy) | `copyWith` that can set nullable fields to null | 25.12.03 |
| [http_middleware](http_middleware) | Middleware chain for `http` | 25.12.03 |

## Claude Code marketplace

Personal marketplace of Claude Code plugins covering Dart/Flutter workflows.

| Plugin | Description | Updated at |
|---------|-------------|------------|
| [flutter-3-44-update](plugins/flutter-3-44-update) | Flutter 3.44 / Dart 3.12 reference + migration workflow | 26.05.22 |
| [http-middleware](plugins/http-middleware) | Usage guide for the http_middleware package (SWR, dedup, retry, breaker) | 26.07.02 |
| [copy](plugins/copy) | Usage guide for the copy package (nullable copyWith, Flutter interop) | 26.07.02 |
| [json](plugins/json) | Usage guide for the json package (typed access, path traversal, listOf) | 26.07.02 |

Install in a Claude Code session:

```
/plugin marketplace add Tembeon/tem_tools
/plugin install flutter-3-44-update@tem-tools
```
