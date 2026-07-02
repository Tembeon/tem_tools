import 'dart:async';

import 'package:http/http.dart' as http;

import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// Determines if a request is eligible for retries at all.
typedef ShouldRetryRequest = bool Function(http.BaseRequest request);

/// Determines if a received response should be retried.
typedef ShouldRetryResponse = bool Function(http.StreamedResponse response);

/// Determines if a thrown error should be retried.
typedef ShouldRetryError = bool Function(Object error);

/// Builds the delay before a retry. [attempt] starts at 1 for the
/// first retry.
typedef RetryDelay = Duration Function(int attempt);

/// A middleware that retries failed requests.
///
/// A request is retried when it throws a retriable error or produces a
/// retriable response (by default: 408, 429 and all 5xx). Each retry sends
/// a fresh clone of the original request, since an [http.BaseRequest] can
/// only be sent once.
///
/// ## Basic Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(),
///     SwrMiddleware(cache: cache),
///     RetryMiddleware(maxRetries: 3),
///   ],
/// );
/// ```
///
/// ## Placement
///
/// Place RetryMiddleware after caching middlewares (closer to the network),
/// so retries hit the network rather than re-entering the cache layer.
/// Responses served from cache and responses carrying a background
/// continuation are never retried.
///
/// ## Defaults
///
/// - Only idempotent methods are retried: GET, HEAD, OPTIONS, PUT, DELETE.
/// - Responses with status 408, 429 or 5xx are retried.
/// - [http.ClientException] and [TimeoutException] errors are retried.
/// - Delay is exponential: 200ms, 400ms, 800ms, ... capped at ~12.8s.
///
/// All of these are configurable:
///
/// ```dart
/// RetryMiddleware(
///   maxRetries: 5,
///   shouldRetryRequest: (request) => request.method != 'POST',
///   shouldRetryResponse: (response) => response.statusCode == 503,
///   shouldRetryError: (error) => error is http.ClientException,
///   delay: (attempt) => Duration(seconds: attempt),
/// )
/// ```
///
/// ## Unclonable requests
///
/// Requests that cannot be cloned (e.g. [http.StreamedRequest]) are sent
/// once and never retried.
class RetryMiddleware extends HttpMiddleware {
  /// Creates a retry middleware.
  ///
  /// [maxRetries] is the number of retries after the initial attempt,
  /// so the request is sent at most `maxRetries + 1` times.
  RetryMiddleware({
    this.maxRetries = 3,
    ShouldRetryRequest? shouldRetryRequest,
    ShouldRetryResponse? shouldRetryResponse,
    ShouldRetryError? shouldRetryError,
    RetryDelay? delay,
  }) : shouldRetryRequest = shouldRetryRequest ?? _defaultShouldRetryRequest,
       shouldRetryResponse = shouldRetryResponse ?? _defaultShouldRetryResponse,
       shouldRetryError = shouldRetryError ?? _defaultShouldRetryError,
       delay = delay ?? _defaultDelay;

  /// Maximum number of retries after the initial attempt.
  final int maxRetries;

  /// Whether a request is eligible for retries.
  final ShouldRetryRequest shouldRetryRequest;

  /// Whether a response should be retried.
  final ShouldRetryResponse shouldRetryResponse;

  /// Whether a thrown error should be retried.
  final ShouldRetryError shouldRetryError;

  /// Delay before each retry attempt.
  final RetryDelay delay;

  static const _idempotentMethods = {'GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'};

  static bool _defaultShouldRetryRequest(http.BaseRequest request) {
    return _idempotentMethods.contains(request.method);
  }

  static bool _defaultShouldRetryResponse(http.StreamedResponse response) {
    final status = response.statusCode;
    return status == 408 || status == 429 || status >= 500;
  }

  static bool _defaultShouldRetryError(Object error) {
    return error is http.ClientException || error is TimeoutException;
  }

  static Duration _defaultDelay(int attempt) {
    final exponent = attempt < 7 ? attempt - 1 : 6;
    return Duration(milliseconds: 200 * (1 << exponent));
  }

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    if (!shouldRetryRequest(context.request)) {
      return next(context);
    }

    var attemptContext = context;

    for (var attempt = 0; ; attempt++) {
      final MiddlewareResponse result;
      try {
        result = await next(attemptContext);
      } catch (error, stackTrace) {
        if (attempt >= maxRetries || !shouldRetryError(error)) {
          rethrow;
        }
        final retryContext = _cloneForRetry(context);
        if (retryContext == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        attemptContext = retryContext;
        await Future<void>.delayed(delay(attempt + 1));
        continue;
      }

      // Never retry cached responses or responses that carry a background
      // continuation - retrying would discard the continuation.
      if (attemptContext.isFromCache || result.hasBackgroundContinuation) {
        return result;
      }

      if (attempt >= maxRetries || !shouldRetryResponse(result.response)) {
        return result;
      }

      final retryContext = _cloneForRetry(context);
      if (retryContext == null) {
        return result;
      }

      // Free the failed response's resources before resending
      await result.response.stream.drain<void>();

      attemptContext = retryContext;
      await Future<void>.delayed(delay(attempt + 1));
    }
  }

  /// Clones the original request for a retry attempt.
  ///
  /// Returns null when the request cannot be cloned.
  static MiddlewareContext? _cloneForRetry(MiddlewareContext context) {
    try {
      return context.copyWith(
        request: MiddlewareContext.cloneRequest(context.request),
      );
    } on UnsupportedError {
      return null;
    }
  }
}
