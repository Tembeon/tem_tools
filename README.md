# tem_tools

Dart/Flutter utilities.

## Tools

| Tool | Description | Updated at |
|---------|-------------|------------|
| [json](json) | Type-safe JSON parsing with path traversal (`user.profile.name`) | 26.07.02 |
| [copy](copy) | `copyWith` that can set nullable fields to null | 26.07.02 |
| [http_middleware](http_middleware) | Middleware chain for `http` with SWR caching, dedup, retry, circuit breaker | 26.07.02 |

## Claude Code marketplace

Personal marketplace of Claude Code plugins covering Dart/Flutter workflows.

| Plugin | Description | Updated at |
|---------|-------------|------------|
| [flutter-3-44-update](plugins/flutter-3-44-update) | Flutter 3.44 / Dart 3.12 reference + migration workflow | 26.05.22 |
| [http-middleware](plugins/http-middleware) | Usage guide for the http_middleware package (SWR, dedup, retry, breaker) | 26.07.02 |
| [copy](plugins/copy) | Usage guide for the copy package (nullable copyWith, Flutter interop) | 26.07.02 |
| [json](plugins/json) | Usage guide for the json package (typed access, path traversal, listOf) | 26.07.02 |
| [scope-architecture](plugins/scope-architecture) | Scope pattern skill + scaffold/review agents (successor of scope_generator) | 26.07.02 |

Install in a Claude Code session:

```
/plugin marketplace add Tembeon/tem_tools
/plugin install flutter-3-44-update@tem-tools
```
