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
  }) : cacheKeyGenerator = cacheKeyGenerator ?? _defaultCacheKey,
       shouldCacheRequest = shouldCacheRequest ?? _defaultShouldCacheRequest,
       shouldCacheResponse = shouldCacheResponse ?? _defaultShouldCacheResponse;

  /// The cache backend.
  final SwrCache cache;

  /// Function to generate cache keys.
  final CacheKeyGenerator cacheKeyGenerator;

  /// Function to determine if a request should be cached.
  final ShouldCacheRequest shouldCacheRequest;

  /// Function to determine if a response should be cached.
  final ShouldCacheResponse shouldCacheResponse;

  /// Cache keys with a revalidation currently in flight.
  ///
  /// Prevents a revalidation stampede: concurrent cache hits for the
  /// same key trigger only one background request.
  final Set<String> _revalidating = {};

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
    // Check if this request should be cached
    if (!shouldCacheRequest(context.request)) {
      return next(context);
    }

    final cacheKey = cacheKeyGenerator(context.request);

    // Store cache key in metadata for other middlewares (e.g., cache tags)
    context.metadata['swr:cacheKey'] = cacheKey;

    // If this is a background revalidation, just update the cache
    if (context.isBackground) {
      try {
        return await _fetchAndCache(context, next, cacheKey);
      } finally {
        _revalidating.remove(cacheKey);
      }
    }

    // Try to get cached response
    final cached = await cache.get(cacheKey);

    // Cache miss - proceed to network and cache the result
    if (cached == null) {
      return _fetchAndCache(context, next, cacheKey);
    }

    // Cache hit! Return immediately and revalidate in background,
    // unless a revalidation for this key is already in flight.
    if (_revalidating.contains(cacheKey)) {
      context.markAsFromCache();
      return MiddlewareResponse.immediate(
        cached.toStreamedResponse(request: context.request),
      );
    }

    // Clone the request so it can be sent again in the background.
    final MiddlewareContext backgroundContext;
    try {
      backgroundContext = context.copyForBackground();
    } on UnsupportedError {
      // The request cannot be cloned (e.g., StreamedRequest):
      // serve from cache without revalidation instead of failing.
      context.markAsFromCache();
      return MiddlewareResponse.immediate(
        cached.toStreamedResponse(request: context.request),
      );
    }
    backgroundContext.metadata['swr:revalidating'] = true;

    context.markAsFromCache();
    _revalidating.add(cacheKey);

    return MiddlewareResponse.withBackgroundContinuation(
      response: cached.toStreamedResponse(request: context.request),
      backgroundContext: backgroundContext,
    );
  }

  Future<MiddlewareResponse> _fetchAndCache(
    MiddlewareContext context,
    MiddlewareNext next,
    String cacheKey,
  ) async {
    final response = await next(context);

    if (!shouldCacheResponse(response.response)) {
      return response;
    }

    final cached = await CachedResponse.fromStreamedResponse(response.response);
    await cache.set(cacheKey, cached);

    // Return a new response since we consumed the original stream
    return MiddlewareResponse.immediate(
      cached.toStreamedResponse(request: context.request),
    );
  }

  @override
  void onBackgroundError(
    Object error,
    StackTrace stackTrace,
    MiddlewareContext context,
  ) {
    // Background revalidation failures are expected sometimes
    // (network issues, server errors, etc.)
    // The stale cache entry remains valid for future requests.
    // Release the revalidation lock even if the chain failed before
    // reaching this middleware.
    final cacheKey = context.metadata['swr:cacheKey'];
    if (cacheKey is String) {
      _revalidating.remove(cacheKey);
    }
  }
}

/// A simple in-memory implementation of [SwrCache] with optional
/// LRU eviction.
///
/// When [maxSizeBytes] or [maxEntries] is set, the least recently used
/// entries are evicted once the limit is exceeded. Reading an entry via
/// [get] marks it as recently used.
///
/// ## Usage
///
/// ```dart
/// final cache = InMemorySwrCache(maxSizeBytes: 8 * 1024 * 1024); // 8 MiB
/// final client = MiddlewareClient(
///   middlewares: [SwrMiddleware(cache: cache)],
/// );
/// ```
///
/// ## Limitations
///
/// - No persistence: cache is lost when the app restarts
/// - No TTL: entries never expire automatically (only by eviction)
/// - Size accounting counts response bodies only; headers overhead
///   is not included
///
/// For persistence or TTL, implement [SwrCache] over your own storage.
class InMemorySwrCache implements SwrCache {
  /// Creates an in-memory cache.
  ///
  /// [maxSizeBytes] caps the total size of cached response bodies.
  /// A response larger than the whole limit is not cached at all
  /// (and removes any stale entry under its key).
  ///
  /// [maxEntries] caps the number of entries.
  ///
  /// When both are null, the cache grows unbounded.
  InMemorySwrCache({this.maxSizeBytes, this.maxEntries})
    : assert(
        maxSizeBytes == null || maxSizeBytes > 0,
        'maxSizeBytes must be positive',
      ),
      assert(
        maxEntries == null || maxEntries > 0,
        'maxEntries must be positive',
      );

  /// Maximum total size of cached response bodies, in bytes.
  final int? maxSizeBytes;

  /// Maximum number of cached entries.
  final int? maxEntries;

  /// Insertion-ordered map; the first key is the least recently used.
  final _cache = <String, CachedResponse>{};

  int _sizeBytes = 0;

  @override
  Future<CachedResponse?> get(String key) async {
    final entry = _cache.remove(key);
    if (entry == null) {
      return null;
    }
    // Re-insert to mark as most recently used
    _cache[key] = entry;
    return entry;
  }

  @override
  Future<void> set(String key, CachedResponse response) async {
    final maxSize = maxSizeBytes;
    if (maxSize != null && response.sizeInBytes > maxSize) {
      // The response alone exceeds the limit: caching it would evict
      // everything else and still break the cap. Drop the stale entry
      // under this key so it doesn't get served forever.
      await remove(key);
      return;
    }

    final old = _cache.remove(key);
    if (old != null) {
      _sizeBytes -= old.sizeInBytes;
    }

    _cache[key] = response;
    _sizeBytes += response.sizeInBytes;

    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    final maxSize = maxSizeBytes;
    final maxCount = maxEntries;
    while ((maxSize != null && _sizeBytes > maxSize) ||
        (maxCount != null && _cache.length > maxCount)) {
      final oldestKey = _cache.keys.first;
      _sizeBytes -= _cache.remove(oldestKey)!.sizeInBytes;
    }
  }

  @override
  Future<void> remove(String key) async {
    final removed = _cache.remove(key);
    if (removed != null) {
      _sizeBytes -= removed.sizeInBytes;
    }
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _sizeBytes = 0;
  }

  /// Returns the number of entries in the cache.
  int get length => _cache.length;

  /// Returns all cache keys, least recently used first.
  Iterable<String> get keys => _cache.keys;

  /// Total size of cached response bodies, in bytes.
  int get sizeInBytes => _sizeBytes;
}
