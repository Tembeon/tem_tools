import 'dart:async';

import 'package:http/http.dart' as http;

import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// Builds headers for a request, possibly asynchronously.
///
/// Useful for values that must be fetched lazily, like an access token
/// from secure storage.
typedef HeadersBuilder =
    FutureOr<Map<String, String>> Function(http.BaseRequest request);

/// A middleware that applies default headers to every request.
///
/// By default, headers already present on the request win, so per-request
/// values are never silently clobbered. Set [overrideExisting] to true to
/// force the middleware's values.
///
/// ## Static headers
///
/// ```dart
/// HeadersMiddleware({
///   'User-Agent': 'my-app/1.2.0',
///   'Accept': 'application/json',
/// })
/// ```
///
/// ## Dynamic headers (e.g. auth tokens)
///
/// ```dart
/// HeadersMiddleware.builder((request) async {
///   final token = await tokenStorage.read();
///   return {'Authorization': 'Bearer $token'};
/// })
/// ```
///
/// Because background revalidations re-run the whole chain, they pick up
/// fresh header values too - a revalidation that happens after a token
/// refresh uses the new token.
class HeadersMiddleware extends HttpMiddleware {
  /// Creates a middleware that applies the static [headers] map.
  HeadersMiddleware(
    Map<String, String> headers, {
    this.overrideExisting = false,
  }) : _builder = ((_) => headers);

  /// Creates a middleware that builds headers per request via [builder].
  HeadersMiddleware.builder(
    HeadersBuilder builder, {
    this.overrideExisting = false,
  }) : _builder = builder;

  final HeadersBuilder _builder;

  /// Whether the middleware's headers replace values already present
  /// on the request. Defaults to false (request values win).
  final bool overrideExisting;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    final headers = await _builder(context.request);

    for (final entry in headers.entries) {
      if (overrideExisting) {
        context.request.headers[entry.key] = entry.value;
      } else {
        context.request.headers.putIfAbsent(entry.key, () => entry.value);
      }
    }

    return next(context);
  }
}
