import 'dart:async';

import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// A middleware that limits how long a request may take.
///
/// Throws a [TimeoutException] when the chain below it does not produce
/// a response in time. Combine with [RetryMiddleware] (placed above this
/// one) to retry timed-out requests.
///
/// ## Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     RetryMiddleware(),
///     TimeoutMiddleware(const Duration(seconds: 10)),
///   ],
/// );
/// ```
///
/// ## Background requests
///
/// Background revalidations often tolerate a longer wait - the caller
/// already has a response. Use [backgroundTimeout] to relax the limit:
///
/// ```dart
/// TimeoutMiddleware(
///   const Duration(seconds: 5),
///   backgroundTimeout: const Duration(seconds: 30),
/// )
/// ```
///
/// ## Scope of the limit
///
/// The timeout covers the time until response headers arrive
/// (`http.StreamedResponse` is produced), not the body download.
/// The underlying request is not cancelled - `package:http` clients
/// have no cancellation API - but its response stream is abandoned.
class TimeoutMiddleware extends HttpMiddleware {
  /// Creates a timeout middleware.
  ///
  /// [timeout] applies to foreground requests. [backgroundTimeout]
  /// applies to background continuations and defaults to [timeout].
  const TimeoutMiddleware(this.timeout, {Duration? backgroundTimeout})
    : backgroundTimeout = backgroundTimeout ?? timeout;

  /// Maximum duration for foreground requests.
  final Duration timeout;

  /// Maximum duration for background requests.
  final Duration backgroundTimeout;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) {
    final limit = context.isBackground ? backgroundTimeout : timeout;
    return next(context).timeout(limit);
  }
}
