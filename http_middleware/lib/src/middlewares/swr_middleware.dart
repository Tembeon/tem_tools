import 'package:http/http.dart' as http;

import '../cached_response.dart';
import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// Interface for cache storage used by [SwrMiddleware].
///
/// Implement this interface to provide your own cache backend
/// (in-memory, SQLite, shared_preferences, etc.).
///
/// ## Example Implementation
///
/// ```dart
/// class InMemorySwrCache implements SwrCache {
///   final _cache = <String, CachedResponse>{};
///
///   @override
///   Future<CachedResponse?> get(String key) async => _cache[key];
///
///   @override
///   Future<void> set(String key, CachedResponse response) async {
///     _cache[key] = response;
///   }
///
///   @override
///   Future<void> remove(String key) async {
///     _cache.remove(key);
///   }
///
///   @override
///   Future<void> clear() async {
///     _cache.clear();
///   }
/// }
/// ```
abstract interface class SwrCache {
  /// Retrieves a cached response by key.
  ///
  /// Returns null if the key is not in the cache.
  Future<CachedResponse?> get(String key);

  /// Stores a response in the cache.
  Future<void> set(String key, CachedResponse response);

  /// Removes a specific entry from the cache.
  Future<void> remove(String key);

  /// Clears all entries from the cache.
  Future<void> clear();
}

/// Function to generate a cache key from a request.
typedef CacheKeyGenerator = String Function(http.BaseRequest request);

/// Function to determine if a request should be cached.
typedef ShouldCacheRequest = bool Function(http.BaseRequest request);

/// Function to determine if a response should be cached.
typedef ShouldCacheResponse = bool Function(http.StreamedResponse response);

/// A middleware implementing the Stale-While-Revalidate (SWR) caching pattern.
///
/// SWR returns cached data immediately (stale) while fetching fresh data
/// in the background (revalidate). This provides the best of both worlds:
/// - Instant responses from cache (great UX)
/// - Fresh data that updates the cache for next time
///
/// ## How It Works
///
/// 1. Request comes in
/// 2. If cached response exists:
///    - Return cached response immediately to caller
///    - Start background request to refresh cache
/// 3. If no cached response:
///    - Make network request
///    - Cache the response
///    - Return to caller
///
/// ## Basic Usage
///
/// ```dart
/// final cache = InMemorySwrCache();
///
/// final client = MiddlewareClient(
///   middlewares: [
///     SwrMiddleware(cache: cache),
///   ],
/// );
///
/// // First request - cache miss, goes to network
/// final response1 = await client.get(uri);
///
/// // Second request - cache hit!
/// // Returns instantly from cache
/// // Background request refreshes cache
/// final response2 = await client.get(uri);
/// ```
///
/// ## Cache Key Generation
///
/// By default, cache keys are `METHOD:URL`. You can customize this:
///
/// ```dart
/// SwrMiddleware(
///   cache: cache,
///   cacheKeyGenerator: (request) {
///     // Include headers in cache key
///     final auth = request.headers['Authorization'] ?? '';
///     return '${request.method}:${request.url}:$auth';
///   },
/// )
/// ```
///
/// ## Conditional Caching
///
/// Control what gets cached:
///
/// ```dart
/// SwrMiddleware(
///   cache: cache,
///   // Only cache GET requests (default)
///   shouldCacheRequest: (request) => request.method == 'GET',
///   // Only cache successful responses
///   shouldCacheResponse: (response) =>
///       response.statusCode >= 200 && response.statusCode < 300,
/// )
/// ```
///
/// ## Integration with Other Middlewares
///
/// SWR works well with other middlewares. Place it after logging
/// to see both cache hits and background requests:
///
/// ```dart
/// MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(),  // Logs all requests including background
///     AuthMiddleware(),      // Adds auth headers
///     SwrMiddleware(cache: cache),  // Cache layer
///   ],
/// )
/// ```
class SwrMiddleware extends HttpMiddleware {
  /// Creates an SWR middleware.
  ///
  /// [cache] is the cache backend to use.
  ///
  /// [cacheKeyGenerator] generates cache keys from requests.
  /// Defaults to `METHOD:URL`.
  ///
  /// [shouldCacheRequest] determines if a request should be cached.
  /// Defaults to only caching GET requests.
  ///
  /// [shouldCacheResponse] determines if a response should be cached.
  /// Defaults to caching successful (2xx) responses.
  SwrMiddleware({
    required this.cache,
    CacheKeyGenerator? cacheKeyGenerator,
    ShouldCacheRequest? shouldCacheRequest,
    ShouldCacheResponse? shouldCacheResponse,
  })  : cacheKeyGenerator = cacheKeyGenerator ?? _defaultCacheKey,
        shouldCacheRequest = shouldCacheRequest ?? _defaultShouldCacheRequest,
        shouldCacheResponse =
            shouldCacheResponse ?? _defaultShouldCacheResponse;

  /// The cache backend.
  final SwrCache cache;

  /// Function to generate cache keys.
  final CacheKeyGenerator cacheKeyGenerator;

  /// Function to determine if a request should be cached.
  final ShouldCacheRequest shouldCacheRequest;

  /// Function to determine if a response should be cached.
  final ShouldCacheResponse shouldCacheResponse;

  static String _defaultCacheKey(http.BaseRequest request) {
    return '${request.method}:${request.url}';
  }

  static bool _defaultShouldCacheRequest(http.BaseRequest request) {
    return request.method == 'GET';
  }

  static bool _defaultShouldCacheResponse(http.StreamedResponse response) {
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    // Don't cache if this is a background revalidation
    // (we'll cache the result after the request completes)
    final isBackground = context.isBackground;

    // Check if this request should be cached
    if (!shouldCacheRequest(context.request)) {
      return next(context);
    }

    final cacheKey = cacheKeyGenerator(context.request);

    // Store cache key in metadata for other middlewares (e.g., cache tags)
    context.metadata['swr:cacheKey'] = cacheKey;

    // If this is a background request, just update the cache
    if (isBackground) {
      return _handleBackgroundRequest(context, next, cacheKey);
    }

    // Try to get cached response
    final cached = await cache.get(cacheKey);

    if (cached != null) {
      // Cache hit! Return immediately and revalidate in background
      context.markAsFromCache();

      // Create background context for revalidation
      // Use copyForBackground to clone the request so it can be sent again
      final backgroundContext = context.copyForBackground();
      backgroundContext.metadata['swr:revalidating'] = true;

      return MiddlewareResponse.withBackgroundContinuation(
        response: cached.toStreamedResponse(),
        backgroundContext: backgroundContext,
      );
    }

    // Cache miss - proceed to network and cache the result
    return _handleCacheMiss(context, next, cacheKey);
  }

  Future<MiddlewareResponse> _handleBackgroundRequest(
    MiddlewareContext context,
    MiddlewareNext next,
    String cacheKey,
  ) async {
    final response = await next(context);

    // Cache the response if it's cacheable
    if (shouldCacheResponse(response.response)) {
      final cached =
          await CachedResponse.fromStreamedResponse(response.response);
      await cache.set(cacheKey, cached);

      // Return a new response since we consumed the original stream
      return MiddlewareResponse.immediate(cached.toStreamedResponse());
    }

    return response;
  }

  Future<MiddlewareResponse> _handleCacheMiss(
    MiddlewareContext context,
    MiddlewareNext next,
    String cacheKey,
  ) async {
    final response = await next(context);

    // Cache successful responses
    if (shouldCacheResponse(response.response)) {
      final cached =
          await CachedResponse.fromStreamedResponse(response.response);
      await cache.set(cacheKey, cached);

      // Return a new response since we consumed the original stream
      return MiddlewareResponse.immediate(cached.toStreamedResponse());
    }

    return response;
  }

  @override
  void onBackgroundError(Object error, StackTrace stackTrace) {
    // Background revalidation failures are expected sometimes
    // (network issues, server errors, etc.)
    // The stale cache entry remains valid for future requests
  }
}

/// A simple in-memory implementation of [SwrCache].
///
/// Useful for testing and simple applications. For production,
/// consider using a persistent cache like SQLite.
///
/// ## Usage
///
/// ```dart
/// final cache = InMemorySwrCache();
/// final client = MiddlewareClient(
///   middlewares: [SwrMiddleware(cache: cache)],
/// );
/// ```
///
/// ## Limitations
///
/// - No persistence: cache is lost when the app restarts
/// - No size limits: can grow unbounded
/// - No TTL: entries never expire automatically
///
/// For production, implement [SwrCache] with these features.
class InMemorySwrCache implements SwrCache {
  final _cache = <String, CachedResponse>{};

  @override
  Future<CachedResponse?> get(String key) async => _cache[key];

  @override
  Future<void> set(String key, CachedResponse response) async {
    _cache[key] = response;
  }

  @override
  Future<void> remove(String key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }

  /// Returns the number of entries in the cache.
  int get length => _cache.length;

  /// Returns all cache keys.
  Iterable<String> get keys => _cache.keys;
}
