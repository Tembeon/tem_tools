# http_middleware 2.0.0 - API reference

Verified against the package sources at `http_middleware/` in tembeon/tem_tools. All types are exported from `package:http_middleware/http_middleware.dart`.

## MiddlewareClient

```dart
MiddlewareClient({
  http.Client? inner,            // default: http.Client()
  http.Client? backgroundInner,  // separate pool for background revalidation
  List<HttpMiddleware> middlewares = const [],
})

factory MiddlewareClient.standard({
  http.Client? inner,
  http.Client? backgroundInner,
  SwrCache? cache,                              // default: InMemorySwrCache(maxSizeBytes: 8 MiB)
  Map<String, String> defaultHeaders = const {},
  LogCallback? onLog,                           // null -> no LoggingMiddleware
  int maxRetries = 3,                           // 0 -> no RetryMiddleware
  Duration? timeout = const Duration(seconds: 10),  // null -> no TimeoutMiddleware
  List<HttpMiddleware> extra = const [],        // inserted after headers, before dedup
})
```

- Extends `http.BaseClient`: `get/post/put/delete/head/send` all flow through the chain.
- `close()` closes both `inner` and `backgroundInner`.
- Chain executes in list order; first middleware is outermost.

### Streamed SWR

```dart
Stream<WatchEvent> watch(http.BaseRequest request, {bool skipUnchanged = false})
Stream<WatchEvent> watchGet(Uri url, {Map<String, String>? headers, bool skipUnchanged = false})
```

`WatchEvent`: `response` (`http.Response`, buffered), `source` (`WatchSource`), sugar getters `isFromCache`, `isRevalidating`.

`WatchSource`: `network` (fresh, final event) | `cacheRevalidating` (stale, fresh event follows unless skipUnchanged suppresses it) | `cacheOnly` (stale, stream closes; happens when another request already revalidates the key or the request is unclonable).

Semantics:
- Revalidation starts BEFORE the first event is yielded; cancelling the stream does not cancel it and the cache still refreshes.
- Revalidation failure: middlewares get `onBackgroundError`, then the error is emitted to the stream.
- `skipUnchanged` compares status code + body bytes (`ListEquality`); headers are ignored.
- A failed revalidation response (e.g. 500) IS emitted as the second event but does NOT overwrite the cached entry (non-2xx not cached by default).

## HttpMiddleware (base class)

```dart
abstract class HttpMiddleware {
  Future<MiddlewareResponse> process(MiddlewareContext context, MiddlewareNext next);
  void onBackgroundError(Object error, StackTrace stackTrace, MiddlewareContext context) {}
}
typedef MiddlewareNext = Future<MiddlewareResponse> Function(MiddlewareContext);
```

`onBackgroundError` fires on ALL middlewares in the chain when a background continuation fails, with the background context (its `metadata` includes keys copied from the foreground pass, e.g. `swr:cacheKey`).

## MiddlewareContext

- `request` (`http.BaseRequest`), `metadata` (`Map<String, Object?>`).
- `isFromCache` / `markAsFromCache()`, `isBackground` / `markAsBackground()`.
- `copyWith({request, metadata})` - shallow copy, does NOT clone the request.
- `copyForBackground()` - clones the request, copies metadata minus `_isFromCache`. Throws `UnsupportedError` for unclonable requests.
- `static cloneRequest(http.BaseRequest)` - clones `Request` (incl. finalized) and `MultipartRequest`; throws `UnsupportedError` for `StreamedRequest` and unknown types.

Metadata keys: `swr:cacheKey`, `swr:revalidating`, `dedup:key`, `dedup:shared`; `_isFromCache`/`_isBackground` are internal.

## MiddlewareResponse

```dart
const MiddlewareResponse({required http.StreamedResponse response, MiddlewareContext? backgroundContext})
const MiddlewareResponse.immediate(response)
const MiddlewareResponse.withBackgroundContinuation({required response, required backgroundContext})
bool get hasBackgroundContinuation
```

Returning a non-null `backgroundContext` makes the client re-run the FULL chain with that context after returning the response (fire-and-forget in `send`, awaited in `watch`).

## CachedResponse

```dart
const CachedResponse({statusCode, body, headers, reasonPhrase, contentLength,
                      isRedirect = false, persistentConnection = true, cachedAt})
static Future<CachedResponse> fromStreamedResponse(http.StreamedResponse) // consumes stream, stamps cachedAt
http.StreamedResponse toStreamedResponse({http.BaseRequest? request})     // callable many times
String get bodyString  // utf8.decode(allowMalformed: true)
int get sizeInBytes
DateTime? cachedAt     // for TTL in custom backends
```

`toStreamedResponse` always reports the buffered body length as `contentLength` (stored value may describe a compressed body).

## SwrMiddleware

```dart
SwrMiddleware({
  required SwrCache cache,
  CacheKeyGenerator? cacheKeyGenerator,   // default '{METHOD}:{url}'
  ShouldCacheRequest? shouldCacheRequest, // default: GET only
  ShouldCacheResponse? shouldCacheResponse, // default: 2xx only
})
```

Behavior:
- Cache miss: network, cache if cacheable, return.
- Cache hit: mark from-cache, return cached + background continuation.
- Stampede protection: while a key revalidates, further hits serve cache WITHOUT starting another revalidation. Lock released on completion and via `onBackgroundError` (even if an outer middleware failed the background pass).
- Unclonable request + cache hit: serve cache, skip revalidation (no throw).
- Failed revalidation keeps the stale entry.

`SwrCache` interface: `Future<CachedResponse?> get(key)`, `set(key, response)`, `remove(key)`, `clear()`.

`InMemorySwrCache({int? maxSizeBytes, int? maxEntries})` - LRU: `get` refreshes recency; a response larger than the whole `maxSizeBytes` is not cached and evicts the stale entry under its key; exposes `length`, `keys`, `sizeInBytes`.

## DedupMiddleware

```dart
DedupMiddleware({DedupKeyGenerator? keyGenerator, ShouldDedupRequest? shouldDedup})
// defaults: key '{METHOD}:{url}', GET and HEAD only
```

- Background requests pass through (never deduped).
- If no concurrent waiter joined, the leader's response is returned as-is (no body buffering, streaming preserved).
- With waiters: body is buffered, all callers get independent replays; leader keeps its background continuation, waiters get plain responses.
- Errors (including mid-body stream errors) propagate to all waiters.
- Debug: `inFlightCount`, `inFlightKeys`.

## RetryMiddleware

```dart
RetryMiddleware({
  int maxRetries = 3,                     // total attempts = maxRetries + 1
  ShouldRetryRequest? shouldRetryRequest, // default: GET, HEAD, OPTIONS, PUT, DELETE
  ShouldRetryResponse? shouldRetryResponse, // default: 408, 429, >=500
  ShouldRetryError? shouldRetryError,     // default: ClientException, TimeoutException
  RetryDelay? delay,                      // default: 200ms * 2^(n-1), capped ~12.8s; n is 1-based
})
```

- Each retry sends a fresh clone of the ORIGINAL request (body and headers preserved).
- Never retries: cached responses, responses with a background continuation, unclonable requests (sent once; on error the original error is rethrown).
- Drains the failed response body before resending.

## CircuitBreakerMiddleware

```dart
CircuitBreakerMiddleware({
  int failureThreshold = 5,               // consecutive failures to open
  Duration openDuration = const Duration(seconds: 30),
  int halfOpenProbes = 1,                 // concurrent probes in half-open
  CircuitKeyGenerator? keyGenerator,      // default '{scheme}://{host}:{port}'
  ShouldBreakRequest? shouldBreak,        // default: all; use to exempt /health
  IsFailureResponse? isFailureResponse,   // default: >=500 (429 NOT included)
  IsFailureError? isFailureError,         // default: ClientException, TimeoutException
  CircuitStateListener? onStateChange,    // (key, from, to)
  DateTime Function()? now,               // clock injection for tests
})
```

- States: `CircuitState.closed` -> `open` (rejects with `CircuitOpenException(key, retryAfter)`) -> `halfOpen` (probes) -> `closed`/`open`.
- Cached responses are ignored (say nothing about backend health).
- Late results from requests started before the circuit opened are ignored.
- Throwing `onStateChange` is swallowed.
- Introspection: `stateFor(request)`, `stateForKey(key)`, `reset([key])`.
- `CircuitOpenException` deliberately does NOT implement `http.ClientException`, so default retry predicates do not retry it.

## TimeoutMiddleware

```dart
const TimeoutMiddleware(Duration timeout, {Duration? backgroundTimeout}) // bg defaults to timeout
```

Throws `TimeoutException`. Covers time until response HEADERS arrive; body download is not bounded. Underlying request is not cancelled (package:http has no cancellation).

## HeadersMiddleware

```dart
HeadersMiddleware(Map<String, String> headers, {bool overrideExisting = false})
HeadersMiddleware.builder(HeadersBuilder builder, {bool overrideExisting = false})
// typedef HeadersBuilder = FutureOr<Map<String, String>> Function(http.BaseRequest)
```

Request-level headers win unless `overrideExisting: true`. Background revalidations re-run the builder - refreshed tokens apply automatically.

## LoggingMiddleware

```dart
const LoggingMiddleware({LogCallback? onLog, bool includeHeaders = false})
```

Format: `--> GET url` / `<-- 200 OK [CACHE] (12ms)`; background prefixed `[BG]`. Without `onLog` falls back to `print`.

## InlineMiddleware

```dart
const InlineMiddleware(InlineHandler handler)
factory InlineMiddleware.onRequest(RequestVisitor visit)   // mutate request, then next
factory InlineMiddleware.onResponse(ResponseVisitor visit) // observe response; MUST NOT consume stream

typedef InlineHandler = Future<MiddlewareResponse> Function(MiddlewareContext context, MiddlewareNext next);
typedef RequestVisitor = FutureOr<void> Function(http.BaseRequest request);
typedef ResponseVisitor = FutureOr<void> Function(http.StreamedResponse response, MiddlewareContext context);
```

Reading a response body inside a middleware (the buffering pattern):

```dart
final response = await next(context);
final cached = await CachedResponse.fromStreamedResponse(response.response); // consumes stream
inspect(cached.bodyString);
// Preserve a background continuation if the inner response carries one -
// MiddlewareResponse.immediate would silently drop it
return MiddlewareResponse(
  response: cached.toStreamedResponse(),
  backgroundContext: response.backgroundContext,
);
```

## Recommended chain order and why

```
LoggingMiddleware        // outermost: sees everything incl. cache hits
HeadersMiddleware        // applies to foreground and background passes
DedupMiddleware          // collapse before touching cache
SwrMiddleware            // serve cache, schedule revalidation
RetryMiddleware          // retries hit network, never re-enter cache
CircuitBreakerMiddleware // sees every retry attempt; CircuitOpenException stops retries
TimeoutMiddleware        // innermost: timeouts propagate up as breaker failures
```
