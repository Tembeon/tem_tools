import 'package:http/http.dart' as http;

/// A context object that carries request data and shared metadata through
/// the middleware chain.
///
/// The context allows middlewares to:
/// - Access and modify the current request
/// - Share data with other middlewares via [metadata]
/// - Track whether the response came from cache
///
/// Example:
/// ```dart
/// class MyMiddleware extends HttpMiddleware {
///   @override
///   Future<MiddlewareResponse> process(
///     MiddlewareContext context,
///     MiddlewareNext next,
///   ) async {
///     // Store data for downstream middlewares
///     context.metadata['requestStartTime'] = DateTime.now();
///
///     final response = await next(context);
///
///     // Read data from upstream middlewares
///     final cacheTags = context.metadata['cacheTags'] as List<String>?;
///
///     return response;
///   }
/// }
/// ```
class MiddlewareContext {
  /// Creates a new middleware context.
  ///
  /// [request] is the HTTP request being processed.
  /// [metadata] is an optional map for sharing data between middlewares.
  MiddlewareContext({
    required this.request,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  /// The HTTP request being processed through the middleware chain.
  final http.BaseRequest request;

  /// Shared metadata that can be used to pass data between middlewares.
  ///
  /// Conventions:
  /// - Use descriptive keys to avoid collisions (e.g., 'swr:cacheKey')
  /// - Keys starting with underscore are reserved for internal use
  ///
  /// Common internal keys:
  /// - `_isBackground`: true if this is a background revalidation request
  /// - `_isFromCache`: true if the response was served from cache
  final Map<String, dynamic> metadata;

  /// Returns true if the response was served from cache.
  ///
  /// This is set by cache middlewares (like SWR) to indicate that
  /// the response being returned is from cache rather than network.
  bool get isFromCache => metadata['_isFromCache'] == true;

  /// Returns true if this request is a background revalidation.
  ///
  /// Background requests are fire-and-forget operations triggered by
  /// middlewares like SWR to refresh stale cache entries.
  bool get isBackground => metadata['_isBackground'] == true;

  /// Marks the response as coming from cache.
  ///
  /// Call this in cache middlewares when returning a cached response.
  void markAsFromCache() => metadata['_isFromCache'] = true;

  /// Marks this request as a background operation.
  ///
  /// This is automatically set by [MiddlewareClient] when executing
  /// background continuations.
  void markAsBackground() => metadata['_isBackground'] = true;

  /// Creates a copy of this context with optionally modified values.
  ///
  /// If [request] is not provided, the current request is used.
  /// If [metadata] is not provided, a shallow copy of current metadata is used.
  ///
  /// This is useful when you need to modify the request but preserve
  /// the metadata, or when forking the context for background operations.
  MiddlewareContext copyWith({
    http.BaseRequest? request,
    Map<String, dynamic>? metadata,
  }) {
    return MiddlewareContext(
      request: request ?? this.request,
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
    );
  }

  /// Creates a copy suitable for background operations.
  ///
  /// This method clones the request so it can be sent again, which is
  /// necessary for patterns like SWR where the same request needs to be
  /// repeated in the background.
  ///
  /// The cloned context will have:
  /// - A fresh copy of the request (can be sent to the network)
  /// - A shallow copy of the metadata
  ///
  /// Example:
  /// ```dart
  /// final backgroundContext = context.copyForBackground();
  /// return MiddlewareResponse.withBackgroundContinuation(
  ///   response: cachedResponse,
  ///   backgroundContext: backgroundContext,
  /// );
  /// ```
  MiddlewareContext copyForBackground() {
    return MiddlewareContext(
      request: _cloneRequest(request),
      metadata: Map<String, dynamic>.from(metadata),
    );
  }

  /// Clones an HTTP request so it can be sent again.
  static http.BaseRequest _cloneRequest(http.BaseRequest original) {
    if (original is http.Request) {
      final clone = http.Request(original.method, original.url)
        ..headers.addAll(original.headers)
        ..bodyBytes = original.bodyBytes
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
      return clone;
    } else if (original is http.MultipartRequest) {
      final clone = http.MultipartRequest(original.method, original.url)
        ..headers.addAll(original.headers)
        ..fields.addAll(original.fields)
        ..files.addAll(original.files)
        ..followRedirects = original.followRedirects
        ..maxRedirects = original.maxRedirects
        ..persistentConnection = original.persistentConnection;
      return clone;
    } else if (original is http.StreamedRequest) {
      // StreamedRequest cannot be cloned because the stream can only be read once
      throw UnsupportedError(
        'StreamedRequest cannot be cloned for background operations. '
        'Use Request or MultipartRequest instead.',
      );
    }
    // Fallback for unknown request types
    throw UnsupportedError(
      'Cannot clone request of type ${original.runtimeType}. '
      'Only Request and MultipartRequest are supported.',
    );
  }

  @override
  String toString() {
    return 'MiddlewareContext('
        'request: ${request.method} ${request.url}, '
        'metadata: $metadata)';
  }
}
