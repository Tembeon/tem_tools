import 'dart:async';

import 'package:http/http.dart' as http;

import '../cached_response.dart';
import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// Function to generate a deduplication key from a request.
typedef DedupKeyGenerator = String Function(http.BaseRequest request);

/// Function to determine if a request should be deduplicated.
typedef ShouldDedupRequest = bool Function(http.BaseRequest request);

/// A middleware that deduplicates concurrent identical requests.
///
/// When multiple identical requests are made simultaneously, only one
/// network request is sent and all callers share the same response.
/// This prevents redundant network traffic and server load.
///
/// ## How It Works
///
/// 1. Request comes in, a dedup key is generated
/// 2. If an identical request is already in-flight:
///    - The new request waits for the existing one
///    - Both callers receive the same response
/// 3. If no identical request is in-flight:
///    - The request proceeds normally
///    - The response is shared with any subsequent identical requests
///
/// ## Basic Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     DedupMiddleware(),
///   ],
/// );
///
/// // These requests are deduplicated - only one network call is made
/// final futures = await Future.wait([
///   client.get(Uri.parse('https://api.example.com/data')),
///   client.get(Uri.parse('https://api.example.com/data')),
///   client.get(Uri.parse('https://api.example.com/data')),
/// ]);
/// ```
///
/// ## Custom Key Generation
///
/// By default, dedup keys are `METHOD:URL`. You can customize this:
///
/// ```dart
/// DedupMiddleware(
///   keyGenerator: (request) {
///     // Include specific headers in the key
///     final userId = request.headers['X-User-Id'] ?? '';
///     return '${request.method}:${request.url}:$userId';
///   },
/// )
/// ```
///
/// ## Conditional Deduplication
///
/// Control which requests get deduplicated:
///
/// ```dart
/// DedupMiddleware(
///   // Only dedup GET and HEAD requests (default)
///   shouldDedup: (request) =>
///       request.method == 'GET' || request.method == 'HEAD',
/// )
/// ```
///
/// ## Integration with Other Middlewares
///
/// Place DedupMiddleware early in the chain so it can deduplicate
/// before other middlewares process the request:
///
/// ```dart
/// MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(),      // Logs all requests
///     DedupMiddleware(),        // Deduplicates identical requests
///     SwrMiddleware(cache: cache), // Cache layer
///   ],
/// )
/// ```
///
/// ## Metadata
///
/// The middleware sets `dedup:key` in the context metadata with the
/// generated dedup key, and `dedup:shared` to `true` for requests
/// that shared a response with another in-flight request.
class DedupMiddleware extends HttpMiddleware {
  /// Creates a deduplication middleware.
  ///
  /// [keyGenerator] generates dedup keys from requests.
  /// Defaults to `METHOD:URL`.
  ///
  /// [shouldDedup] determines if a request should be deduplicated.
  /// Defaults to only deduplicating GET and HEAD requests.
  DedupMiddleware({
    DedupKeyGenerator? keyGenerator,
    ShouldDedupRequest? shouldDedup,
  })  : keyGenerator = keyGenerator ?? _defaultKeyGenerator,
        shouldDedup = shouldDedup ?? _defaultShouldDedup;

  /// Function to generate dedup keys.
  final DedupKeyGenerator keyGenerator;

  /// Function to determine if a request should be deduplicated.
  final ShouldDedupRequest shouldDedup;

  /// Map of in-flight requests by their dedup key.
  ///
  /// Each entry contains a completer that will complete when the
  /// request finishes, along with the cached response data.
  final Map<String, _InFlightRequest> _inFlight = {};

  static String _defaultKeyGenerator(http.BaseRequest request) {
    return '${request.method}:${request.url}';
  }

  static bool _defaultShouldDedup(http.BaseRequest request) {
    return request.method == 'GET' || request.method == 'HEAD';
  }

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    // Don't dedup background requests - they should always go through
    if (context.isBackground) {
      return next(context);
    }

    // Check if this request should be deduplicated
    if (!shouldDedup(context.request)) {
      return next(context);
    }

    final key = keyGenerator(context.request);

    // Store key in metadata for other middlewares
    context.metadata['dedup:key'] = key;

    // Check if there's already an in-flight request
    final existing = _inFlight[key];
    if (existing != null) {
      // Wait for the existing request and share its response
      context.metadata['dedup:shared'] = true;
      final cached = await existing.completer.future;
      return MiddlewareResponse.immediate(cached.toStreamedResponse());
    }

    // No existing request - start a new one
    final inFlightRequest = _InFlightRequest();
    _inFlight[key] = inFlightRequest;

    try {
      final response = await next(context);

      // Cache the response body so it can be shared
      final cached =
          await CachedResponse.fromStreamedResponse(response.response);

      // Complete the in-flight tracker so waiting requests get the response
      inFlightRequest.completer.complete(cached);

      // Return a fresh streamed response from the cached data
      // Handle background continuation if present
      if (response.hasBackgroundContinuation) {
        return MiddlewareResponse.withBackgroundContinuation(
          response: cached.toStreamedResponse(),
          backgroundContext: response.backgroundContext!,
        );
      }

      return MiddlewareResponse.immediate(cached.toStreamedResponse());
    } catch (e, st) {
      // Propagate the error to all waiting requests
      inFlightRequest.completer.completeError(e, st);
      rethrow;
    } finally {
      // Always clean up the in-flight tracker
      _inFlight.remove(key);
    }
  }

  /// Returns the number of requests currently in-flight.
  ///
  /// Useful for testing and debugging.
  int get inFlightCount => _inFlight.length;

  /// Returns all dedup keys for requests currently in-flight.
  ///
  /// Useful for testing and debugging.
  Iterable<String> get inFlightKeys => _inFlight.keys;
}

/// Tracks an in-flight request for deduplication.
class _InFlightRequest {
  _InFlightRequest() {
    // Prevent unhandled async error when completeError is called
    // but no one is listening to the future yet
    completer.future.ignore();
  }

  /// Completer that will complete when the request finishes.
  final Completer<CachedResponse> completer = Completer<CachedResponse>();
}
