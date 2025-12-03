import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http_middleware/http_middleware.dart';
import 'package:test/test.dart';

void main() {
  group('MiddlewareContext', () {
    test('creates with request and empty metadata', () {
      final request = http.Request('GET', Uri.parse('https://example.com'));
      final context = MiddlewareContext(request: request);

      expect(context.request, equals(request));
      expect(context.metadata, isEmpty);
      expect(context.isFromCache, isFalse);
      expect(context.isBackground, isFalse);
    });

    test('marks as from cache', () {
      final request = http.Request('GET', Uri.parse('https://example.com'));
      final context = MiddlewareContext(request: request);

      context.markAsFromCache();

      expect(context.isFromCache, isTrue);
    });

    test('marks as background', () {
      final request = http.Request('GET', Uri.parse('https://example.com'));
      final context = MiddlewareContext(request: request);

      context.markAsBackground();

      expect(context.isBackground, isTrue);
    });

    test('copyWith creates independent copy', () {
      final request = http.Request('GET', Uri.parse('https://example.com'));
      final context = MiddlewareContext(request: request);
      context.metadata['key'] = 'value';

      final copy = context.copyWith();
      copy.metadata['key'] = 'modified';
      copy.markAsBackground();

      expect(context.metadata['key'], equals('value'));
      expect(context.isBackground, isFalse);
      expect(copy.metadata['key'], equals('modified'));
      expect(copy.isBackground, isTrue);
    });
  });

  group('MiddlewareResponse', () {
    test('immediate creates response without background', () {
      final streamedResponse = http.StreamedResponse(
        Stream.value(utf8.encode('test')),
        200,
      );

      final response = MiddlewareResponse.immediate(streamedResponse);

      expect(response.response, equals(streamedResponse));
      expect(response.hasBackgroundContinuation, isFalse);
      expect(response.backgroundContext, isNull);
    });

    test('withBackgroundContinuation includes context', () {
      final streamedResponse = http.StreamedResponse(
        Stream.value(utf8.encode('test')),
        200,
      );
      final request = http.Request('GET', Uri.parse('https://example.com'));
      final backgroundContext = MiddlewareContext(request: request);

      final response = MiddlewareResponse.withBackgroundContinuation(
        response: streamedResponse,
        backgroundContext: backgroundContext,
      );

      expect(response.response, equals(streamedResponse));
      expect(response.hasBackgroundContinuation, isTrue);
      expect(response.backgroundContext, equals(backgroundContext));
    });
  });

  group('CachedResponse', () {
    test('fromStreamedResponse captures all data', () async {
      final body = utf8.encode('{"data": "test"}');
      final streamedResponse = http.StreamedResponse(
        Stream.value(body),
        200,
        headers: {'content-type': 'application/json'},
        reasonPhrase: 'OK',
        contentLength: body.length,
      );

      final cached =
          await CachedResponse.fromStreamedResponse(streamedResponse);

      expect(cached.statusCode, equals(200));
      expect(cached.body, equals(body));
      expect(cached.headers['content-type'], equals('application/json'));
      expect(cached.reasonPhrase, equals('OK'));
      expect(cached.contentLength, equals(body.length));
    });

    test('toStreamedResponse creates fresh stream', () async {
      final body = Uint8List.fromList(utf8.encode('test body'));
      final cached = CachedResponse(
        statusCode: 201,
        body: body,
        headers: {'x-custom': 'header'},
        reasonPhrase: 'Created',
      );

      final response1 = cached.toStreamedResponse();
      final body1 = await response1.stream.toBytes();

      final response2 = cached.toStreamedResponse();
      final body2 = await response2.stream.toBytes();

      expect(body1, equals(body));
      expect(body2, equals(body));
      expect(response1.statusCode, equals(201));
      expect(response2.headers['x-custom'], equals('header'));
    });

    test('bodyString decodes UTF-8', () {
      final cached = CachedResponse(
        statusCode: 200,
        body: Uint8List.fromList(utf8.encode('Hello, World!')),
        headers: {},
      );

      expect(cached.bodyString, equals('Hello, World!'));
    });

    test('sizeInBytes returns body length', () {
      final cached = CachedResponse(
        statusCode: 200,
        body: Uint8List(100),
        headers: {},
      );

      expect(cached.sizeInBytes, equals(100));
    });
  });

  group('MiddlewareClient', () {
    test('sends request without middlewares', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"success": true}', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [],
      );

      final response = await client.get(Uri.parse('https://example.com/api'));

      expect(response.statusCode, equals(200));
      expect(response.body, equals('{"success": true}'));

      client.close();
    });

    test('executes middleware in correct order', () async {
      final order = <String>[];

      final mockClient = MockClient((request) async {
        order.add('network');
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [
          _OrderTrackingMiddleware('first', order),
          _OrderTrackingMiddleware('second', order),
          _OrderTrackingMiddleware('third', order),
        ],
      );

      await client.get(Uri.parse('https://example.com'));

      expect(order, [
        'first-before',
        'second-before',
        'third-before',
        'network',
        'third-after',
        'second-after',
        'first-after',
      ]);

      client.close();
    });

    test('middleware can modify request', () async {
      String? capturedAuth;

      final mockClient = MockClient((request) async {
        capturedAuth = request.headers['authorization'];
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [_AuthMiddleware('secret-token')],
      );

      await client.get(Uri.parse('https://example.com'));

      expect(capturedAuth, equals('Bearer secret-token'));

      client.close();
    });

    test('middleware can short-circuit with cached response', () async {
      var networkCalls = 0;

      final mockClient = MockClient((request) async {
        networkCalls++;
        return http.Response('from network', 200);
      });

      final cache = InMemorySwrCache();

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [SwrMiddleware(cache: cache)],
      );

      // First call - network
      final response1 = await client.get(Uri.parse('https://example.com'));
      expect(response1.body, equals('from network'));
      expect(networkCalls, equals(1));

      // Wait for any background operations
      await Future.delayed(const Duration(milliseconds: 50));

      // Second call - from cache (but triggers background revalidation)
      final response2 = await client.get(Uri.parse('https://example.com'));
      expect(response2.body, equals('from network'));
      // Network was not called synchronously (the cached response was returned)
      // But a background request may have been triggered

      client.close();
    });

    test('runs background continuation', () async {
      var requestCount = 0;
      var backgroundRequestMade = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (request.headers['x-background'] == 'true') {
          backgroundRequestMade = true;
        }
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [_BackgroundTriggerMiddleware()],
      );

      await client.get(Uri.parse('https://example.com'));

      // First request should have been made
      expect(requestCount, equals(1));

      // Wait for background continuation to complete
      // Background runs asynchronously, so give it time
      await Future.delayed(const Duration(milliseconds: 200));

      // Background request should have been made
      expect(requestCount, equals(2));
      expect(backgroundRequestMade, isTrue);

      client.close();
    });

    test('handles background errors silently', () async {
      var errorHandled = false;

      final mockClient = MockClient((request) async {
        if (request.headers['x-background'] == 'true') {
          throw Exception('Network error');
        }
        return http.Response('ok', 200);
      });

      final errorHandler = _ErrorHandlingMiddleware(
        onError: () => errorHandled = true,
      );

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [
          errorHandler,
          _BackgroundTriggerMiddleware(),
        ],
      );

      // Should not throw
      final response = await client.get(Uri.parse('https://example.com'));
      expect(response.statusCode, equals(200));

      // Wait for background error to be handled
      await Future.delayed(const Duration(milliseconds: 100));

      expect(errorHandled, isTrue);

      client.close();
    });
  });

  group('LoggingMiddleware', () {
    test('logs request and response', () async {
      final logs = <String>[];

      final mockClient = MockClient((request) async {
        return http.Response('ok', 200, reasonPhrase: 'OK');
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [LoggingMiddleware(onLog: logs.add)],
      );

      await client.get(Uri.parse('https://example.com/test'));

      expect(logs.length, equals(2));
      expect(logs[0], contains('GET'));
      expect(logs[0], contains('https://example.com/test'));
      expect(logs[1], contains('200'));
      expect(logs[1], contains('ms'));

      client.close();
    });

    test('logs background requests with prefix', () async {
      final logs = <String>[];

      final mockClient = MockClient((request) async {
        return http.Response('ok', 200, reasonPhrase: 'OK');
      });

      final request = http.Request('GET', Uri.parse('https://example.com'));
      final context = MiddlewareContext(request: request);
      context.markAsBackground();

      final middleware = LoggingMiddleware(onLog: logs.add);

      await middleware.process(
        context,
        (ctx) async => MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value([]), 200, reasonPhrase: 'OK'),
        ),
      );

      expect(logs[0], startsWith('[BG]'));
      expect(logs[1], startsWith('[BG]'));

      mockClient.close();
    });

    test('logs cache indicator', () async {
      final logs = <String>[];

      final request = http.Request('GET', Uri.parse('https://example.com'));
      final context = MiddlewareContext(request: request);
      context.markAsFromCache();

      final middleware = LoggingMiddleware(onLog: logs.add);

      await middleware.process(
        context,
        (ctx) async => MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value([]), 200, reasonPhrase: 'OK'),
        ),
      );

      expect(logs[1], contains('[CACHE]'));
    });
  });

  group('SwrMiddleware', () {
    test('caches successful GET requests', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final mockClient = MockClient((request) async {
        networkCalls++;
        return http.Response('response $networkCalls', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [SwrMiddleware(cache: cache)],
      );

      // First request - cache miss
      await client.get(Uri.parse('https://example.com/data'));
      expect(networkCalls, equals(1));
      expect(cache.length, equals(1));

      client.close();
    });

    test('does not cache non-GET requests by default', () async {
      final cache = InMemorySwrCache();

      final mockClient = MockClient((request) async {
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [SwrMiddleware(cache: cache)],
      );

      await client.post(Uri.parse('https://example.com/data'));

      expect(cache.length, equals(0));

      client.close();
    });

    test('returns cached response immediately on hit', () async {
      final cache = InMemorySwrCache();
      final networkCalls = <int>[];
      var callCount = 0;

      final mockClient = MockClient((request) async {
        callCount++;
        networkCalls.add(callCount);
        // Delay to simulate network latency
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response('response $callCount', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [SwrMiddleware(cache: cache)],
      );

      // First request - cache miss, network call
      final response1 = await client.get(Uri.parse('https://example.com'));
      expect(response1.body, equals('response 1'));

      // Second request - should return immediately from cache
      final stopwatch = Stopwatch()..start();
      final response2 = await client.get(Uri.parse('https://example.com'));
      stopwatch.stop();

      // Response should be from cache (fast)
      expect(response2.body, equals('response 1'));
      // Should return almost instantly (much faster than network delay)
      expect(stopwatch.elapsedMilliseconds, lessThan(30));

      // Wait for background revalidation
      await Future.delayed(const Duration(milliseconds: 100));

      // Background request should have been made
      expect(networkCalls.length, equals(2));

      client.close();
    });

    test('uses custom cache key generator', () async {
      final cache = InMemorySwrCache();

      final mockClient = MockClient((request) async {
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [
          SwrMiddleware(
            cache: cache,
            cacheKeyGenerator: (request) => 'custom:${request.url.path}',
          ),
        ],
      );

      await client.get(Uri.parse('https://example.com/test'));

      expect(cache.keys.first, equals('custom:/test'));

      client.close();
    });

    test('respects shouldCacheResponse', () async {
      final cache = InMemorySwrCache();

      final mockClient = MockClient((request) async {
        return http.Response('error', 500);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [SwrMiddleware(cache: cache)],
      );

      await client.get(Uri.parse('https://example.com'));

      // Should not cache 500 responses
      expect(cache.length, equals(0));

      client.close();
    });
  });

  group('InMemorySwrCache', () {
    test('stores and retrieves values', () async {
      final cache = InMemorySwrCache();
      final response = CachedResponse(
        statusCode: 200,
        body: Uint8List.fromList([1, 2, 3]),
        headers: {},
      );

      await cache.set('key', response);
      final retrieved = await cache.get('key');

      expect(retrieved, isNotNull);
      expect(retrieved!.statusCode, equals(200));
      expect(retrieved.body, equals([1, 2, 3]));
    });

    test('returns null for missing keys', () async {
      final cache = InMemorySwrCache();

      final result = await cache.get('nonexistent');

      expect(result, isNull);
    });

    test('removes values', () async {
      final cache = InMemorySwrCache();
      final response = CachedResponse(
        statusCode: 200,
        body: Uint8List(0),
        headers: {},
      );

      await cache.set('key', response);
      await cache.remove('key');

      expect(await cache.get('key'), isNull);
    });

    test('clears all values', () async {
      final cache = InMemorySwrCache();
      final response = CachedResponse(
        statusCode: 200,
        body: Uint8List(0),
        headers: {},
      );

      await cache.set('key1', response);
      await cache.set('key2', response);
      await cache.clear();

      expect(cache.length, equals(0));
    });
  });
}

// Test helpers

class _OrderTrackingMiddleware extends HttpMiddleware {
  const _OrderTrackingMiddleware(this.name, this.order);

  final String name;
  final List<String> order;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    order.add('$name-before');
    final response = await next(context);
    order.add('$name-after');
    return response;
  }
}

class _AuthMiddleware extends HttpMiddleware {
  const _AuthMiddleware(this.token);

  final String token;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    context.request.headers['authorization'] = 'Bearer $token';
    return next(context);
  }
}

class _BackgroundTriggerMiddleware extends HttpMiddleware {
  const _BackgroundTriggerMiddleware();

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    // If this is a background request, mark it
    if (context.isBackground) {
      context.request.headers['x-background'] = 'true';
      return next(context);
    }

    // Otherwise, return immediately and trigger background
    final response = await next(context);

    // Use copyForBackground to clone the request so it can be sent again
    final backgroundContext = context.copyForBackground();
    return MiddlewareResponse.withBackgroundContinuation(
      response: response.response,
      backgroundContext: backgroundContext,
    );
  }
}

class _ErrorHandlingMiddleware extends HttpMiddleware {
  _ErrorHandlingMiddleware({required this.onError});

  final void Function() onError;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) {
    return next(context);
  }

  @override
  void onBackgroundError(Object error, StackTrace stackTrace) {
    onError();
  }
}
