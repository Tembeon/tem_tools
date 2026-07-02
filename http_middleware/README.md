# http_middleware

A flexible HTTP middleware system for Dart that enables powerful request/response interception patterns including Stale-While-Revalidate (SWR) caching.

## Features

- **Class-based middlewares** - Extend `HttpMiddleware` for clean, testable implementations
- **Pipe pattern** - Middlewares chain together naturally, wrapping each other
- **Background continuation** - Return responses immediately while continuing requests in the background
- **Stale-While-Revalidate (SWR)** - Built-in SWR middleware for instant cached responses with background revalidation
- **Streamed SWR** - `watch()` emits the cached response first, then the fresh one (`Stream<Response>`)
- **Context sharing** - Pass data between middlewares via `MiddlewareContext`
- **Error handling hooks** - Handle background errors gracefully with `onBackgroundError`

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  http_middleware:
    git:
      url: https://github.com/tembeon/tem_tools.git
      ref: main
      path: http_middleware
```

## Quick Start

The plug-and-play way - `MiddlewareClient.standard` wires the recommended
chain (dedup, SWR cache, retries, circuit breaker, timeout) for you:

```dart
import 'package:http_middleware/http_middleware.dart';

void main() async {
  final client = MiddlewareClient.standard(
    defaultHeaders: {'User-Agent': 'my-app/1.0'},
    onLog: print, // omit to disable logging
  );

  final response = await client.get(Uri.parse('https://api.example.com/data'));
  print(response.body);

  client.watchGet(Uri.parse('https://api.example.com/data')).listen(
    (event) => print('${event.source}: ${event.response.body}'),
  );

  client.close();
}
```

`standard()` is deliberately opinionated with few knobs (`cache`,
`defaultHeaders`, `onLog`, `maxRetries`, `timeout`, `extra` for custom
middlewares). Need retry predicates, breaker thresholds or custom dedup
keys? Compose the chain yourself - that's the intended escape hatch:

```dart
final client = MiddlewareClient(
  middlewares: [
    LoggingMiddleware(),
    SwrMiddleware(cache: InMemorySwrCache()),
  ],
);
```

## Creating Custom Middlewares

Extend `HttpMiddleware` and implement the `process` method:

```dart
class AuthMiddleware extends HttpMiddleware {
  const AuthMiddleware({required this.token});

  final String token;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    // Modify the request
    context.request.headers['Authorization'] = 'Bearer $token';

    // Continue to next middleware
    return next(context);
  }
}
```

For one-off logic, `InlineMiddleware` avoids the class boilerplate:

```dart
MiddlewareClient(
  middlewares: [
    // Mutate the request
    InlineMiddleware.onRequest((request) {
      request.headers['X-Request-Id'] = generateId();
    }),
    // Observe the response (must not consume its stream)
    InlineMiddleware.onResponse((response, context) {
      if (response.statusCode == 401) authState.markExpired();
    }),
    // Full control
    InlineMiddleware((context, next) async {
      context.metadata['trace:id'] = generateTraceId();
      return next(context);
    }),
  ],
)
```

## Middleware Execution Order

Middlewares execute in the order they're added. The first middleware wraps all subsequent ones:

```
Request:  Client → M1 → M2 → M3 → Network
Response: Client ← M1 ← M2 ← M3 ← Network
```

Example:

```dart
final client = MiddlewareClient(
  middlewares: [
    LoggingMiddleware(),   // Runs first (outermost)
    AuthMiddleware(),      // Runs second
    RetryMiddleware(),     // Runs third (innermost)
  ],
);
```

## Stale-While-Revalidate (SWR)

The SWR pattern returns cached data immediately while fetching fresh data in the background:

```dart
final cache = InMemorySwrCache();

final client = MiddlewareClient(
  middlewares: [
    LoggingMiddleware(),
    SwrMiddleware(cache: cache),
  ],
);

// First request - cache miss, goes to network
final response1 = await client.get(uri);  // ~200ms

// Second request - cache hit!
// Returns instantly from cache
// Background request refreshes cache
final response2 = await client.get(uri);  // ~1ms
```

### Streamed SWR: watch()

`send()` can only return one response, so with SWR the fresh data lands
in the cache silently. `watch()` exposes both: it emits the cached
response immediately, then the fresh one when revalidation completes.

Each event is a `WatchEvent` whose `source` tells you where the data
came from:

- `WatchSource.network` - fresh data, final event
- `WatchSource.cacheRevalidating` - stale cache data, fresh event follows
- `WatchSource.cacheOnly` - stale cache data, nothing else on this stream
  (e.g. another request is already revalidating this key)

```dart
// Cache hit: 2 events (stale from cache, then fresh from network)
// Cache miss or no cache middleware: 1 event (network)
client.watchGet(Uri.parse('https://api.example.com/profile')).listen(
  (event) {
    render(event.response.body);
    // Or the isFromCache / isRevalidating shorthands
    showUpdatingBadge(visible: event.source == WatchSource.cacheRevalidating);
  },
);
```

Map to a typed stream with regular stream operators:

```dart
final Stream<Profile> profile = client
    .watchGet(profileUri)
    .map((event) => Profile.fromJson(jsonDecode(event.response.body)));
```

In Flutter this plugs straight into a `StreamBuilder`: the UI shows
cached data instantly and rebuilds once when fresh data arrives.

Behavior details:

- `skipUnchanged: true` suppresses the second event when the fresh
  response is byte-identical to the cached one - no needless rebuild.
- If revalidation fails, the cached event is delivered first and the
  error follows as a stream error. Add `.handleError((_) {})` for
  stale-on-error behavior.
- Cancelling the subscription after the first event does not cancel the
  revalidation - the cache is still refreshed, like with `send()`.
- `watch(request)` accepts any clonable `BaseRequest`; `watchGet(url)`
  is the shorthand for the common case.

### Custom Cache Backend

Implement `SwrCache` for your preferred storage:

```dart
/// Please dont, hive here just for memes
class HiveSwrCache implements SwrCache {
  const HiveSwrCache(this._box);

  final Box<CachedResponse> _box;

  @override
  Future<CachedResponse?> get(String key) async => _box.get(key);

  @override
  Future<void> set(String key, CachedResponse response) async {
    await _box.put(key, response);
  }

  @override
  Future<void> remove(String key) async => _box.delete(key);

  @override
  Future<void> clear() async => _box.clear();
}
```

### Custom Cache Keys

Control how cache keys are generated:

```dart
SwrMiddleware(
  cache: cache,
  cacheKeyGenerator: (request) {
    // Include auth header in cache key for user-specific caching
    final userId = request.headers['X-User-Id'] ?? 'anonymous';
    return '$userId:${request.method}:${request.url}';
  },
)
```

## Background Continuation

Middlewares can return responses immediately while continuing the request in the background. This is the core mechanism enabling SWR:

```dart
class CustomCacheMiddleware extends HttpMiddleware {
  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    final cached = await getFromCache(context.request.url);

    if (cached != null && !context.isBackground) {
      // Return cached response immediately
      // Continue to network in background
      // Use copyForBackground() to clone the request for reuse
      return MiddlewareResponse.withBackgroundContinuation(
        response: cached.toStreamedResponse(),
        backgroundContext: context.copyForBackground(),
      );
    }

    // No cache or this IS the background request
    final response = await next(context);
    await saveToCache(context.request.url, response);
    return response;
  }
}
```

> **Important:** Use `copyForBackground()` instead of `copyWith()` when creating
> a context for background continuation. This clones the HTTP request, which is
> necessary because requests can only be sent once.

### Handling Background Errors

Override `onBackgroundError` to handle errors in background operations:

```dart
class MyMiddleware extends HttpMiddleware {
  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    // ... middleware logic
  }

  @override
  void onBackgroundError(
    Object error,
    StackTrace stackTrace,
    MiddlewareContext context,
  ) {
    // Log the error, update metrics, etc.
    logger.warning('Revalidation of ${context.request.url} failed: $error');
  }
}
```

## Sharing Data Between Middlewares

Use `MiddlewareContext.metadata` to pass data through the chain:

```dart
class TimingMiddleware extends HttpMiddleware {
  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    final stopwatch = Stopwatch()..start();

    final response = await next(context);

    stopwatch.stop();
    context.metadata['timing:totalMs'] = stopwatch.elapsedMilliseconds;

    return response;
  }
}

class MetricsMiddleware extends HttpMiddleware {
  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    final response = await next(context);

    // Read data from another middleware
    final timing = context.metadata['timing:totalMs'] as int?;
    if (timing != null) {
      recordMetric('http_request_duration_ms', timing);
    }

    return response;
  }
}
```

## Built-in Middlewares

### LoggingMiddleware

Logs HTTP requests and responses with timing:

```dart
LoggingMiddleware(
  onLog: (message) => logger.info(message),
  includeHeaders: true,  // Include request/response headers
)
```

Output:
```
--> GET https://api.example.com/data
<-- 200 OK (123ms)
```

Background and cached responses are marked:
```
[BG] --> GET https://api.example.com/data
<-- 200 OK [CACHE] (2ms)
```

### SwrMiddleware

Stale-While-Revalidate caching (see above for details).

### DedupMiddleware

Deduplicates concurrent identical requests - only one network call is made
and all callers share the response:

```dart
DedupMiddleware(
  // Defaults: GET and HEAD, key is METHOD:URL
  keyGenerator: (request) => '${request.method}:${request.url}',
)
```

### RetryMiddleware

Retries failed requests with exponential backoff. Each retry sends a fresh
clone of the original request:

```dart
RetryMiddleware(
  maxRetries: 3,
  // Defaults: idempotent methods only; 408/429/5xx and network errors
  shouldRetryResponse: (response) => response.statusCode >= 500,
  delay: (attempt) => Duration(milliseconds: 200 * attempt),
)
```

Place it after caching middlewares (closer to the network) so retries don't
re-enter the cache layer.

### CircuitBreakerMiddleware

Stops hammering a failing backend: after `failureThreshold` consecutive
failures the circuit opens and requests fail fast with `CircuitOpenException`
(no network call). After `openDuration` a probe request is let through -
success closes the circuit, failure reopens it.

```dart
CircuitBreakerMiddleware(
  failureThreshold: 5,
  openDuration: const Duration(seconds: 30),
  halfOpenProbes: 1,
  // Circuits are per scheme://host:port by default
  keyGenerator: (request) => request.url.host,
  // 5xx by default; errors: ClientException and TimeoutException
  isFailureResponse: (response) => response.statusCode >= 500,
  // Exempt endpoints, e.g. health checks
  shouldBreak: (request) => !request.url.path.startsWith('/health'),
  onStateChange: (key, from, to) => log.warning('$key: $from -> $to'),
)
```

With `SwrMiddleware` above the breaker an outage degrades gracefully:
cache hits are still served instantly, only cache misses fail fast.
`CircuitOpenException` is not retried by `RetryMiddleware` defaults, so
retries stop as soon as the circuit opens.

### TimeoutMiddleware

Bounds how long a request may take, with an optional relaxed limit for
background revalidations:

```dart
TimeoutMiddleware(
  const Duration(seconds: 5),
  backgroundTimeout: const Duration(seconds: 30),
)
```

### HeadersMiddleware

Applies default headers to every request. Request-level headers win unless
`overrideExisting` is set:

```dart
// Static headers
HeadersMiddleware({'User-Agent': 'my-app/1.2.0'})

// Dynamic headers, e.g. tokens from secure storage
HeadersMiddleware.builder((request) async {
  final token = await tokenStorage.read();
  return {'Authorization': 'Bearer $token'};
})
```

Background revalidations re-run the whole chain, so they pick up fresh
header values (e.g. a refreshed token) automatically.

## Recommended Order

```dart
MiddlewareClient(
  middlewares: [
    LoggingMiddleware(),          // outermost: sees everything, incl. cache hits
    HeadersMiddleware(...),       // headers apply to foreground and background
    DedupMiddleware(),            // collapse concurrent identical calls
    SwrMiddleware(...),           // serve from cache, revalidate in background
    RetryMiddleware(),            // retries hit the network, not the cache
    CircuitBreakerMiddleware(),   // every retry attempt is checked and recorded
    TimeoutMiddleware(...),       // innermost: timeouts count as breaker failures
  ],
)
```

## API Reference

### Core Classes

| Class | Description |
|-------|-------------|
| `MiddlewareClient` | HTTP client that processes requests through middleware chain |
| `HttpMiddleware` | Base class for creating middlewares |
| `InlineMiddleware` | Middleware from a closure, no subclass needed |
| `MiddlewareContext` | Carries request and metadata through the chain |
| `MiddlewareResponse` | Response wrapper supporting background continuation |
| `CachedResponse` | Serializable response for caching |

### Built-in Middlewares

| Class | Description |
|-------|-------------|
| `LoggingMiddleware` | Logs requests, responses and timing |
| `SwrMiddleware` | Stale-While-Revalidate caching |
| `DedupMiddleware` | Collapses concurrent identical requests |
| `RetryMiddleware` | Retries failures with exponential backoff |
| `CircuitBreakerMiddleware` | Fails fast when a backend keeps failing |
| `TimeoutMiddleware` | Bounds request duration |
| `HeadersMiddleware` | Applies default/dynamic headers |

### SWR Components

| Class/Interface | Description |
|-----------------|-------------|
| `SwrCache` | Interface for cache backends |
| `InMemorySwrCache` | In-memory cache with optional LRU limits (`maxSizeBytes`, `maxEntries`) |
