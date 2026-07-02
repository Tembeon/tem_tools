import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A cached representation of an HTTP response that can be stored and
/// converted back to [http.StreamedResponse] multiple times.
///
/// Since [http.StreamedResponse.stream] can only be consumed once,
/// this class captures all response data including the body bytes,
/// allowing multiple [http.StreamedResponse] instances to be created
/// from the same cached data.
///
/// ## Usage
///
/// ### Caching a response
/// ```dart
/// final response = await client.send(request);
/// final cached = await CachedResponse.fromStreamedResponse(response);
/// await cache.store(key, cached);
/// ```
///
/// ### Restoring from cache
/// ```dart
/// final cached = await cache.get(key);
/// if (cached != null) {
///   return cached.toStreamedResponse();
/// }
/// ```
///
/// ## Memory Considerations
///
/// This class buffers the entire response body in memory. For large responses,
/// consider implementing size limits in your cache or using a streaming cache.
class CachedResponse {
  /// Creates a cached response with all required fields.
  const CachedResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    this.reasonPhrase,
    this.contentLength,
    this.isRedirect = false,
    this.persistentConnection = true,
    this.cachedAt,
  });

  /// Creates a [CachedResponse] from an [http.StreamedResponse].
  ///
  /// This consumes the response stream to capture the body bytes.
  /// After calling this, the original response's stream is exhausted
  /// and cannot be read again.
  ///
  /// Example:
  /// ```dart
  /// final response = await next(context);
  /// final cached = await CachedResponse.fromStreamedResponse(response.response);
  /// await cache.store(cacheKey, cached);
  ///
  /// // Return a new response since the original stream was consumed
  /// return MiddlewareResponse(response: cached.toStreamedResponse());
  /// ```
  static Future<CachedResponse> fromStreamedResponse(
    http.StreamedResponse response,
  ) async {
    final body = await response.stream.toBytes();
    return CachedResponse(
      statusCode: response.statusCode,
      body: body,
      headers: Map<String, String>.from(response.headers),
      reasonPhrase: response.reasonPhrase,
      contentLength: response.contentLength,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      cachedAt: DateTime.now(),
    );
  }

  /// The HTTP status code.
  final int statusCode;

  /// The response body bytes.
  final Uint8List body;

  /// The response headers.
  final Map<String, String> headers;

  /// The reason phrase associated with the status code.
  final String? reasonPhrase;

  /// The content length, if known.
  final int? contentLength;

  /// Whether this response is a redirect.
  final bool isRedirect;

  /// Whether the connection is persistent.
  final bool persistentConnection;

  /// When this response was captured from the network.
  ///
  /// Set automatically by [fromStreamedResponse]. Useful for implementing
  /// TTL or staleness checks in cache backends. Null for manually
  /// constructed instances that don't provide it.
  final DateTime? cachedAt;

  /// Creates a new [http.StreamedResponse] from the cached data.
  ///
  /// Each call creates a fresh response with a new stream,
  /// so this can be called multiple times.
  ///
  /// The response's `contentLength` is always the buffered body length:
  /// the original value may describe the compressed body, while [body]
  /// holds the decoded bytes.
  ///
  /// [request] is optionally attached to the response so consumers can
  /// read `response.request` as they would for a network response.
  ///
  /// Example:
  /// ```dart
  /// final cached = await cache.get(key);
  /// if (cached != null) {
  ///   return MiddlewareResponse(response: cached.toStreamedResponse());
  /// }
  /// ```
  http.StreamedResponse toStreamedResponse({http.BaseRequest? request}) {
    return http.StreamedResponse(
      Stream.value(body),
      statusCode,
      headers: headers,
      reasonPhrase: reasonPhrase,
      contentLength: body.length,
      isRedirect: isRedirect,
      persistentConnection: persistentConnection,
      request: request,
    );
  }

  /// Returns the body as a UTF-8 decoded string.
  ///
  /// Useful for debugging or when you know the response is text.
  String get bodyString => utf8.decode(body, allowMalformed: true);

  /// Returns the size of the cached body in bytes.
  int get sizeInBytes => body.length;

  @override
  String toString() {
    return 'CachedResponse('
        'status: $statusCode, '
        'size: $sizeInBytes bytes, '
        'headers: ${headers.keys.join(', ')})';
  }
}
