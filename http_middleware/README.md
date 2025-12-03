# http_middleware

A flexible HTTP middleware system for Dart that enables powerful request/response interception patterns including Stale-While-Revalidate (SWR) caching.

## Features

- **Class-based middlewares** - Extend `HttpMiddleware` for clean, testable implementations
- **Pipe pattern** - Middlewares chain together naturally, wrapping each other
- **Background continuation** - Return responses immediately while continuing requests in the background
- **Stale-While-Revalidate (SWR)** - Built-in SWR middleware for instant cached responses with background revalidation
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

```dart
import 'package:http_middleware/http_middleware.dart';

void main() async {
  final client = MiddlewareClient(
    middlewares: [
      LoggingMiddleware(),
      SwrMiddleware(cache: InMemorySwrCache()),
    ],
  );

  final response = await client.get(Uri.parse('https://api.example.com/data'));
  print(response.body);

  client.close();
}
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
  void onBackgroundError(Object error, StackTrace stackTrace) {
    // Log the error, update metrics, etc.
    logger.warning('Background revalidation failed: $error');
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

## API Reference

### Core Classes

| Class | Description |
|-------|-------------|
| `MiddlewareClient` | HTTP client that processes requests through middleware chain |
| `HttpMiddleware` | Base class for creating middlewares |
| `MiddlewareContext` | Carries request and metadata through the chain |
| `MiddlewareResponse` | Response wrapper supporting background continuation |
| `CachedResponse` | Serializable response for caching |

### SWR Components

| Class/Interface | Description |
|-----------------|-------------|
| `SwrCache` | Interface for cache backends |
| `InMemorySwrCache` | Simple in-memory cache implementation |
