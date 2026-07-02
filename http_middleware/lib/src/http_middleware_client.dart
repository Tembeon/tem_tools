import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import 'http_middleware.dart';
import 'middleware_context.dart';
import 'middleware_response.dart';
import 'middlewares/circuit_breaker_middleware.dart';
import 'middlewares/dedup_middleware.dart';
import 'middlewares/headers_middleware.dart';
import 'middlewares/logging_middleware.dart';
import 'middlewares/retry_middleware.dart';
import 'middlewares/swr_middleware.dart';
import 'middlewares/timeout_middleware.dart';
import 'watch_event.dart';

/// An HTTP client that processes requests through a middleware chain.
///
/// [MiddlewareClient] extends [http.BaseClient], making it a drop-in
/// replacement for any code using the `http` package. Requests pass
/// through each middleware in order before reaching the network.
///
/// ## Basic Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(),
///     AuthMiddleware(token: 'secret'),
///     RetryMiddleware(maxRetries: 3),
///   ],
/// );
///
/// final response = await client.get(Uri.parse('https://api.example.com/data'));
/// print(response.body);
///
/// client.close();
/// ```
///
/// ## Middleware Order
///
/// Middlewares execute in the order provided. The first middleware
/// wraps all subsequent middlewares:
///
/// ```
/// Request flow:  Client -> M1 -> M2 -> M3 -> Network
/// Response flow: Client <- M1 <- M2 <- M3 <- Network
/// ```
///
/// ## Background Continuation
///
/// Middlewares can return responses immediately while continuing
/// the request in the background (Stale-While-Revalidate pattern):
///
/// ```dart
/// // In a cache middleware:
/// if (cachedResponse != null) {
///   return MiddlewareResponse.withBackgroundContinuation(
///     response: cachedResponse,
///     backgroundContext: context.copyForBackground(),
///   );
/// }
/// ```
///
/// Background operations:
/// - Run asynchronously (fire-and-forget)
/// - Go through the full middleware chain
/// - Have errors handled via [HttpMiddleware.onBackgroundError]
/// - Automatically drain response streams to prevent leaks
///
/// ## Custom Inner Client
///
/// You can provide a custom inner client for testing or special configurations:
///
/// ```dart
/// final client = MiddlewareClient(
///   inner: MockClient((request) async => Response('test', 200)),
///   middlewares: [LoggingMiddleware()],
/// );
/// ```
///
/// ## Background Client
///
/// By default, background continuations (e.g., SWR revalidation) use the same
/// [inner] client as foreground requests, sharing the connection pool.
///
/// To isolate background traffic, provide a separate [backgroundInner]:
///
/// ```dart
/// final client = MiddlewareClient(
///   inner: IOClient(),
///   backgroundInner: IOClient(), // separate connection pool
///   middlewares: [SwrMiddleware(cache: cache)],
/// );
/// ```
class MiddlewareClient extends http.BaseClient {
  /// Creates a middleware client.
  ///
  /// [inner] is the underlying HTTP client used for foreground network requests.
  /// If not provided, a default [http.Client] is created.
  ///
  /// [backgroundInner] is an optional separate HTTP client used for background
  /// continuations (e.g., SWR revalidation). When provided, background requests
  /// use their own connection pool and won't compete with foreground requests.
  /// If not provided, [inner] is used for both.
  ///
  /// [middlewares] is the list of middlewares to apply to each request.
  /// Middlewares are executed in the order provided.
  MiddlewareClient({
    http.Client? inner,
    http.Client? backgroundInner,
    List<HttpMiddleware> middlewares = const [],
  }) : _inner = inner ?? http.Client(),
       _backgroundInner = backgroundInner,
       _middlewares = List.unmodifiable(middlewares);

  /// Creates a client with the recommended middleware stack, plug and play.
  ///
  /// The chain, in order:
  ///
  /// 1. [LoggingMiddleware] - only when [onLog] is provided
  /// 2. [HeadersMiddleware] - only when [defaultHeaders] is non-empty
  /// 3. [extra] - your custom middlewares
  /// 4. [DedupMiddleware] - collapses concurrent identical requests
  /// 5. [SwrMiddleware] - instant cached responses, background refresh
  /// 6. [RetryMiddleware] - only when [maxRetries] > 0
  /// 7. [CircuitBreakerMiddleware] - fails fast on a dead backend
  /// 8. [TimeoutMiddleware] - only when [timeout] is non-null
  ///
  /// ```dart
  /// final client = MiddlewareClient.standard(
  ///   cache: MySqliteCache(),
  ///   defaultHeaders: {'User-Agent': 'my-app/1.0'},
  ///   onLog: logger.fine,
  /// );
  ///
  /// final response = await client.get(uri);        // SWR via send
  /// client.watchGet(uri).listen(render);           // streamed SWR
  /// ```
  ///
  /// [cache] defaults to a fresh [InMemorySwrCache] capped at 8 MiB with
  /// LRU eviction. It is non-persistent; pass your own [SwrCache] for
  /// persistence or a different limit.
  ///
  /// This constructor is deliberately opinionated and exposes few knobs.
  /// If you need to tune what it doesn't expose (retry predicates,
  /// breaker thresholds, dedup keys...), compose the chain yourself with
  /// the regular constructor - that is the intended escape hatch, not a
  /// missing feature.
  factory MiddlewareClient.standard({
    http.Client? inner,
    http.Client? backgroundInner,
    SwrCache? cache,
    Map<String, String> defaultHeaders = const {},
    LogCallback? onLog,
    int maxRetries = 3,
    Duration? timeout = const Duration(seconds: 10),
    List<HttpMiddleware> extra = const [],
  }) {
    return MiddlewareClient(
      inner: inner,
      backgroundInner: backgroundInner,
      middlewares: [
        if (onLog != null) LoggingMiddleware(onLog: onLog),
        if (defaultHeaders.isNotEmpty) HeadersMiddleware(defaultHeaders),
        ...extra,
        DedupMiddleware(),
        SwrMiddleware(
          cache: cache ?? InMemorySwrCache(maxSizeBytes: _defaultCacheSize),
        ),
        if (maxRetries > 0) RetryMiddleware(maxRetries: maxRetries),
        CircuitBreakerMiddleware(),
        if (timeout != null) TimeoutMiddleware(timeout),
      ],
    );
  }

  /// Default cache size for [MiddlewareClient.standard]: 8 MiB.
  static const _defaultCacheSize = 8 * 1024 * 1024;

  final http.Client _inner;
  final http.Client? _backgroundInner;
  final List<HttpMiddleware> _middlewares;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final context = MiddlewareContext(request: request);

    // Build and execute the middleware chain
    final middlewareResponse = await _buildChain(context);

    // If there's a background continuation, run it asynchronously
    if (middlewareResponse.hasBackgroundContinuation) {
      _runBackgroundContinuation(middlewareResponse.backgroundContext!);
    }

    return middlewareResponse.response;
  }

  /// Sends [request] and emits responses as they become available.
  ///
  /// This is the streamed form of the SWR pattern. With a cache middleware
  /// (e.g. [SwrMiddleware]) in the chain:
  ///
  /// - **Cache hit**: emits the cached response immediately, then the fresh
  ///   network response once the background revalidation completes
  ///   (two events).
  /// - **Cache miss**: emits the network response (one event).
  ///
  /// Without a middleware that produces a background continuation, this
  /// behaves like [send] with a buffered response (one event).
  ///
  /// Each [WatchEvent] tells the subscriber where the data came from via
  /// [WatchEvent.source]: fresh from the network, cached with a refresh
  /// on the way, or cached with nothing else coming:
  ///
  /// ```dart
  /// client.watchGet(uri).listen((event) {
  ///   render(event.response.body);
  ///   showUpdatingBadge(visible: event.isRevalidating);
  /// });
  /// ```
  ///
  /// Map to a typed stream with a decoder:
  ///
  /// ```dart
  /// final Stream<Profile> profile = client
  ///     .watch(http.Request('GET', profileUri))
  ///     .map((event) => Profile.fromJson(jsonDecode(event.response.body)));
  /// ```
  ///
  /// ## Errors
  ///
  /// If the revalidation fails, middlewares are still notified via
  /// [HttpMiddleware.onBackgroundError] (so cache middlewares can release
  /// their state), and the error is then emitted to the stream after the
  /// cached event. Use `handleError` if stale-on-error is acceptable:
  ///
  /// ```dart
  /// client.watch(request).handleError((_) {}) // keep the cached event only
  /// ```
  ///
  /// ## Cancellation
  ///
  /// Cancelling the subscription does not cancel the revalidation: it
  /// completes in the background and the cache is still refreshed, exactly
  /// as with [send].
  ///
  /// ## skipUnchanged
  ///
  /// When [skipUnchanged] is true, the second event is suppressed if the
  /// fresh response has the same status code and byte-identical body as
  /// the first one - listeners don't get a needless rebuild for
  /// unchanged data. The stream then closes after the cached event.
  Stream<WatchEvent> watch(
    http.BaseRequest request, {
    bool skipUnchanged = false,
  }) async* {
    final context = MiddlewareContext(request: request);
    final middlewareResponse = await _buildChain(context);

    // Start the revalidation before yielding, mirroring send(): the
    // refresh must happen even if the listener cancels after the first
    // event. Errors are delivered via the await below when the listener
    // is still there; ignore() prevents an unhandled error otherwise
    // (middlewares are notified either way).
    Future<http.Response>? revalidation;
    final backgroundContext = middlewareResponse.backgroundContext;
    if (backgroundContext != null) {
      revalidation = _superviseRevalidation(backgroundContext);
      revalidation.ignore();
    }

    final first = await http.Response.fromStream(middlewareResponse.response);
    yield WatchEvent(
      response: first,
      source: revalidation != null
          ? WatchSource.cacheRevalidating
          : context.isFromCache
          ? WatchSource.cacheOnly
          : WatchSource.network,
    );

    if (revalidation == null) {
      return;
    }

    final fresh = await revalidation;

    if (skipUnchanged &&
        fresh.statusCode == first.statusCode &&
        const ListEquality<int>().equals(fresh.bodyBytes, first.bodyBytes)) {
      return;
    }

    yield WatchEvent(response: fresh, source: WatchSource.network);
  }

  /// Convenience for [watch] with a GET request.
  Stream<WatchEvent> watchGet(
    Uri url, {
    Map<String, String>? headers,
    bool skipUnchanged = false,
  }) {
    final request = http.Request('GET', url);
    if (headers != null) {
      request.headers.addAll(headers);
    }
    return watch(request, skipUnchanged: skipUnchanged);
  }

  /// Runs the background chain and buffers the fresh response.
  ///
  /// On failure, notifies middlewares (cleanup, logging) and rethrows so
  /// the caller can surface the error.
  Future<http.Response> _superviseRevalidation(
    MiddlewareContext context,
  ) async {
    context.markAsBackground();
    try {
      final response = await _buildChain(context, client: _backgroundInner);
      return await http.Response.fromStream(response.response);
    } catch (error, stackTrace) {
      _notifyBackgroundError(error, stackTrace, context);
      rethrow;
    }
  }

  /// Builds and executes the middleware chain.
  ///
  /// If [client] is provided, it overrides the default [_inner] client
  /// for the terminal network request.
  Future<MiddlewareResponse> _buildChain(
    MiddlewareContext context, {
    http.Client? client,
  }) {
    final effectiveClient = client ?? _inner;

    // Terminal handler: makes the actual HTTP request
    Future<MiddlewareResponse> terminal(MiddlewareContext ctx) async {
      final response = await effectiveClient.send(ctx.request);
      return MiddlewareResponse.immediate(response);
    }

    // Build chain by wrapping handlers from last to first
    // Result: m1(m2(m3(terminal)))
    // Execution: m1 -> m2 -> m3 -> network -> m3 -> m2 -> m1
    MiddlewareNext handler = terminal;

    for (final middleware in _middlewares.reversed) {
      final next = handler;
      handler = (ctx) => middleware.process(ctx, next);
    }

    return handler(context);
  }

  /// Runs a background continuation asynchronously.
  ///
  /// This is fire-and-forget: the method returns immediately
  /// while the continuation runs in the background.
  void _runBackgroundContinuation(MiddlewareContext context) {
    // Ensure the context is marked as background
    context.markAsBackground();

    // Schedule the background operation to run asynchronously
    // Using unawaited Future to ensure it's scheduled properly
    Future(() async {
      try {
        // Execute the full middleware chain using the background client
        final response = await _buildChain(context, client: _backgroundInner);

        // Drain the response stream to prevent resource leaks
        await response.response.stream.drain<void>();
      } catch (error, stackTrace) {
        _notifyBackgroundError(error, stackTrace, context);
      }
    });
  }

  /// Notifies all middlewares of a background error.
  void _notifyBackgroundError(
    Object error,
    StackTrace stackTrace,
    MiddlewareContext context,
  ) {
    for (final middleware in _middlewares) {
      try {
        middleware.onBackgroundError(error, stackTrace, context);
      } catch (_) {
        // Ignore errors from error handlers
      }
    }
  }

  @override
  void close() {
    _inner.close();
    _backgroundInner?.close();
  }
}
