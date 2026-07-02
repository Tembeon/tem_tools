---
name: use-http-middleware
description: This skill should be used when working with the http_middleware Dart package (tembeon/tem_tools), or when the user asks to "add SWR caching to Dart http", "stale-while-revalidate in Flutter", "cache HTTP responses and refresh in background", "show cached data then update from network", "deduplicate concurrent HTTP requests", "retry failed HTTP requests in Dart", "circuit breaker for a Dart HTTP client", "HTTP timeout middleware", "add default headers / auth token to every request", "intercept requests with package:http", "MiddlewareClient", "SwrMiddleware", "watchGet", or asks how to compose an offline-friendly data layer over package:http without dio. Do NOT use this skill for dio, Chopper or Retrofit clients (they have their own interceptor systems) or for generic HTTP-caching theory questions.
version: 2.0.0
---

# http_middleware - usage guide

`http_middleware` is a Dart package (in `tembeon/tem_tools`, path `http_middleware`) that adds a composable middleware chain on top of `package:http`. Its centerpiece is Stale-While-Revalidate: serve cached responses instantly, refresh them in the background, and optionally stream both states to the UI. Answer questions from this skill and `references/api-reference.md` instead of reading the package sources.

## Installation

```yaml
dependencies:
  http_middleware:
    git:
      url: https://github.com/tembeon/tem_tools.git
      ref: main
      path: http_middleware
```

## When to reach for it

- Flutter/Dart app needs instant screens from cache with background refresh (SWR).
- UI should show cached data first, then fresh data (`Stream` of both states).
- Concurrent identical GETs must collapse into one network call.
- Transient failures need retries; a dead backend must fail fast (circuit breaker). During an outage cached data keeps being served: SWR sits outside the breaker in the chain, so an open circuit blocks only fresh network calls, never cached reads.
- Every request needs default or dynamically built headers (auth tokens).
- The user wants `package:http` (not dio) with interceptor-like behavior. Do not suggest this package if the project already uses dio - dio has its own interceptors.

## Quick start - plug and play

`MiddlewareClient.standard()` wires the recommended chain (logging -> headers -> dedup -> SWR -> retry -> circuit breaker -> timeout):

```dart
import 'package:http_middleware/http_middleware.dart';

final client = MiddlewareClient.standard(
  defaultHeaders: {'User-Agent': 'my-app/1.0'},
  onLog: print,                       // omit to disable logging
  // cache: MySqliteCache(),          // default: in-memory LRU, 8 MiB
  // maxRetries: 3, timeout: Duration(seconds: 10),
  // extra: [MyCustomMiddleware()],   // inserted after headers, before dedup
);
```

`standard()` is deliberately opinionated with few knobs. The `extra` list only INSERTS middlewares (after headers, before dedup) - it cannot reconfigure the built-in dedup/SWR/retry/breaker. To change retry predicates, breaker thresholds or dedup keys, drop `standard()` and compose the chain manually - that is the intended escape hatch:

```dart
final client = MiddlewareClient(
  middlewares: [
    LoggingMiddleware(),          // outermost: sees everything incl. cache hits
    HeadersMiddleware({'x': 'y'}),
    DedupMiddleware(),
    SwrMiddleware(cache: InMemorySwrCache(maxSizeBytes: 8 << 20)),
    RetryMiddleware(),            // retries must hit network, not cache
    CircuitBreakerMiddleware(),   // sees every retry attempt
    TimeoutMiddleware(const Duration(seconds: 10)),
  ],
);
```

The order above is load-bearing; keep it unless there is a reason not to.

`MiddlewareClient` extends `http.BaseClient`, so `get/post/send` work as usual and it drops into any API that accepts `http.Client`.

## The two SWR modes

**Future mode** - `client.get(uri)` returns the cached response instantly on a cache hit; revalidation happens fire-and-forget and lands in the cache for next time.

**Stream mode** - `client.watchGet(uri)` (or `watch(request)`) returns `Stream<WatchEvent>`:

```dart
client.watchGet(uri).listen((event) {
  render(event.response.body);
  showUpdatingBadge(visible: event.isRevalidating);
});
```

- Cache hit: 2 events - stale from cache, then fresh from network.
- Cache miss / no cache middleware: 1 event.
- `event.source`: `WatchSource.network` (fresh, final), `cacheRevalidating` (stale, fresh follows), `cacheOnly` (stale, nothing follows - another request is already revalidating this key).
- `skipUnchanged: true` drops the second event when status + body bytes are identical (no needless rebuild). Header-only changes count as unchanged.
- Revalidation errors arrive as stream errors after the cached event; `.handleError((_) {})` gives stale-on-error.
- Cancelling the subscription does NOT cancel the revalidation - the cache still refreshes.
- Typed stream: `client.watchGet(uri).map((e) => Model.fromJson(jsonDecode(e.response.body)))`.

## Built-in middlewares (one-liners)

| Middleware | Purpose | Key defaults |
|---|---|---|
| `SwrMiddleware` | SWR caching | GET only, 2xx cached, key `METHOD:URL`, stampede-protected |
| `DedupMiddleware` | collapse concurrent identical requests | GET/HEAD, key `METHOD:URL`, no buffering when no waiters |
| `RetryMiddleware` | retries with exponential backoff | idempotent methods, 408/429/5xx + ClientException/TimeoutException, 3 retries (4 total attempts) |
| `CircuitBreakerMiddleware` | fail fast on dead backend | per `scheme://host:port`, 5 consecutive failures, 30s cooldown |
| `TimeoutMiddleware` | bound request duration | covers headers arrival, not body; separate `backgroundTimeout` |
| `HeadersMiddleware` | default/dynamic headers | request-level headers win; `.builder()` for async tokens |
| `LoggingMiddleware` | request/response/timing logs | `[BG]` prefix for background, `[CACHE]` marker |
| `InlineMiddleware` | middleware from a closure | `.onRequest()`, `.onResponse()` shortcuts |

Full constructor signatures and edge-case semantics: `references/api-reference.md`.

## Writing a custom middleware

```dart
class MyMiddleware extends HttpMiddleware {
  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    context.request.headers['x-trace'] = newTraceId();  // mutate request
    final response = await next(context);               // continue chain
    return response;
  }
}
```

For one-off logic prefer `InlineMiddleware` over a class:

```dart
// RequestVisitor: FutureOr<void> Function(http.BaseRequest request)
InlineMiddleware.onRequest((request) {
  request.headers['x-request-id'] = generateId();
})

// ResponseVisitor: FutureOr<void> Function(http.StreamedResponse response, MiddlewareContext context)
// Observer only - must NOT consume response.stream
InlineMiddleware.onResponse((response, context) {
  if (response.statusCode == 401) authState.markExpired();
})
```

## Critical rules (violating these breaks user code)

1. **A `BaseRequest` can only be sent once** (resending throws "Can't finalize a finalized Request"). Any middleware that resends (retry, revalidation) must clone via `MiddlewareContext.cloneRequest(request)` or `context.copyForBackground()`. `StreamedRequest` cannot be cloned - SWR then serves cache without revalidation, retry sends once. Note: default retries cover idempotent methods only (GET/HEAD/OPTIONS/PUT/DELETE) - POST is NOT retried unless a custom `shouldRetryRequest` is passed.
2. **A response stream can only be read once.** To read a body inside a middleware, buffer it with `CachedResponse.fromStreamedResponse(...)` and return `cached.toStreamedResponse()`. Never consume the stream in `InlineMiddleware.onResponse`.
3. **Use `context.copyForBackground()`, not `copyWith()`,** when creating a background continuation - it clones the request and strips the `_isFromCache` flag.
4. **`onBackgroundError(error, stackTrace, context)`** has three parameters (since 2.0.0) and is called on ALL middlewares when a background pass fails - use it to release state.
5. **Background continuations re-run the WHOLE chain** with `context.isBackground == true`. Cache middlewares must check this flag to avoid infinite loops.
6. **Metadata conventions:** share data via `context.metadata` with prefixed keys (`swr:cacheKey`, `dedup:key`); underscore keys are internal.
7. **`CircuitOpenException` is not an `http.ClientException`** on purpose - the retry middleware must not retry an open circuit.

## Cache backends

`SwrCache` is a 4-method interface (`get/set/remove/clear`). `InMemorySwrCache` ships in the box: optional LRU via `maxSizeBytes` / `maxEntries`, `get` refreshes recency, non-persistent. For persistence implement `SwrCache` over sqlite/hive/etc; `CachedResponse.cachedAt` supports TTL logic in custom backends.

## Version note

Current version: 2.0.0 (breaking vs 1.x: `onBackgroundError` signature, `metadata` typed `Map<String, Object?>`, `toStreamedResponse` reports buffered length). 153 tests, 100% line coverage.
