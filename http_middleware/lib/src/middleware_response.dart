import 'package:http/http.dart' as http;

import 'middleware_context.dart';

/// A response wrapper that supports returning a result immediately while
/// optionally continuing the middleware chain in the background.
///
/// This is the core mechanism that enables patterns like Stale-While-Revalidate
/// (SWR), where a cached response is returned immediately to the caller while
/// a background request refreshes the cache.
///
/// ## Usage Patterns
///
/// ### Simple Response (most common)
/// For normal middleware that just passes through or modifies responses:
/// ```dart
/// final response = await next(context);
/// return response; // Already a MiddlewareResponse
/// ```
///
/// Or when creating a response directly:
/// ```dart
/// return MiddlewareResponse(response: myStreamedResponse);
/// ```
///
/// ### Background Continuation (SWR pattern)
/// When you want to return a cached result but continue the request:
/// ```dart
/// if (cachedResponse != null) {
///   return MiddlewareResponse.withBackgroundContinuation(
///     response: cachedResponse,
///     backgroundContext: context.copyWith(),
///   );
/// }
/// ```
class MiddlewareResponse {
  /// Creates a middleware response.
  ///
  /// [response] is the HTTP response to return to the caller.
  /// [backgroundContext] optionally specifies a context for background continuation.
  const MiddlewareResponse({
    required this.response,
    this.backgroundContext,
  });

  /// Creates a simple response without background continuation.
  ///
  /// This is the most common case for middlewares that don't need
  /// to trigger background operations.
  const MiddlewareResponse.immediate(this.response) : backgroundContext = null;

  /// Creates a response that triggers background continuation.
  ///
  /// The [response] is returned to the caller immediately, while
  /// [backgroundContext] is used to continue the middleware chain
  /// in a fire-and-forget manner.
  ///
  /// This is the key mechanism for SWR: return cached data immediately,
  /// then revalidate in the background.
  ///
  /// Example:
  /// ```dart
  /// final cachedData = await cache.get(key);
  /// if (cachedData != null) {
  ///   final backgroundCtx = context.copyWith();
  ///   backgroundCtx.markAsBackground();
  ///
  ///   return MiddlewareResponse.withBackgroundContinuation(
  ///     response: cachedData.toStreamedResponse(),
  ///     backgroundContext: backgroundCtx,
  ///   );
  /// }
  /// ```
  const MiddlewareResponse.withBackgroundContinuation({
    required this.response,
    required MiddlewareContext this.backgroundContext,
  });

  /// The HTTP response to return to the caller.
  final http.StreamedResponse response;

  /// Optional context for background continuation.
  ///
  /// When this is non-null, the [MiddlewareClient] will run the full
  /// middleware chain again with this context after returning the
  /// [response] to the caller.
  ///
  /// The background operation:
  /// - Runs asynchronously (fire-and-forget)
  /// - Goes through the full middleware chain
  /// - Has errors handled silently via [HttpMiddleware.onBackgroundError]
  /// - Drains the response stream to prevent resource leaks
  final MiddlewareContext? backgroundContext;

  /// Returns true if this response has a background continuation.
  bool get hasBackgroundContinuation => backgroundContext != null;

  @override
  String toString() {
    return 'MiddlewareResponse('
        'status: ${response.statusCode}, '
        'hasBackgroundContinuation: $hasBackgroundContinuation)';
  }
}
