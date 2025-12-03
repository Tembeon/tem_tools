/// A flexible HTTP middleware system for Dart.
///
/// This package provides a middleware architecture for HTTP clients,
/// allowing you to intercept, modify, and extend HTTP requests and responses.
///
/// ## Features
///
/// - **Class-based middlewares** - Extend [HttpMiddleware] for clean,
///   testable middleware implementations
/// - **Pipe pattern** - Middlewares chain together naturally
/// - **Background continuation** - Return responses immediately while
///   continuing requests in the background (SWR pattern)
/// - **Context sharing** - Pass data between middlewares via [MiddlewareContext]
///
/// ## Quick Start
///
/// ```dart
/// import 'package:http_middleware/http_middleware.dart';
///
/// void main() async {
///   final client = MiddlewareClient(
///     middlewares: [
///       LoggingMiddleware(),
///       SwrMiddleware(cache: InMemorySwrCache()),
///     ],
///   );
///
///   final response = await client.get(Uri.parse('https://api.example.com'));
///   print(response.body);
///
///   client.close();
/// }
/// ```
///
/// ## Creating Custom Middlewares
///
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
///     context.request.headers['Authorization'] = 'Bearer $token';
///     return next(context);
///   }
/// }
/// ```
///
/// See [HttpMiddleware] for more details on creating middlewares.
library;

// Core classes
export 'src/cached_response.dart';
export 'src/http_middleware.dart';
export 'src/http_middleware_client.dart';
export 'src/middleware_context.dart';
export 'src/middleware_response.dart';

// Built-in middlewares
export 'src/middlewares/dedup_middleware.dart';
export 'src/middlewares/logging_middleware.dart';
export 'src/middlewares/swr_middleware.dart';
