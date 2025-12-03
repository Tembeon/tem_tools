// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
import 'package:http_middleware/http_middleware.dart';

/// Example demonstrating the HTTP middleware system.
///
/// This example shows:
/// - Basic middleware usage with logging
/// - Custom middleware creation
/// - SWR (Stale-While-Revalidate) caching
/// - Background continuation
void main() async {
  // Example 1: Basic usage with logging
  print('=== Example 1: Basic Logging ===\n');
  await basicLoggingExample();

  // Example 2: Custom middleware
  print('\n=== Example 2: Custom Middleware ===\n');
  await customMiddlewareExample();

  // Example 3: SWR caching
  print('\n=== Example 3: SWR Caching ===\n');
  await swrCachingExample();

  // Example 4: Multiple middlewares
  print('\n=== Example 4: Middleware Chain ===\n');
  await middlewareChainExample();
}

/// Demonstrates basic logging middleware usage.
Future<void> basicLoggingExample() async {
  final client = MiddlewareClient(middlewares: [LoggingMiddleware()]);

  try {
    final response = await client.get(Uri.parse('https://httpbin.dev/get'));
    print('Response status: ${response.statusCode}');
  } finally {
    client.close();
  }
}

/// Demonstrates creating a custom middleware.
Future<void> customMiddlewareExample() async {
  final client = MiddlewareClient(
    middlewares: [
      // Custom auth middleware
      AuthMiddleware(token: 'my-secret-token'),
      // Logging to see the auth header was added
      LoggingMiddleware(includeHeaders: true),
    ],
  );

  try {
    final response = await client.get(Uri.parse('https://httpbin.dev/headers'));
    print('Response: ${response.body}');
  } finally {
    client.close();
  }
}

/// Demonstrates SWR (Stale-While-Revalidate) caching.
Future<void> swrCachingExample() async {
  final cache = InMemorySwrCache();

  final client = MiddlewareClient(
    middlewares: [
      LoggingMiddleware(),
      SwrMiddleware(cache: cache),
    ],
  );

  final uri = Uri.parse('https://httpbin.dev/uuid');

  // First request - cache miss, goes to network
  print('First request (cache miss):');
  final response1 = await client.get(uri);
  print('UUID: ${response1.body}\n');

  // Small delay to let background request complete
  await Future.delayed(const Duration(milliseconds: 100));

  // Second request - cache hit!
  // Returns instantly from cache
  // Background request refreshes cache
  print('Second request (cache hit + background revalidation):');
  final response2 = await client.get(uri);
  print('UUID (from cache): ${response2.body}\n');

  // Wait for background revalidation
  await Future.delayed(const Duration(seconds: 2));

  // Third request - returns the revalidated cache
  print('Third request (updated cache):');
  final response3 = await client.get(uri);
  print('UUID (refreshed): ${response3.body}');
}

/// Demonstrates a chain of multiple middlewares.
Future<void> middlewareChainExample() async {
  final client = MiddlewareClient(
    middlewares: [
      // Middlewares execute in order:
      // 1. Timing - wraps everything, measures total time
      TimingMiddleware(),
      // 2. Logging - logs request/response
      LoggingMiddleware(),
      // 3. Auth - adds authorization header
      AuthMiddleware(token: 'bearer-token'),
      // 4. Retry - handles transient failures
      RetryMiddleware(maxRetries: 2),
    ],
  );

  try {
    final response = await client.get(Uri.parse('https://httpbin.dev/get'));
    print('Final response status: ${response.statusCode}');
  } finally {
    client.close();
  }
}

// ============================================================================
// Custom Middleware Examples
// ============================================================================

/// A middleware that adds an Authorization header to requests.
class AuthMiddleware extends HttpMiddleware {
  const AuthMiddleware({required this.token});

  final String token;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    // Add auth header to the request
    final request = context.request;
    if (request is http.Request) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Continue to next middleware
    return next(context);
  }
}

/// A middleware that measures total request time.
class TimingMiddleware extends HttpMiddleware {
  const TimingMiddleware();

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final response = await next(context);
      stopwatch.stop();

      // Store timing in metadata for other middlewares
      context.metadata['timing:totalMs'] = stopwatch.elapsedMilliseconds;

      print('[TIMING] Total request time: ${stopwatch.elapsedMilliseconds}ms');

      return response;
    } catch (e) {
      stopwatch.stop();
      print('[TIMING] Request failed after ${stopwatch.elapsedMilliseconds}ms');
      rethrow;
    }
  }
}

/// A middleware that retries failed requests.
class RetryMiddleware extends HttpMiddleware {
  const RetryMiddleware({this.maxRetries = 3});

  final int maxRetries;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    var lastError = Object();
    StackTrace lastStackTrace = StackTrace.current;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          print('[RETRY] Attempt ${attempt + 1}/${maxRetries + 1}');
          // Exponential backoff
          await Future.delayed(Duration(milliseconds: 100 * (1 << attempt)));
        }

        return await next(context);
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;

        if (attempt == maxRetries) {
          break;
        }
      }
    }

    Error.throwWithStackTrace(lastError, lastStackTrace);
  }
}
