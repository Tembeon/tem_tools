import 'dart:async';

import 'package:http/http.dart' as http;

import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// Signature of a full inline middleware handler.
typedef InlineHandler =
    Future<MiddlewareResponse> Function(
      MiddlewareContext context,
      MiddlewareNext next,
    );

/// Signature for a request visitor used by [InlineMiddleware.onRequest].
///
/// May mutate the request (e.g. add headers).
typedef RequestVisitor = FutureOr<void> Function(http.BaseRequest request);

/// Signature for a response visitor used by [InlineMiddleware.onResponse].
///
/// Must not consume `response.stream` - the stream can only be read once
/// and belongs to the caller.
typedef ResponseVisitor =
    FutureOr<void> Function(
      http.StreamedResponse response,
      MiddlewareContext context,
    );

/// A middleware built from a closure, for cases where a dedicated
/// [HttpMiddleware] subclass is overkill.
///
/// ## Full handler
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     InlineMiddleware((context, next) async {
///       context.metadata['trace:id'] = generateTraceId();
///       return next(context);
///     }),
///   ],
/// );
/// ```
///
/// ## Request-only
///
/// ```dart
/// InlineMiddleware.onRequest((request) {
///   request.headers['Authorization'] = 'Bearer $token';
/// })
/// ```
///
/// ## Response-only
///
/// ```dart
/// InlineMiddleware.onResponse((response, context) {
///   if (response.statusCode == 401) {
///     authState.markExpired();
///   }
/// })
/// ```
class InlineMiddleware extends HttpMiddleware {
  /// Creates a middleware from a full [InlineHandler].
  const InlineMiddleware(this._handler);

  /// Creates a middleware that runs [visit] on the request and continues
  /// the chain.
  ///
  /// Useful for mutating requests: auth headers, user agents, tracing.
  factory InlineMiddleware.onRequest(RequestVisitor visit) {
    return InlineMiddleware((context, next) async {
      await visit(context.request);
      return next(context);
    });
  }

  /// Creates a middleware that continues the chain and then runs [visit]
  /// on the response.
  ///
  /// [visit] is an observer: it must not consume the response stream.
  factory InlineMiddleware.onResponse(ResponseVisitor visit) {
    return InlineMiddleware((context, next) async {
      final response = await next(context);
      await visit(response.response, context);
      return response;
    });
  }

  final InlineHandler _handler;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) {
    return _handler(context, next);
  }
}
