import 'middleware_context.dart';
import 'middleware_response.dart';

/// Signature for the next middleware or terminal handler in the chain.
///
/// When called with a [MiddlewareContext], it invokes the next middleware
/// in the chain (or the actual HTTP request if this is the last middleware).
typedef MiddlewareNext = Future<MiddlewareResponse> Function(
  MiddlewareContext context,
);

/// Base class for HTTP middlewares.
///
/// Extend this class to create custom middlewares that can intercept,
/// modify, or short-circuit HTTP requests and responses.
///
/// ## Basic Example
///
/// ```dart
/// class LoggingMiddleware extends HttpMiddleware {
///   @override
///   Future<MiddlewareResponse> process(
///     MiddlewareContext context,
///     MiddlewareNext next,
///   ) async {
///     print('Request: ${context.request.method} ${context.request.url}');
///     final stopwatch = Stopwatch()..start();
///
///     final response = await next(context);
///
///     print('Response: ${response.response.statusCode} '
///         'in ${stopwatch.elapsedMilliseconds}ms');
///     return response;
///   }
/// }
/// ```
///
/// ## Modifying Requests
///
/// To modify a request before it continues down the chain:
/// ```dart
/// class AuthMiddleware extends HttpMiddleware {
///   final String token;
///   AuthMiddleware(this.token);
///
///   @override
///   Future<MiddlewareResponse> process(
///     MiddlewareContext context,
///     MiddlewareNext next,
///   ) async {
///     final request = context.request;
///     if (request is http.Request) {
///       request.headers['Authorization'] = 'Bearer $token';
///     }
///     return next(context);
///   }
/// }
/// ```
///
/// ## Short-Circuiting with Background Continuation
///
/// For patterns like SWR (Stale-While-Revalidate):
/// ```dart
/// class CacheMiddleware extends HttpMiddleware {
///   final Cache cache;
///   CacheMiddleware(this.cache);
///
///   @override
///   Future<MiddlewareResponse> process(
///     MiddlewareContext context,
///     MiddlewareNext next,
///   ) async {
///     final cached = await cache.get(context.request.url.toString());
///
///     if (cached != null && !context.isBackground) {
///       // Return cached immediately, revalidate in background
///       return MiddlewareResponse.withBackgroundContinuation(
///         response: cached.toStreamedResponse(),
///         backgroundContext: context.copyWith()..markAsBackground(),
///       );
///     }
///
///     // Cache miss or background request - proceed to network
///     final response = await next(context);
///     await cache.store(context.request.url.toString(), response);
///     return response;
///   }
/// }
/// ```
///
/// ## Execution Order
///
/// Middlewares are executed in the order they are added to [MiddlewareClient].
/// The first middleware wraps all others:
///
/// ```
/// Request:  Client -> M1 -> M2 -> M3 -> Network
/// Response: Client <- M1 <- M2 <- M3 <- Network
/// ```
abstract class HttpMiddleware {
  /// Const constructor for subclasses.
  const HttpMiddleware();

  /// Processes an HTTP request through this middleware.
  ///
  /// [context] contains the request and shared metadata.
  /// [next] invokes the next middleware or makes the actual HTTP request.
  ///
  /// Returns a [MiddlewareResponse] which may include a background
  /// continuation for patterns like SWR.
  ///
  /// ## Implementation Guidelines
  ///
  /// 1. **Always call [next]** unless you're intentionally short-circuiting
  ///    (like returning a cached response).
  ///
  /// 2. **Check [context.isBackground]** in cache middlewares to avoid
  ///    infinite loops when handling background revalidation.
  ///
  /// 3. **Use [context.metadata]** to share data with other middlewares
  ///    (e.g., cache keys, timing info, tags).
  ///
  /// 4. **Handle errors appropriately**: Either let them propagate
  ///    or catch and transform them.
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  );

  /// Called when an error occurs during background continuation.
  ///
  /// Override this to handle background errors (e.g., logging).
  /// By default, errors are silently ignored as is appropriate for
  /// background revalidation operations.
  ///
  /// This is called for ALL middlewares in the chain when a background
  /// error occurs, not just the one that triggered the continuation.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onBackgroundError(Object error, StackTrace stackTrace) {
  ///   logger.warning('Background revalidation failed: $error');
  /// }
  /// ```
  void onBackgroundError(Object error, StackTrace stackTrace) {
    // Silent by default - appropriate for background operations
  }
}
