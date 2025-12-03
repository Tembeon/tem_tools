import 'dart:async';

import 'package:http/http.dart' as http;

import 'http_middleware.dart';
import 'middleware_context.dart';
import 'middleware_response.dart';

/// An HTTP client that processes requests through a middleware chain.
///
/// [MiddlewareClient] extends [http.BaseClient], making it a drop-in
/// replacement for any code using the `http` package. Requests pass
/// through each middleware in order before reaching the network.
///
/// ## Basic Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(),
///     AuthMiddleware(token: 'secret'),
///     RetryMiddleware(maxRetries: 3),
///   ],
/// );
///
/// final response = await client.get(Uri.parse('https://api.example.com/data'));
/// print(response.body);
///
/// client.close();
/// ```
///
/// ## Middleware Order
///
/// Middlewares execute in the order provided. The first middleware
/// wraps all subsequent middlewares:
///
/// ```
/// Request flow:  Client -> M1 -> M2 -> M3 -> Network
/// Response flow: Client <- M1 <- M2 <- M3 <- Network
/// ```
///
/// ## Background Continuation
///
/// Middlewares can return responses immediately while continuing
/// the request in the background (Stale-While-Revalidate pattern):
///
/// ```dart
/// // In a cache middleware:
/// if (cachedResponse != null) {
///   return MiddlewareResponse.withBackgroundContinuation(
///     response: cachedResponse,
///     backgroundContext: context.copyWith()..markAsBackground(),
///   );
/// }
/// ```
///
/// Background operations:
/// - Run asynchronously (fire-and-forget)
/// - Go through the full middleware chain
/// - Have errors handled via [HttpMiddleware.onBackgroundError]
/// - Automatically drain response streams to prevent leaks
///
/// ## Custom Inner Client
///
/// You can provide a custom inner client for testing or special configurations:
///
/// ```dart
/// final client = MiddlewareClient(
///   inner: MockClient((request) async => Response('test', 200)),
///   middlewares: [LoggingMiddleware()],
/// );
/// ```
class MiddlewareClient extends http.BaseClient {
  /// Creates a middleware client.
  ///
  /// [inner] is the underlying HTTP client used for actual network requests.
  /// If not provided, a default [http.Client] is created.
  ///
  /// [middlewares] is the list of middlewares to apply to each request.
  /// Middlewares are executed in the order provided.
  MiddlewareClient({
    http.Client? inner,
    List<HttpMiddleware> middlewares = const [],
  }) : _inner = inner ?? http.Client(),
       _middlewares = List.unmodifiable(middlewares);

  final http.Client _inner;
  final List<HttpMiddleware> _middlewares;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final context = MiddlewareContext(request: request);

    // Build and execute the middleware chain
    final middlewareResponse = await _buildChain(context);

    // If there's a background continuation, run it asynchronously
    if (middlewareResponse.hasBackgroundContinuation) {
      _runBackgroundContinuation(middlewareResponse.backgroundContext!);
    }

    return middlewareResponse.response;
  }

  /// Builds and executes the middleware chain.
  Future<MiddlewareResponse> _buildChain(MiddlewareContext context) {
    // Terminal handler: makes the actual HTTP request
    Future<MiddlewareResponse> terminal(MiddlewareContext ctx) async {
      final response = await _inner.send(ctx.request);
      return MiddlewareResponse.immediate(response);
    }

    // Build chain by wrapping handlers from last to first
    // Result: m1(m2(m3(terminal)))
    // Execution: m1 -> m2 -> m3 -> network -> m3 -> m2 -> m1
    MiddlewareNext handler = terminal;

    for (final middleware in _middlewares.reversed) {
      final next = handler;
      handler = (ctx) => middleware.process(ctx, next);
    }

    return handler(context);
  }

  /// Runs a background continuation asynchronously.
  ///
  /// This is fire-and-forget: the method returns immediately
  /// while the continuation runs in the background.
  void _runBackgroundContinuation(MiddlewareContext context) {
    // Ensure the context is marked as background
    context.markAsBackground();

    // Schedule the background operation to run asynchronously
    // Using unawaited Future to ensure it's scheduled properly
    Future(() async {
      try {
        // Execute the full middleware chain
        final response = await _buildChain(context);

        // Drain the response stream to prevent resource leaks
        await response.response.stream.drain<void>();
      } catch (error, stackTrace) {
        // Notify all middlewares of the background error
        for (final middleware in _middlewares) {
          try {
            middleware.onBackgroundError(error, stackTrace);
          } catch (_) {
            // Ignore errors from error handlers
          }
        }
      }
    });
  }

  @override
  void close() => _inner.close();
}
