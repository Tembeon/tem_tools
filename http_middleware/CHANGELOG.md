## 2.0.0

Breaking:

- `HttpMiddleware.onBackgroundError` now receives the background
  `MiddlewareContext` as a third parameter.
- `MiddlewareContext.metadata` is typed `Map<String, Object?>` instead of
  `Map<String, dynamic>`.
- `CachedResponse.toStreamedResponse` always reports the buffered body length
  as `contentLength` (the stored `contentLength` could describe a compressed
  body and corrupt replays).

Fixed:

- `SwrMiddleware` no longer leaks the `_isFromCache` flag into background
  revalidation contexts (background requests were logged as `[CACHE]`).
- `SwrMiddleware` deduplicates background revalidations: concurrent cache
  hits for the same key trigger a single background request instead of one
  per hit.
- A cache hit for a request that cannot be cloned (e.g. `StreamedRequest`)
  is now served from cache without revalidation instead of throwing.
- `CachedResponse.bodyString` decodes UTF-8 correctly instead of mangling
  multi-byte characters via `String.fromCharCodes`.
- `RetryMiddleware` example no longer resends an already finalized request.

Added:

- `MiddlewareClient.standard()`: plug-and-play factory that wires the
  recommended chain (logging, default headers, dedup, SWR, retry, circuit
  breaker, timeout) with sensible defaults and an `extra` extension point.
  Its default cache is capped at 8 MiB.
- `InMemorySwrCache` supports LRU eviction via `maxSizeBytes` and
  `maxEntries`; `get` marks entries as recently used, `sizeInBytes`
  exposes current usage. Unbounded by default, as before.
- Streamed SWR: `MiddlewareClient.watch(request)` and `watchGet(url)` return
  a `Stream<WatchEvent>` that emits the cached response immediately and the
  fresh response once background revalidation completes. `WatchEvent.source`
  carries the origin (`network` / `cacheRevalidating` / `cacheOnly`), with
  `isFromCache` and `isRevalidating` shorthands. Revalidation
  errors surface as stream errors (after middleware notification);
  cancelling the subscription does not cancel the cache refresh;
  `skipUnchanged: true` drops the second event for byte-identical data.
- `InlineMiddleware`: build a middleware from a closure, with
  `InlineMiddleware.onRequest` and `InlineMiddleware.onResponse` shortcuts.
- `RetryMiddleware`: retries with exponential backoff, request cloning per
  attempt, configurable predicates. Never retries cached responses or
  responses carrying a background continuation.
- `CircuitBreakerMiddleware`: fails fast with `CircuitOpenException` when a
  backend keeps failing. Per-host circuits by default, configurable
  threshold, cooldown, probe count, failure predicates, key/exemption
  predicates, state-change listener and clock injection.
- `TimeoutMiddleware`: bounds request duration, with a separate relaxed
  limit for background revalidations.
- `HeadersMiddleware`: default or dynamically built (e.g. auth token)
  headers for every request.
- `DedupMiddleware` skips body buffering when no concurrent request joined,
  preserving streaming for the common single-caller case.
- `CachedResponse.cachedAt` timestamp for TTL/staleness checks in cache
  backends.
- `CachedResponse.toStreamedResponse` accepts an optional `request` to attach
  to the produced response.
- `MiddlewareContext.cloneRequest` is now public for retry-style middlewares.

## 1.0.0

- Initial version.
