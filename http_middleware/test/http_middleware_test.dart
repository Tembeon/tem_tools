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

      final cached = await CachedResponse.fromStreamedResponse(
        streamedResponse,
      );

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

    test('bodyString decodes multi-byte UTF-8', () {
      final cached = CachedResponse(
        statusCode: 200,
        body: Uint8List.fromList(utf8.encode('Привет, мир!')),
        headers: {},
      );

      expect(cached.bodyString, equals('Привет, мир!'));
    });

    test('fromStreamedResponse sets cachedAt', () async {
      final streamedResponse = http.StreamedResponse(
        Stream.value(utf8.encode('test')),
        200,
      );

      final cached = await CachedResponse.fromStreamedResponse(
        streamedResponse,
      );

      expect(cached.cachedAt, isNotNull);
    });

    test('toStreamedResponse reports buffered body length', () async {
      final body = Uint8List.fromList(utf8.encode('decoded body'));
      final cached = CachedResponse(
        statusCode: 200,
        body: body,
        headers: {},
        // Stale value, e.g. length of the compressed body
        contentLength: 5,
      );

      expect(cached.toStreamedResponse().contentLength, equals(body.length));
    });

    test('toStreamedResponse attaches request', () {
      final request = http.Request('GET', Uri.parse('https://example.com'));
      final cached = CachedResponse(
        statusCode: 200,
        body: Uint8List(0),
        headers: {},
      );

      final response = cached.toStreamedResponse(request: request);

      expect(response.request, same(request));
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

      final client = MiddlewareClient(inner: mockClient, middlewares: []);

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
        middlewares: [errorHandler, _BackgroundTriggerMiddleware()],
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

    test(
      'background revalidation context is not marked as from cache',
      () async {
        final cache = InMemorySwrCache();
        final backgroundContexts = <MiddlewareContext>[];

        final mockClient = MockClient((request) async {
          return http.Response('ok', 200);
        });

        final client = MiddlewareClient(
          inner: mockClient,
          middlewares: [
            _ContextCaptureMiddleware(backgroundContexts, onlyBackground: true),
            SwrMiddleware(cache: cache),
          ],
        );

        final uri = Uri.parse('https://example.com');
        await client.get(uri);
        // Cache hit triggers a background revalidation
        await client.get(uri);
        await Future.delayed(const Duration(milliseconds: 100));

        expect(backgroundContexts, hasLength(1));
        expect(backgroundContexts.single.isFromCache, isFalse);

        client.close();
      },
    );

    test('concurrent cache hits trigger a single revalidation', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final mockClient = MockClient((request) async {
        networkCalls++;
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com');
      await client.get(uri);
      expect(networkCalls, equals(1));

      // Concurrent cache hits: each would previously spawn a revalidation
      await Future.wait([client.get(uri), client.get(uri), client.get(uri)]);
      await Future.delayed(const Duration(milliseconds: 200));

      // Only one background revalidation should have happened
      expect(networkCalls, equals(2));

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

  group('DedupMiddleware', () {
    test('deduplicates concurrent identical GET requests', () async {
      var networkCalls = 0;
      final completer = Completer<MiddlewareResponse>();
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');

      Future<MiddlewareResponse> next(MiddlewareContext ctx) {
        networkCalls++;
        return completer.future;
      }

      // Start multiple concurrent requests
      final future1 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );
      final future3 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );

      // Only one network call should be made
      expect(networkCalls, equals(1));

      // Complete the request
      completer.complete(
        MiddlewareResponse.immediate(
          http.StreamedResponse(
            Stream.value(utf8.encode('shared response')),
            200,
          ),
        ),
      );

      // All futures should resolve
      final responses = await Future.wait([future1, future2, future3]);

      for (final response in responses) {
        final body = await response.response.stream.bytesToString();
        expect(body, equals('shared response'));
        expect(response.response.statusCode, equals(200));
      }

      // Still only one network call
      expect(networkCalls, equals(1));
    });

    test('does not deduplicate non-GET/HEAD requests by default', () async {
      var networkCalls = 0;
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');

      Future<MiddlewareResponse> next(MiddlewareContext ctx) async {
        networkCalls++;
        return MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(utf8.encode('ok')), 200),
        );
      }

      // Start multiple concurrent POST requests
      final future1 = dedup.process(
        MiddlewareContext(request: http.Request('POST', uri)),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(request: http.Request('POST', uri)),
        next,
      );

      await Future.wait([future1, future2]);

      // Both POST requests should go to network (not deduplicated)
      expect(networkCalls, equals(2));
    });

    test('deduplicates HEAD requests', () async {
      var networkCalls = 0;
      final completer = Completer<MiddlewareResponse>();
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');

      Future<MiddlewareResponse> next(MiddlewareContext ctx) {
        networkCalls++;
        return completer.future;
      }

      final future1 = dedup.process(
        MiddlewareContext(request: http.Request('HEAD', uri)),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(request: http.Request('HEAD', uri)),
        next,
      );

      expect(networkCalls, equals(1));

      completer.complete(
        MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value([]), 200),
        ),
      );

      await Future.wait([future1, future2]);

      expect(networkCalls, equals(1));
    });

    test('different URLs are not deduplicated', () async {
      var networkCalls = 0;
      final dedup = DedupMiddleware();

      Future<MiddlewareResponse> next(MiddlewareContext ctx) async {
        networkCalls++;
        return MiddlewareResponse.immediate(
          http.StreamedResponse(
            Stream.value(utf8.encode('response ${ctx.request.url}')),
            200,
          ),
        );
      }

      final future1 = dedup.process(
        MiddlewareContext(
          request: http.Request('GET', Uri.parse('https://example.com/a')),
        ),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(
          request: http.Request('GET', Uri.parse('https://example.com/b')),
        ),
        next,
      );

      final responses = await Future.wait([future1, future2]);

      // Both different URLs should make network calls
      expect(networkCalls, equals(2));

      final body1 = await responses[0].response.stream.bytesToString();
      final body2 = await responses[1].response.stream.bytesToString();
      expect(body1, contains('/a'));
      expect(body2, contains('/b'));
    });

    test('sequential requests are not deduplicated', () async {
      var networkCalls = 0;
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');

      Future<MiddlewareResponse> next(MiddlewareContext ctx) async {
        networkCalls++;
        return MiddlewareResponse.immediate(
          http.StreamedResponse(
            Stream.value(utf8.encode('response $networkCalls')),
            200,
          ),
        );
      }

      // Sequential requests (not concurrent)
      final response1 = await dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );
      final response2 = await dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );

      // Both should make network calls since they're not concurrent
      expect(networkCalls, equals(2));

      final body1 = await response1.response.stream.bytesToString();
      final body2 = await response2.response.stream.bytesToString();
      expect(body1, equals('response 1'));
      expect(body2, equals('response 2'));
    });

    test('propagates errors to all waiting requests', () async {
      var networkCalls = 0;
      final completer = Completer<MiddlewareResponse>();
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');

      Future<MiddlewareResponse> next(MiddlewareContext ctx) {
        networkCalls++;
        return completer.future;
      }

      final future1 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );

      expect(networkCalls, equals(1));

      // Complete with error
      completer.completeError(Exception('Network error'));

      // Both futures should fail with the same error
      await expectLater(future1, throwsException);
      await expectLater(future2, throwsException);
    });

    test('uses custom key generator', () async {
      var networkCalls = 0;
      final completer = Completer<MiddlewareResponse>();
      final dedup = DedupMiddleware(
        // Only use URL path as key (ignore query params)
        keyGenerator: (request) => request.url.path,
      );

      Future<MiddlewareResponse> next(MiddlewareContext ctx) {
        networkCalls++;
        return completer.future;
      }

      // Different query params but same path - should be deduplicated
      final future1 = dedup.process(
        MiddlewareContext(
          request: http.Request(
            'GET',
            Uri.parse('https://example.com/data?v=1'),
          ),
        ),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(
          request: http.Request(
            'GET',
            Uri.parse('https://example.com/data?v=2'),
          ),
        ),
        next,
      );

      expect(networkCalls, equals(1));

      completer.complete(
        MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(utf8.encode('shared')), 200),
        ),
      );

      final responses = await Future.wait([future1, future2]);

      final body1 = await responses[0].response.stream.bytesToString();
      final body2 = await responses[1].response.stream.bytesToString();
      expect(body1, equals('shared'));
      expect(body2, equals('shared'));
    });

    test('uses custom shouldDedup function', () async {
      var networkCalls = 0;
      final dedup = DedupMiddleware(
        // Disable dedup for all requests
        shouldDedup: (request) => false,
      );
      final uri = Uri.parse('https://example.com/data');

      Future<MiddlewareResponse> next(MiddlewareContext ctx) async {
        networkCalls++;
        return MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(utf8.encode('ok')), 200),
        );
      }

      final future1 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );
      final future2 = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        next,
      );

      await Future.wait([future1, future2]);

      // Both requests should go to network (dedup disabled)
      expect(networkCalls, equals(2));
    });

    test('sets metadata for dedup key', () async {
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');
      MiddlewareContext? capturedContext;

      await dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        (ctx) async {
          capturedContext = ctx;
          return MiddlewareResponse.immediate(
            http.StreamedResponse(Stream.value(utf8.encode('ok')), 200),
          );
        },
      );

      // Request should have dedup key in metadata
      expect(capturedContext!.metadata['dedup:key'], equals('GET:$uri'));
    });

    test('marks shared requests in metadata', () async {
      final completer = Completer<MiddlewareResponse>();
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');

      // Track contexts - first request goes to next(), shared ones don't
      MiddlewareContext? firstContext;

      // First request - goes to network
      final context1 = MiddlewareContext(request: http.Request('GET', uri));
      final future1 = dedup.process(context1, (ctx) {
        firstContext = ctx;
        return completer.future;
      });

      // Second request - should be deduplicated (won't call next)
      final context2 = MiddlewareContext(request: http.Request('GET', uri));
      final future2 = dedup.process(context2, (ctx) async {
        fail('Second request should not reach next()');
      });

      completer.complete(
        MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(utf8.encode('ok')), 200),
        ),
      );

      await Future.wait([future1, future2]);

      // First request should have dedup key
      expect(firstContext!.metadata['dedup:key'], equals('GET:$uri'));

      // Second context should be marked as shared
      expect(context2.metadata['dedup:shared'], isTrue);
    });

    test('cleans up in-flight tracker after completion', () async {
      final dedup = DedupMiddleware();

      expect(dedup.inFlightCount, equals(0));

      await dedup.process(
        MiddlewareContext(
          request: http.Request('GET', Uri.parse('https://example.com/data')),
        ),
        (ctx) async => MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(utf8.encode('ok')), 200),
        ),
      );

      // Should be cleaned up after request completes
      expect(dedup.inFlightCount, equals(0));
    });

    test('cleans up in-flight tracker after error', () async {
      final dedup = DedupMiddleware();

      expect(dedup.inFlightCount, equals(0));

      // Create a completer that will throw when awaited
      final errorCompleter = Completer<MiddlewareResponse>();

      final future = dedup.process(
        MiddlewareContext(
          request: http.Request('GET', Uri.parse('https://example.com/data')),
        ),
        (ctx) => errorCompleter.future,
      );

      // Trigger the error
      errorCompleter.completeError(Exception('Network error'));

      // Should throw
      await expectLater(future, throwsA(isA<Exception>()));

      // Should be cleaned up even after error
      expect(dedup.inFlightCount, equals(0));
    });

    test('does not deduplicate background requests', () async {
      var nextCalls = 0;
      final dedup = DedupMiddleware();

      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com')),
      );
      context.markAsBackground();

      // Process as background request
      await dedup.process(context, (ctx) async {
        nextCalls++;
        return MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(utf8.encode('ok')), 200),
        );
      });

      // Background requests should not be tracked (they pass through)
      expect(dedup.inFlightCount, equals(0));
      expect(nextCalls, equals(1));
    });

    test(
      'returns response unbuffered when no concurrent request joined',
      () async {
        final dedup = DedupMiddleware();
        final original = http.StreamedResponse(
          Stream.value(utf8.encode('ok')),
          200,
        );

        final result = await dedup.process(
          MiddlewareContext(
            request: http.Request('GET', Uri.parse('https://example.com')),
          ),
          (ctx) async => MiddlewareResponse.immediate(original),
        );

        // The exact same response object passes through - no buffering
        expect(result.response, same(original));
      },
    );

    test(
      'preserves background continuation from downstream middleware',
      () async {
        final dedup = DedupMiddleware();
        final uri = Uri.parse('https://example.com/data');

        // Simulate a downstream middleware that returns a background continuation
        final response = await dedup.process(
          MiddlewareContext(request: http.Request('GET', uri)),
          (ctx) async {
            final bgContext = ctx.copyForBackground();
            return MiddlewareResponse.withBackgroundContinuation(
              response: http.StreamedResponse(
                Stream.value(utf8.encode('ok')),
                200,
              ),
              backgroundContext: bgContext,
            );
          },
        );

        // The background continuation should be preserved
        expect(response.hasBackgroundContinuation, isTrue);
        expect(response.backgroundContext, isNotNull);
      },
    );
  });

  group('InlineMiddleware', () {
    test('onRequest mutates the request', () async {
      String? capturedHeader;

      final mockClient = MockClient((request) async {
        capturedHeader = request.headers['x-custom'];
        return http.Response('ok', 200);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [
          InlineMiddleware.onRequest((request) {
            request.headers['x-custom'] = 'value';
          }),
        ],
      );

      await client.get(Uri.parse('https://example.com'));

      expect(capturedHeader, equals('value'));

      client.close();
    });

    test('onResponse observes the response without consuming it', () async {
      int? observedStatus;

      final mockClient = MockClient((request) async {
        return http.Response('body', 201);
      });

      final client = MiddlewareClient(
        inner: mockClient,
        middlewares: [
          InlineMiddleware.onResponse((response, context) {
            observedStatus = response.statusCode;
          }),
        ],
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(observedStatus, equals(201));
      expect(response.body, equals('body'));

      client.close();
    });

    test('full handler can short-circuit', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async {
          fail('Network should not be reached');
        }),
        middlewares: [
          InlineMiddleware((context, next) async {
            return MiddlewareResponse.immediate(
              http.StreamedResponse(Stream.value(utf8.encode('stub')), 200),
            );
          }),
        ],
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.body, equals('stub'));

      client.close();
    });
  });

  group('HeadersMiddleware', () {
    test('adds missing headers', () async {
      Map<String, String>? captured;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          captured = request.headers;
          return http.Response('ok', 200);
        }),
        middlewares: [
          HeadersMiddleware({'x-app': 'test', 'accept': 'application/json'}),
        ],
      );

      await client.get(Uri.parse('https://example.com'));

      expect(captured!['x-app'], equals('test'));
      expect(captured!['accept'], equals('application/json'));

      client.close();
    });

    test('does not override request headers by default', () async {
      Map<String, String>? captured;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          captured = request.headers;
          return http.Response('ok', 200);
        }),
        middlewares: [
          HeadersMiddleware({'x-app': 'default'}),
        ],
      );

      await client.get(
        Uri.parse('https://example.com'),
        headers: {'x-app': 'explicit'},
      );

      expect(captured!['x-app'], equals('explicit'));

      client.close();
    });

    test('overrides request headers when overrideExisting is true', () async {
      Map<String, String>? captured;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          captured = request.headers;
          return http.Response('ok', 200);
        }),
        middlewares: [
          HeadersMiddleware({'x-app': 'forced'}, overrideExisting: true),
        ],
      );

      await client.get(
        Uri.parse('https://example.com'),
        headers: {'x-app': 'explicit'},
      );

      expect(captured!['x-app'], equals('forced'));

      client.close();
    });

    test('builder supplies headers asynchronously', () async {
      Map<String, String>? captured;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          captured = request.headers;
          return http.Response('ok', 200);
        }),
        middlewares: [
          HeadersMiddleware.builder((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return {'authorization': 'Bearer fresh-token'};
          }),
        ],
      );

      await client.get(Uri.parse('https://example.com'));

      expect(captured!['authorization'], equals('Bearer fresh-token'));

      client.close();
    });
  });

  group('RetryMiddleware', () {
    test('retries retriable responses until success', () async {
      var calls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          calls++;
          if (calls < 3) {
            return http.Response('unavailable', 503);
          }
          return http.Response('ok', 200);
        }),
        middlewares: [RetryMiddleware(delay: (_) => Duration.zero)],
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(200));
      expect(calls, equals(3));

      client.close();
    });

    test('returns last response after maxRetries', () async {
      var calls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          calls++;
          return http.Response('unavailable', 503);
        }),
        middlewares: [
          RetryMiddleware(maxRetries: 2, delay: (_) => Duration.zero),
        ],
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(503));
      expect(calls, equals(3));

      client.close();
    });

    test('retries thrown ClientException', () async {
      var calls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          calls++;
          if (calls == 1) {
            throw http.ClientException('connection reset');
          }
          return http.Response('ok', 200);
        }),
        middlewares: [RetryMiddleware(delay: (_) => Duration.zero)],
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(200));
      expect(calls, equals(2));

      client.close();
    });

    test('rethrows after maxRetries', () async {
      var calls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          calls++;
          throw http.ClientException('connection reset');
        }),
        middlewares: [
          RetryMiddleware(maxRetries: 1, delay: (_) => Duration.zero),
        ],
      );

      await expectLater(
        client.get(Uri.parse('https://example.com')),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, equals(2));

      client.close();
    });

    test('does not retry POST by default', () async {
      var calls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          calls++;
          return http.Response('unavailable', 503);
        }),
        middlewares: [RetryMiddleware(delay: (_) => Duration.zero)],
      );

      final response = await client.post(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(503));
      expect(calls, equals(1));

      client.close();
    });

    test('does not retry responses with background continuation', () async {
      var nextCalls = 0;
      final retry = RetryMiddleware(delay: (_) => Duration.zero);
      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com')),
      );

      final result = await retry.process(context, (ctx) async {
        nextCalls++;
        return MiddlewareResponse.withBackgroundContinuation(
          response: http.StreamedResponse(Stream.value([]), 503),
          backgroundContext: ctx.copyForBackground(),
        );
      });

      expect(nextCalls, equals(1));
      expect(result.hasBackgroundContinuation, isTrue);
    });
  });

  group('TimeoutMiddleware', () {
    test('throws TimeoutException when the request is too slow', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('ok', 200);
        }),
        middlewares: [const TimeoutMiddleware(Duration(milliseconds: 20))],
      );

      await expectLater(
        client.get(Uri.parse('https://example.com')),
        throwsA(isA<TimeoutException>()),
      );

      client.close();
    });

    test('passes fast requests through', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async => http.Response('ok', 200)),
        middlewares: [const TimeoutMiddleware(Duration(seconds: 5))],
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(200));

      client.close();
    });

    test('uses backgroundTimeout for background requests', () async {
      const middleware = TimeoutMiddleware(
        Duration(milliseconds: 10),
        backgroundTimeout: Duration(seconds: 5),
      );

      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com')),
      );
      context.markAsBackground();

      final result = await middleware.process(context, (ctx) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value([]), 200),
        );
      });

      expect(result.response.statusCode, equals(200));
    });
  });

  group('MiddlewareClient.watch', () {
    test('emits one event on cache miss', () async {
      final cache = InMemorySwrCache();

      final client = MiddlewareClient(
        inner: MockClient((request) async => http.Response('fresh', 200)),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final events = await client
          .watchGet(Uri.parse('https://example.com/data'))
          .toList();

      expect(events, hasLength(1));
      expect(events.single.response.body, equals('fresh'));
      expect(events.single.source, equals(WatchSource.network));
      expect(events.single.isFromCache, isFalse);
      expect(events.single.isRevalidating, isFalse);
      expect(cache.length, equals(1));

      client.close();
    });

    test('emits cached then fresh on cache hit', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('response $networkCalls', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');

      // Populate the cache
      await client.get(uri);

      final events = await client.watchGet(uri).toList();

      expect(events, hasLength(2));
      expect(events[0].response.body, equals('response 1'));
      expect(events[0].source, equals(WatchSource.cacheRevalidating));
      expect(events[0].isFromCache, isTrue);
      expect(events[0].isRevalidating, isTrue);
      expect(events[1].response.body, equals('response 2'));
      expect(events[1].source, equals(WatchSource.network));
      expect(events[1].isFromCache, isFalse);
      expect(events[1].isRevalidating, isFalse);

      // The fresh response also updated the cache
      final cached = await cache.get('GET:$uri');
      expect(cached!.bodyString, equals('response 2'));

      client.close();
    });

    test('emits one event without cache middleware', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async => http.Response('plain', 200)),
        middlewares: [],
      );

      final events = await client
          .watchGet(Uri.parse('https://example.com'))
          .toList();

      expect(events, hasLength(1));
      expect(events.single.response.body, equals('plain'));
      expect(events.single.isFromCache, isFalse);
      expect(events.single.isRevalidating, isFalse);

      client.close();
    });

    test('emits cached event then error when revalidation fails', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;
      MiddlewareContext? errorContext;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          if (networkCalls > 1) {
            throw http.ClientException('server down');
          }
          return http.Response('stale', 200);
        }),
        middlewares: [
          _BackgroundErrorCaptureMiddleware((ctx) => errorContext = ctx),
          SwrMiddleware(cache: cache),
        ],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      final events = <WatchEvent>[];
      Object? streamError;
      await client
          .watchGet(uri)
          .handleError((Object e) => streamError = e)
          .forEach(events.add);

      expect(events, hasLength(1));
      expect(events.single.response.body, equals('stale'));
      expect(events.single.isFromCache, isTrue);
      expect(events.single.isRevalidating, isTrue);
      expect(streamError, isA<http.ClientException>());
      // Middlewares were notified so cache state was cleaned up
      expect(errorContext, isNotNull);
      expect(errorContext!.isBackground, isTrue);

      client.close();
    });

    test('skipUnchanged suppresses identical fresh response', () async {
      final cache = InMemorySwrCache();

      final client = MiddlewareClient(
        inner: MockClient((request) async => http.Response('same', 200)),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      final events = await client.watchGet(uri, skipUnchanged: true).toList();

      expect(events, hasLength(1));
      expect(events.single.response.body, equals('same'));
      expect(events.single.isFromCache, isTrue);
      expect(events.single.isRevalidating, isTrue);

      client.close();
    });

    test('skipUnchanged still emits a changed fresh response', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('response $networkCalls', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      final events = await client.watchGet(uri, skipUnchanged: true).toList();

      expect(events, hasLength(2));

      client.close();
    });

    test(
      'cache hit during another revalidation is not marked revalidating',
      () async {
        final cache = InMemorySwrCache();
        var networkCalls = 0;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            networkCalls++;
            if (networkCalls > 1) {
              // Slow revalidation holds the SWR lock
              await Future.delayed(const Duration(milliseconds: 100));
            }
            return http.Response('response $networkCalls', 200);
          }),
          middlewares: [SwrMiddleware(cache: cache)],
        );

        final uri = Uri.parse('https://example.com/data');
        await client.get(uri);

        // Starts a slow revalidation
        final firstWatch = client.watchGet(uri).toList();

        // While it's in flight, another watch hits the cache: it must not
        // claim to be revalidating - no second event will follow
        final second = await client.watchGet(uri).toList();
        expect(second, hasLength(1));
        expect(second.single.source, equals(WatchSource.cacheOnly));
        expect(second.single.isFromCache, isTrue);
        expect(second.single.isRevalidating, isFalse);

        final first = await firstWatch;
        expect(first, hasLength(2));
        expect(first[0].isRevalidating, isTrue);

        client.close();
      },
    );

    test('early cancellation still refreshes the cache', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('response $networkCalls', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      // Take only the first (cached) event and cancel
      final first = await client.watchGet(uri).first;
      expect(first.response.body, equals('response 1'));
      expect(first.isFromCache, isTrue);

      // The revalidation still runs to completion
      await Future.delayed(const Duration(milliseconds: 100));
      expect(networkCalls, equals(2));

      final cached = await cache.get('GET:$uri');
      expect(cached!.bodyString, equals('response 2'));

      // And the revalidation lock was released: a new watch revalidates
      final events = await client.watchGet(uri).toList();
      expect(events, hasLength(2));
      expect(networkCalls, equals(3));

      client.close();
    });

    test('early cancellation with failing revalidation stays silent', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          if (networkCalls > 1) {
            throw http.ClientException('server down');
          }
          return http.Response('stale', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      // Cancel after the first event; the failing revalidation must not
      // produce an unhandled async error
      final first = await client.watchGet(uri).first;
      expect(first.response.body, equals('stale'));

      await Future.delayed(const Duration(milliseconds: 100));
      expect(networkCalls, equals(2));

      client.close();
    });
  });

  group('MiddlewareClient.standard', () {
    test('provides SWR caching out of the box', () async {
      var networkCalls = 0;

      final client = MiddlewareClient.standard(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('response $networkCalls', 200);
        }),
      );

      final uri = Uri.parse('https://example.com/data');

      final response1 = await client.get(uri);
      expect(response1.body, equals('response 1'));

      // Cache hit: served from cache, background revalidation follows
      final response2 = await client.get(uri);
      expect(response2.body, equals('response 1'));

      client.close();
    });

    test('applies default headers and logging when provided', () async {
      final logs = <String>[];
      Map<String, String>? captured;

      final client = MiddlewareClient.standard(
        inner: MockClient((request) async {
          captured = request.headers;
          return http.Response('ok', 200);
        }),
        defaultHeaders: {'x-app': 'test'},
        onLog: logs.add,
      );

      await client.get(Uri.parse('https://example.com'));

      expect(captured!['x-app'], equals('test'));
      expect(logs, isNotEmpty);

      client.close();
    });

    test('retries transient failures by default', () async {
      var networkCalls = 0;

      final client = MiddlewareClient.standard(
        inner: MockClient((request) async {
          networkCalls++;
          if (networkCalls < 2) {
            return http.Response('unavailable', 503);
          }
          return http.Response('ok', 200);
        }),
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(200));
      expect(networkCalls, equals(2));

      client.close();
    });

    test('includes custom extra middlewares', () async {
      final seen = <String>[];

      final client = MiddlewareClient.standard(
        inner: MockClient((request) async => http.Response('ok', 200)),
        extra: [
          InlineMiddleware.onRequest((request) {
            seen.add(request.url.path);
          }),
        ],
      );

      await client.get(Uri.parse('https://example.com/hello'));

      expect(seen, equals(['/hello']));

      client.close();
    });
  });

  group('CircuitBreakerMiddleware', () {
    MiddlewareContext contextFor(String url) {
      return MiddlewareContext(request: http.Request('GET', Uri.parse(url)));
    }

    Future<MiddlewareResponse> respond(int status) async {
      return MiddlewareResponse.immediate(
        http.StreamedResponse(Stream.value(<int>[]), status),
      );
    }

    test('opens after failureThreshold consecutive failures', () async {
      var networkCalls = 0;
      final breaker = CircuitBreakerMiddleware(failureThreshold: 2);

      Future<MiddlewareResponse> next(MiddlewareContext ctx) {
        networkCalls++;
        return respond(500);
      }

      await breaker.process(contextFor('https://example.com/a'), next);
      await breaker.process(contextFor('https://example.com/b'), next);

      expect(
        breaker.stateFor(http.Request('GET', Uri.parse('https://example.com'))),
        equals(CircuitState.open),
      );

      await expectLater(
        breaker.process(contextFor('https://example.com/c'), next),
        throwsA(isA<CircuitOpenException>()),
      );
      expect(networkCalls, equals(2));
    });

    test('thrown ClientException counts as failure', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      await expectLater(
        breaker.process(
          contextFor('https://example.com'),
          (ctx) => throw http.ClientException('connection refused'),
        ),
        throwsA(isA<http.ClientException>()),
      );

      await expectLater(
        breaker.process(
          contextFor('https://example.com'),
          (ctx) => respond(200),
        ),
        throwsA(isA<CircuitOpenException>()),
      );
    });

    test('success resets the consecutive failure counter', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 2);

      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );
      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(200),
      );
      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.closed),
      );
    });

    test(
      'transitions to halfOpen after openDuration and closes on success',
      () async {
        var current = DateTime(2026, 1, 1);
        final transitions = <String>[];

        final breaker = CircuitBreakerMiddleware(
          failureThreshold: 1,
          openDuration: const Duration(seconds: 30),
          now: () => current,
          onStateChange: (key, from, to) => transitions.add('$from->$to'),
        );

        await breaker.process(
          contextFor('https://example.com'),
          (ctx) => respond(500),
        );

        // Still open: cooldown not elapsed
        await expectLater(
          breaker.process(
            contextFor('https://example.com'),
            (ctx) => respond(200),
          ),
          throwsA(isA<CircuitOpenException>()),
        );

        // Cooldown elapsed: probe goes through and closes the circuit
        current = current.add(const Duration(seconds: 31));
        final result = await breaker.process(
          contextFor('https://example.com'),
          (ctx) => respond(200),
        );

        expect(result.response.statusCode, equals(200));
        expect(
          breaker.stateForKey('https://example.com:443'),
          equals(CircuitState.closed),
        );
        expect(
          transitions,
          equals([
            'CircuitState.closed->CircuitState.open',
            'CircuitState.open->CircuitState.halfOpen',
            'CircuitState.halfOpen->CircuitState.closed',
          ]),
        );
      },
    );

    test('failed probe reopens the circuit', () async {
      var current = DateTime(2026, 1, 1);

      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        openDuration: const Duration(seconds: 30),
        now: () => current,
      );

      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );

      current = current.add(const Duration(seconds: 31));
      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(503),
      );

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.open),
      );

      // And the cooldown restarted
      await expectLater(
        breaker.process(
          contextFor('https://example.com'),
          (ctx) => respond(200),
        ),
        throwsA(isA<CircuitOpenException>()),
      );
    });

    test('halfOpen limits concurrent probes', () async {
      var current = DateTime(2026, 1, 1);

      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        openDuration: const Duration(seconds: 30),
        now: () => current,
      );

      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );
      current = current.add(const Duration(seconds: 31));

      final probeGate = Completer<MiddlewareResponse>();
      final probe = breaker.process(
        contextFor('https://example.com'),
        (ctx) => probeGate.future,
      );

      // Second request while the probe is in flight is rejected
      await expectLater(
        breaker.process(
          contextFor('https://example.com'),
          (ctx) => respond(200),
        ),
        throwsA(isA<CircuitOpenException>()),
      );

      probeGate.complete(await respond(200));
      await probe;

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.closed),
      );
    });

    test('circuits are isolated per host by default', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      await breaker.process(
        contextFor('https://down.example.com'),
        (ctx) => respond(500),
      );

      // Other host is unaffected
      final result = await breaker.process(
        contextFor('https://up.example.com'),
        (ctx) => respond(200),
      );

      expect(result.response.statusCode, equals(200));
      expect(
        breaker.stateForKey('https://down.example.com:443'),
        equals(CircuitState.open),
      );
      expect(
        breaker.stateForKey('https://up.example.com:443'),
        equals(CircuitState.closed),
      );
    });

    test('shouldBreak exempts requests from circuit breaking', () async {
      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        shouldBreak: (request) => !request.url.path.startsWith('/health'),
      );

      await breaker.process(
        contextFor('https://example.com/api'),
        (ctx) => respond(500),
      );

      // Circuit is open, but health checks bypass it
      final result = await breaker.process(
        contextFor('https://example.com/health'),
        (ctx) => respond(200),
      );

      expect(result.response.statusCode, equals(200));
    });

    test('cached responses do not affect the circuit', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      await breaker.process(contextFor('https://example.com'), (ctx) async {
        ctx.markAsFromCache();
        return respond(500);
      });

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.closed),
      );
    });

    test('custom isFailureResponse treats 429 as failure', () async {
      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        isFailureResponse: (response) =>
            response.statusCode >= 500 || response.statusCode == 429,
      );

      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(429),
      );

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.open),
      );
    });

    test('reset manually closes circuits', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );
      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.open),
      );

      breaker.reset();

      final result = await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(200),
      );
      expect(result.response.statusCode, equals(200));
    });

    test('RetryMiddleware does not retry CircuitOpenException', () async {
      var calls = 0;
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          calls++;
          return http.Response('down', 503);
        }),
        middlewares: [
          RetryMiddleware(maxRetries: 5, delay: (_) => Duration.zero),
          breaker,
        ],
      );

      await expectLater(
        client.get(Uri.parse('https://example.com')),
        throwsA(isA<CircuitOpenException>()),
      );

      // First attempt opened the circuit; retries stopped immediately
      expect(calls, equals(1));

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
      expect(cache.sizeInBytes, equals(0));
    });

    CachedResponse ofSize(int bytes) {
      return CachedResponse(
        statusCode: 200,
        body: Uint8List(bytes),
        headers: {},
      );
    }

    test('tracks total size in bytes', () async {
      final cache = InMemorySwrCache();

      await cache.set('a', ofSize(100));
      await cache.set('b', ofSize(50));
      expect(cache.sizeInBytes, equals(150));

      // Replacing an entry updates accounting
      await cache.set('a', ofSize(30));
      expect(cache.sizeInBytes, equals(80));

      await cache.remove('b');
      expect(cache.sizeInBytes, equals(30));
    });

    test('evicts least recently used entries over maxSizeBytes', () async {
      final cache = InMemorySwrCache(maxSizeBytes: 250);

      await cache.set('a', ofSize(100));
      await cache.set('b', ofSize(100));
      await cache.set('c', ofSize(100)); // 300 > 250: 'a' evicted

      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), isNotNull);
      expect(await cache.get('c'), isNotNull);
      expect(cache.sizeInBytes, equals(200));
    });

    test('get marks an entry as recently used', () async {
      final cache = InMemorySwrCache(maxSizeBytes: 250);

      await cache.set('a', ofSize(100));
      await cache.set('b', ofSize(100));

      // Touch 'a' so 'b' becomes the LRU entry
      await cache.get('a');

      await cache.set('c', ofSize(100)); // evicts 'b', not 'a'

      expect(await cache.get('a'), isNotNull);
      expect(await cache.get('b'), isNull);
      expect(await cache.get('c'), isNotNull);
    });

    test('does not store a response larger than maxSizeBytes', () async {
      final cache = InMemorySwrCache(maxSizeBytes: 100);

      await cache.set('a', ofSize(50));
      await cache.set('big', ofSize(200));

      expect(await cache.get('big'), isNull);
      // Other entries survive
      expect(await cache.get('a'), isNotNull);
      expect(cache.sizeInBytes, equals(50));
    });

    test('oversized response removes the stale entry under its key', () async {
      final cache = InMemorySwrCache(maxSizeBytes: 100);

      await cache.set('a', ofSize(50));
      // The refreshed response no longer fits: the stale one must not
      // be served forever
      await cache.set('a', ofSize(200));

      expect(await cache.get('a'), isNull);
      expect(cache.sizeInBytes, equals(0));
    });

    test('evicts entries over maxEntries', () async {
      final cache = InMemorySwrCache(maxEntries: 2);

      await cache.set('a', ofSize(1));
      await cache.set('b', ofSize(1));
      await cache.set('c', ofSize(1));

      expect(cache.length, equals(2));
      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), isNotNull);
      expect(await cache.get('c'), isNotNull);
    });
  });

  group('MiddlewareContext.cloneRequest', () {
    test('clones Request with all fields', () {
      final original = http.Request('POST', Uri.parse('https://example.com'))
        ..headers['x-custom'] = 'value'
        ..bodyBytes = utf8.encode('payload')
        ..followRedirects = false
        ..maxRedirects = 3
        ..persistentConnection = false;

      final clone = MiddlewareContext.cloneRequest(original) as http.Request;

      expect(clone, isNot(same(original)));
      expect(clone.method, equals('POST'));
      expect(clone.url, equals(original.url));
      expect(clone.headers['x-custom'], equals('value'));
      expect(clone.bodyBytes, equals(original.bodyBytes));
      expect(clone.followRedirects, isFalse);
      expect(clone.maxRedirects, equals(3));
      expect(clone.persistentConnection, isFalse);
    });

    test('clones a finalized Request', () {
      final original = http.Request('GET', Uri.parse('https://example.com'));
      original.finalize();

      final clone = MiddlewareContext.cloneRequest(original);

      // The clone must be sendable: finalize() works exactly once
      expect(clone.finalize, returnsNormally);
    });

    test('clones MultipartRequest with fields and files', () {
      final original =
          http.MultipartRequest('POST', Uri.parse('https://example.com'))
            ..headers['x-custom'] = 'value'
            ..fields['name'] = 'test'
            ..files.add(http.MultipartFile.fromBytes('file', [1, 2, 3]));

      final clone =
          MiddlewareContext.cloneRequest(original) as http.MultipartRequest;

      expect(clone, isNot(same(original)));
      expect(clone.headers['x-custom'], equals('value'));
      expect(clone.fields['name'], equals('test'));
      expect(clone.files, hasLength(1));
    });

    test('throws UnsupportedError for StreamedRequest', () {
      final original = http.StreamedRequest(
        'POST',
        Uri.parse('https://example.com'),
      );

      expect(
        () => MiddlewareContext.cloneRequest(original),
        throwsUnsupportedError,
      );
    });

    test('throws UnsupportedError for unknown request types', () {
      final original = _CustomRequest('GET', Uri.parse('https://example.com'));

      expect(
        () => MiddlewareContext.cloneRequest(original),
        throwsUnsupportedError,
      );
    });

    test('copyForBackground strips _isFromCache but keeps other metadata', () {
      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com')),
      );
      context.markAsFromCache();
      context.metadata['custom'] = 'kept';

      final copy = context.copyForBackground();

      expect(copy.isFromCache, isFalse);
      expect(copy.metadata['custom'], equals('kept'));
      expect(copy.request, isNot(same(context.request)));
    });

    test('toString includes method, url and metadata', () {
      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com/x')),
      );
      context.metadata['k'] = 'v';

      expect(context.toString(), contains('GET'));
      expect(context.toString(), contains('https://example.com/x'));
      expect(context.toString(), contains('k'));
    });
  });

  group('edge cases: value types', () {
    test(
      'CachedResponse round-trips isRedirect and persistentConnection',
      () async {
        final source = http.StreamedResponse(
          Stream.value(<int>[]),
          302,
          isRedirect: true,
          persistentConnection: false,
          reasonPhrase: 'Found',
        );

        final cached = await CachedResponse.fromStreamedResponse(source);
        final restored = cached.toStreamedResponse();

        expect(restored.isRedirect, isTrue);
        expect(restored.persistentConnection, isFalse);
        expect(restored.reasonPhrase, equals('Found'));
      },
    );

    test('bodyString tolerates malformed UTF-8', () {
      final cached = CachedResponse(
        statusCode: 200,
        body: Uint8List.fromList([0xFF, 0xFE, 0x41]),
        headers: {},
      );

      expect(() => cached.bodyString, returnsNormally);
      expect(cached.bodyString, contains('A'));
    });

    test('CachedResponse.toString reports status and size', () {
      final cached = CachedResponse(
        statusCode: 404,
        body: Uint8List(7),
        headers: {'a': '1'},
      );

      expect(cached.toString(), contains('404'));
      expect(cached.toString(), contains('7'));
    });

    test('MiddlewareResponse default constructor carries continuation', () {
      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com')),
      );
      final response = MiddlewareResponse(
        response: http.StreamedResponse(Stream.value(<int>[]), 200),
        backgroundContext: context,
      );

      expect(response.hasBackgroundContinuation, isTrue);
      expect(response.toString(), contains('hasBackgroundContinuation: true'));
    });

    test('WatchEvent.toString reports status and source', () {
      final event = WatchEvent(
        response: http.Response('x', 200),
        source: WatchSource.cacheRevalidating,
      );

      expect(event.toString(), contains('200'));
      expect(event.toString(), contains('cacheRevalidating'));
    });

    test('CircuitOpenException.toString reports key and retryAfter', () {
      final exception = CircuitOpenException(
        key: 'https://example.com:443',
        retryAfter: const Duration(seconds: 7),
      );

      expect(exception.toString(), contains('https://example.com:443'));
      expect(exception.toString(), contains('0:00:07'));
    });
  });

  group('edge cases: MiddlewareClient', () {
    test('default constructor creates and closes an own inner client', () {
      final client = MiddlewareClient();
      expect(client.close, returnsNormally);
    });

    test('close closes inner and backgroundInner', () {
      final inner = _TrackingClient();
      final background = _TrackingClient();

      MiddlewareClient(inner: inner, backgroundInner: background).close();

      expect(inner.closed, isTrue);
      expect(background.closed, isTrue);
    });

    test('background revalidation uses backgroundInner', () async {
      var foregroundCalls = 0;
      var backgroundCalls = 0;
      final cache = InMemorySwrCache();

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          foregroundCalls++;
          return http.Response('foreground', 200);
        }),
        backgroundInner: MockClient((request) async {
          backgroundCalls++;
          return http.Response('background', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);
      expect(foregroundCalls, equals(1));
      expect(backgroundCalls, equals(0));

      // Cache hit: revalidation must go to the background client
      await client.get(uri);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(foregroundCalls, equals(1));
      expect(backgroundCalls, equals(1));

      final cached = await cache.get('GET:$uri');
      expect(cached!.bodyString, equals('background'));

      client.close();
    });

    test(
      'throwing onBackgroundError handler does not silence others',
      () async {
        var secondHandlerCalled = false;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            if (request.headers['x-background'] == 'true') {
              throw http.ClientException('boom');
            }
            return http.Response('ok', 200);
          }),
          middlewares: [
            _BackgroundErrorCaptureMiddleware((_) => throw StateError('bad')),
            _BackgroundErrorCaptureMiddleware(
              (_) => secondHandlerCalled = true,
            ),
            _BackgroundTriggerMiddleware(),
          ],
        );

        await client.get(Uri.parse('https://example.com'));
        await Future.delayed(const Duration(milliseconds: 100));

        expect(secondHandlerCalled, isTrue);

        client.close();
      },
    );

    test('watchGet applies headers', () async {
      String? captured;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          captured = request.headers['x-token'];
          return http.Response('ok', 200);
        }),
      );

      await client
          .watchGet(
            Uri.parse('https://example.com'),
            headers: {'x-token': 'abc'},
          )
          .drain<void>();

      expect(captured, equals('abc'));

      client.close();
    });

    test('watch emits failed revalidation response as network event', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          if (networkCalls > 1) {
            return http.Response('server error', 500);
          }
          return http.Response('good', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      final events = await client.watchGet(uri).toList();

      expect(events, hasLength(2));
      expect(events[1].source, equals(WatchSource.network));
      expect(events[1].response.statusCode, equals(500));

      // The 500 must not overwrite the cached 200
      final cached = await cache.get('GET:$uri');
      expect(cached!.statusCode, equals(200));
      expect(cached.bodyString, equals('good'));

      client.close();
    });

    test(
      'skipUnchanged emits when status differs but body is identical',
      () async {
        final cache = InMemorySwrCache();
        var networkCalls = 0;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            networkCalls++;
            return http.Response('same', networkCalls == 1 ? 200 : 404);
          }),
          middlewares: [SwrMiddleware(cache: cache)],
        );

        final uri = Uri.parse('https://example.com/data');
        await client.get(uri);

        final events = await client.watchGet(uri, skipUnchanged: true).toList();

        expect(events, hasLength(2));
        expect(events[1].response.statusCode, equals(404));

        client.close();
      },
    );
  });

  group('edge cases: SwrMiddleware', () {
    test(
      'serves cache hit for unclonable request without revalidation',
      () async {
        final cache = InMemorySwrCache();
        var networkCalls = 0;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            networkCalls++;
            return http.Response('cached data', 200);
          }),
          middlewares: [SwrMiddleware(cache: cache)],
        );

        final uri = Uri.parse('https://example.com/data');
        await client.get(uri);
        expect(networkCalls, equals(1));

        // StreamedRequest cannot be cloned for revalidation: the cached
        // response must still be served instead of throwing
        final streamedRequest = http.StreamedRequest('GET', uri);
        unawaited(streamedRequest.sink.close());
        final response = await client.send(streamedRequest);
        final body = await response.stream.bytesToString();

        expect(body, equals('cached data'));

        await Future.delayed(const Duration(milliseconds: 100));
        // No revalidation happened
        expect(networkCalls, equals(1));

        client.close();
      },
    );

    test('failed revalidation keeps the stale cache entry', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          if (networkCalls > 1) {
            return http.Response('oops', 503);
          }
          return http.Response('good', 200);
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      // Cache hit triggers a revalidation that returns 503
      final response = await client.get(uri);
      expect(response.body, equals('good'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(networkCalls, equals(2));
      final cached = await cache.get('GET:$uri');
      expect(cached!.bodyString, equals('good'));

      client.close();
    });

    test('custom shouldCacheRequest enables caching POST', () async {
      final cache = InMemorySwrCache();

      final client = MiddlewareClient(
        inner: MockClient((request) async => http.Response('ok', 200)),
        middlewares: [
          SwrMiddleware(cache: cache, shouldCacheRequest: (request) => true),
        ],
      );

      await client.post(Uri.parse('https://example.com/data'));

      expect(cache.length, equals(1));
      expect(cache.keys.first, startsWith('POST:'));

      client.close();
    });

    test('exposes cache key in context metadata', () async {
      final middleware = SwrMiddleware(cache: InMemorySwrCache());
      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com/data')),
      );

      await middleware.process(
        context,
        (ctx) async => MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(<int>[]), 200),
        ),
      );

      expect(
        context.metadata['swr:cacheKey'],
        equals('GET:https://example.com/data'),
      );
    });
  });

  group('edge cases: DedupMiddleware', () {
    test('leader with waiters keeps its background continuation', () async {
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');
      final gate = Completer<MiddlewareResponse>();

      final leader = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        (ctx) => gate.future,
      );
      final waiter = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        (ctx) async => fail('waiter must not reach next'),
      );

      expect(dedup.inFlightKeys, contains('GET:$uri'));

      final backgroundContext = MiddlewareContext(
        request: http.Request('GET', uri),
      );
      gate.complete(
        MiddlewareResponse.withBackgroundContinuation(
          response: http.StreamedResponse(Stream.value(utf8.encode('x')), 200),
          backgroundContext: backgroundContext,
        ),
      );

      final leaderResult = await leader;
      final waiterResult = await waiter;

      expect(leaderResult.hasBackgroundContinuation, isTrue);
      expect(leaderResult.backgroundContext, same(backgroundContext));
      // The waiter gets a plain shared response
      expect(waiterResult.hasBackgroundContinuation, isFalse);
    });

    test('body stream error during buffering propagates to waiters', () async {
      final dedup = DedupMiddleware();
      final uri = Uri.parse('https://example.com/data');
      final gate = Completer<MiddlewareResponse>();

      final leader = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        (ctx) => gate.future,
      );
      final waiter = dedup.process(
        MiddlewareContext(request: http.Request('GET', uri)),
        (ctx) async => fail('waiter must not reach next'),
      );

      gate.complete(
        MiddlewareResponse.immediate(
          http.StreamedResponse(
            Stream.error(Exception('connection reset mid-body')),
            200,
          ),
        ),
      );

      await expectLater(leader, throwsException);
      await expectLater(waiter, throwsException);
      expect(dedup.inFlightCount, equals(0));
    });
  });

  group('edge cases: RetryMiddleware', () {
    MiddlewareContext streamedContext() {
      final request = http.StreamedRequest(
        'GET',
        Uri.parse('https://example.com'),
      );
      unawaited(request.sink.close());
      return MiddlewareContext(request: request);
    }

    test('unclonable request is not retried on retriable response', () async {
      var nextCalls = 0;
      final retry = RetryMiddleware(delay: (_) => Duration.zero);

      final result = await retry.process(streamedContext(), (ctx) async {
        nextCalls++;
        return MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(<int>[]), 503),
        );
      });

      expect(nextCalls, equals(1));
      expect(result.response.statusCode, equals(503));
    });

    test('unclonable request rethrows the original error', () async {
      var nextCalls = 0;
      final retry = RetryMiddleware(delay: (_) => Duration.zero);

      await expectLater(
        retry.process(streamedContext(), (ctx) async {
          nextCalls++;
          throw http.ClientException('network down');
        }),
        throwsA(isA<http.ClientException>()),
      );
      expect(nextCalls, equals(1));
    });

    test('delay receives 1-based attempt numbers', () async {
      final attempts = <int>[];

      final client = MiddlewareClient(
        inner: MockClient((request) async => http.Response('unavailable', 503)),
        middlewares: [
          RetryMiddleware(
            maxRetries: 2,
            delay: (attempt) {
              attempts.add(attempt);
              return Duration.zero;
            },
          ),
        ],
      );

      await client.get(Uri.parse('https://example.com'));

      expect(attempts, equals([1, 2]));

      client.close();
    });

    test('retries 408 and 429 by default', () async {
      for (final status in [408, 429]) {
        var calls = 0;
        final client = MiddlewareClient(
          inner: MockClient((request) async {
            calls++;
            return calls == 1
                ? http.Response('retry me', status)
                : http.Response('ok', 200);
          }),
          middlewares: [RetryMiddleware(delay: (_) => Duration.zero)],
        );

        final response = await client.get(Uri.parse('https://example.com'));

        expect(response.statusCode, equals(200), reason: 'status $status');
        expect(calls, equals(2), reason: 'status $status');

        client.close();
      }
    });

    test('does not retry responses served from cache', () async {
      var nextCalls = 0;
      final retry = RetryMiddleware(delay: (_) => Duration.zero);
      final context = MiddlewareContext(
        request: http.Request('GET', Uri.parse('https://example.com')),
      );

      final result = await retry.process(context, (ctx) async {
        nextCalls++;
        ctx.markAsFromCache();
        return MiddlewareResponse.immediate(
          http.StreamedResponse(Stream.value(<int>[]), 503),
        );
      });

      expect(nextCalls, equals(1));
      expect(result.response.statusCode, equals(503));
    });
  });

  group('edge cases: CircuitBreakerMiddleware', () {
    MiddlewareContext contextFor(String url) {
      return MiddlewareContext(request: http.Request('GET', Uri.parse(url)));
    }

    Future<MiddlewareResponse> respond(int status) async {
      return MiddlewareResponse.immediate(
        http.StreamedResponse(Stream.value(<int>[]), status),
      );
    }

    test('late failure after the circuit opened is ignored', () async {
      final transitions = <String>[];
      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        onStateChange: (key, from, to) => transitions.add('$from->$to'),
      );
      final gate = Completer<MiddlewareResponse>();

      // Slow request enters while the circuit is still closed
      final slow = breaker.process(
        contextFor('https://example.com/slow'),
        (ctx) => gate.future,
      );

      // Another request opens the circuit
      await breaker.process(
        contextFor('https://example.com/fast'),
        (ctx) => respond(500),
      );
      expect(transitions, hasLength(1));

      // The slow request completes with a failure - no double transition
      gate.complete(await respond(500));
      await slow;

      expect(transitions, hasLength(1));
      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.open),
      );
    });

    test('late success after the circuit opened does not close it', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);
      final gate = Completer<MiddlewareResponse>();

      final slow = breaker.process(
        contextFor('https://example.com/slow'),
        (ctx) => gate.future,
      );

      await breaker.process(
        contextFor('https://example.com/fast'),
        (ctx) => respond(500),
      );

      gate.complete(await respond(200));
      await slow;

      // Only a successful probe may close the circuit
      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.open),
      );
    });

    test('reset(key) closes only that circuit', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      await breaker.process(
        contextFor('https://a.example.com'),
        (ctx) => respond(500),
      );
      await breaker.process(
        contextFor('https://b.example.com'),
        (ctx) => respond(500),
      );

      breaker.reset('https://a.example.com:443');

      expect(
        breaker.stateForKey('https://a.example.com:443'),
        equals(CircuitState.closed),
      );
      expect(
        breaker.stateForKey('https://b.example.com:443'),
        equals(CircuitState.open),
      );
    });

    test('throwing onStateChange listener does not break processing', () async {
      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        onStateChange: (key, from, to) => throw StateError('listener bug'),
      );

      // Transition happens inside process - must not throw
      final result = await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );

      expect(result.response.statusCode, equals(500));
      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.open),
      );
    });

    test('non-failure errors do not trip the circuit', () async {
      final breaker = CircuitBreakerMiddleware(failureThreshold: 1);

      await expectLater(
        breaker.process(
          contextFor('https://example.com'),
          (ctx) => throw ArgumentError('programming bug, not backend'),
        ),
        throwsArgumentError,
      );

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.closed),
      );
    });

    test('halfOpenProbes allows multiple concurrent probes', () async {
      var current = DateTime(2026, 1, 1);
      final breaker = CircuitBreakerMiddleware(
        failureThreshold: 1,
        halfOpenProbes: 2,
        openDuration: const Duration(seconds: 30),
        now: () => current,
      );

      await breaker.process(
        contextFor('https://example.com'),
        (ctx) => respond(500),
      );
      current = current.add(const Duration(seconds: 31));

      final gate1 = Completer<MiddlewareResponse>();
      final gate2 = Completer<MiddlewareResponse>();
      final probe1 = breaker.process(
        contextFor('https://example.com'),
        (ctx) => gate1.future,
      );
      final probe2 = breaker.process(
        contextFor('https://example.com'),
        (ctx) => gate2.future,
      );

      // Third concurrent request exceeds the probe budget
      await expectLater(
        breaker.process(
          contextFor('https://example.com'),
          (ctx) => respond(200),
        ),
        throwsA(isA<CircuitOpenException>()),
      );

      gate1.complete(await respond(200));
      gate2.complete(await respond(200));
      await probe1;
      await probe2;

      expect(
        breaker.stateForKey('https://example.com:443'),
        equals(CircuitState.closed),
      );
    });
  });

  group('edge cases: LoggingMiddleware', () {
    test('includeHeaders logs request and response headers', () async {
      final logs = <String>[];

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          return http.Response('ok', 200, headers: {'x-resp': 'pong'});
        }),
        middlewares: [LoggingMiddleware(onLog: logs.add, includeHeaders: true)],
      );

      await client.get(
        Uri.parse('https://example.com'),
        headers: {'x-req': 'ping'},
      );

      expect(logs.join('\n'), contains('x-req: ping'));
      expect(logs.join('\n'), contains('x-resp: pong'));

      client.close();
    });

    test('logs and rethrows errors', () async {
      final logs = <String>[];

      await expectLater(
        LoggingMiddleware(onLog: logs.add).process(
          MiddlewareContext(
            request: http.Request('GET', Uri.parse('https://example.com')),
          ),
          (ctx) => throw http.ClientException('boom'),
        ),
        throwsA(isA<http.ClientException>()),
      );

      expect(logs.last, contains('ERROR'));
      expect(logs.last, contains('boom'));
    });

    test('falls back to print without onLog', () async {
      final prints = <String>[];

      await runZoned(
        () => const LoggingMiddleware().process(
          MiddlewareContext(
            request: http.Request('GET', Uri.parse('https://example.com')),
          ),
          (ctx) async => MiddlewareResponse.immediate(
            http.StreamedResponse(Stream.value(<int>[]), 200),
          ),
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => prints.add(line),
        ),
      );

      expect(prints, hasLength(2));
      expect(prints[0], contains('-->'));
      expect(prints[1], contains('<--'));
    });

    test('onBackgroundError logs the failed request', () {
      final logs = <String>[];
      final middleware = LoggingMiddleware(onLog: logs.add);

      middleware.onBackgroundError(
        Exception('timeout'),
        StackTrace.current,
        MiddlewareContext(
          request: http.Request('GET', Uri.parse('https://example.com/bg')),
        ),
      );

      expect(logs.single, contains('[BG]'));
      expect(logs.single, contains('https://example.com/bg'));
      expect(logs.single, contains('timeout'));
    });
  });

  group('integration: composed chains', () {
    test('timeout counts as a circuit breaker failure', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async {
          await Future.delayed(const Duration(milliseconds: 200));
          return http.Response('slow', 200);
        }),
        middlewares: [
          CircuitBreakerMiddleware(failureThreshold: 1),
          const TimeoutMiddleware(Duration(milliseconds: 20)),
        ],
      );

      final uri = Uri.parse('https://example.com');

      await expectLater(client.get(uri), throwsA(isA<TimeoutException>()));

      // The timeout tripped the circuit: next request fails fast
      await expectLater(client.get(uri), throwsA(isA<CircuitOpenException>()));

      client.close();
    });

    test('dedup and SWR share one network call on a cold cache', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          await Future.delayed(const Duration(milliseconds: 30));
          return http.Response('shared', 200);
        }),
        middlewares: [
          DedupMiddleware(),
          SwrMiddleware(cache: cache),
        ],
      );

      final uri = Uri.parse('https://example.com/data');
      final responses = await Future.wait([
        client.get(uri),
        client.get(uri),
        client.get(uri),
      ]);

      expect(networkCalls, equals(1));
      for (final response in responses) {
        expect(response.body, equals('shared'));
      }
      expect(cache.length, equals(1));

      client.close();
    });

    test('standard chain serves watch with cache and revalidation', () async {
      var networkCalls = 0;

      final client = MiddlewareClient.standard(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('response $networkCalls', 200);
        }),
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      final events = await client.watchGet(uri).toList();

      expect(events, hasLength(2));
      expect(events[0].source, equals(WatchSource.cacheRevalidating));
      expect(events[0].response.body, equals('response 1'));
      expect(events[1].source, equals(WatchSource.network));
      expect(events[1].response.body, equals('response 2'));

      client.close();
    });
  });

  group('documented guarantees', () {
    test(
      'SWR serves cache while the circuit is open (graceful degradation)',
      () async {
        final cache = InMemorySwrCache();
        var networkCalls = 0;
        var backendDown = false;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            networkCalls++;
            if (backendDown) {
              return http.Response('down', 503);
            }
            return http.Response('healthy', 200);
          }),
          middlewares: [
            SwrMiddleware(cache: cache),
            CircuitBreakerMiddleware(failureThreshold: 1),
          ],
        );

        final cachedUri = Uri.parse('https://example.com/cached');
        final missUri = Uri.parse('https://example.com/miss');
        final missUri2 = Uri.parse('https://example.com/miss2');

        // Populate the cache while the backend is healthy
        await client.get(cachedUri);
        expect(networkCalls, equals(1));

        // Backend dies; a cache miss opens the circuit
        backendDown = true;
        final missResponse = await client.get(missUri);
        expect(missResponse.statusCode, equals(503));
        expect(networkCalls, equals(2));

        // Cached data is still served instantly despite the open circuit
        final cachedResponse = await client.get(cachedUri);
        expect(cachedResponse.body, equals('healthy'));

        // The background revalidation was rejected by the breaker silently
        await Future.delayed(const Duration(milliseconds: 100));
        expect(networkCalls, equals(2));
        final cached = await cache.get('GET:$cachedUri');
        expect(cached!.bodyString, equals('healthy'));

        // Only cache misses fail fast
        await expectLater(
          client.get(missUri2),
          throwsA(isA<CircuitOpenException>()),
        );

        client.close();
      },
    );

    test('background failure in an outer middleware releases the SWR '
        'revalidation lock', () async {
      final cache = InMemorySwrCache();
      var backgroundAttempts = 0;
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('ok', 200);
        }),
        middlewares: [
          // Fails background passes BEFORE they reach SwrMiddleware
          _FailInBackgroundMiddleware(
            onBackgroundAttempt: () {
              backgroundAttempts++;
            },
          ),
          SwrMiddleware(cache: cache),
        ],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);
      expect(networkCalls, equals(1));

      // Cache hit: revalidation starts and dies in the outer middleware
      await client.get(uri);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(backgroundAttempts, equals(1));

      // The lock must be released: the next cache hit revalidates again.
      // A leaked lock would make backgroundAttempts stay at 1 forever.
      await client.get(uri);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(backgroundAttempts, equals(2));

      client.close();
    });

    test(
      'failed network revalidation releases the SWR lock via send',
      () async {
        final cache = InMemorySwrCache();
        var networkCalls = 0;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            networkCalls++;
            if (networkCalls > 1) {
              throw http.ClientException('down');
            }
            return http.Response('good', 200);
          }),
          middlewares: [SwrMiddleware(cache: cache)],
        );

        final uri = Uri.parse('https://example.com/data');
        await client.get(uri);

        // Two cache hits, each must attempt its own revalidation
        final r1 = await client.get(uri);
        expect(r1.body, equals('good'));
        await Future.delayed(const Duration(milliseconds: 100));
        expect(networkCalls, equals(2));

        final r2 = await client.get(uri);
        expect(r2.body, equals('good'));
        await Future.delayed(const Duration(milliseconds: 100));
        expect(networkCalls, equals(3));

        client.close();
      },
    );

    test('revalidation picks up a refreshed auth token', () async {
      final cache = InMemorySwrCache();
      var tokenVersion = 0;
      final sentTokens = <String?>[];

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          sentTokens.add(request.headers['authorization']);
          return http.Response('ok', 200);
        }),
        middlewares: [
          HeadersMiddleware.builder((request) async {
            tokenVersion++;
            return {'authorization': 'Bearer token-$tokenVersion'};
          }),
          SwrMiddleware(cache: cache),
        ],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);
      // Cache hit: the revalidation re-runs the whole chain and must
      // carry a freshly built token, not the one from the first request
      await client.get(uri);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(sentTokens, hasLength(2));
      expect(sentTokens[0], equals('Bearer token-1'));
      expect(sentTokens[1], isNot(equals('Bearer token-1')));

      client.close();
    });

    test(
      'retry preserves the request body and headers across attempts',
      () async {
        final sentBodies = <String>[];
        final sentHeaders = <String?>[];
        var calls = 0;

        final client = MiddlewareClient(
          inner: MockClient((request) async {
            calls++;
            sentBodies.add(request.body);
            sentHeaders.add(request.headers['x-signed']);
            return calls == 1
                ? http.Response('unavailable', 503)
                : http.Response('ok', 200);
          }),
          middlewares: [
            HeadersMiddleware({'x-signed': 'signature'}),
            RetryMiddleware(
              shouldRetryRequest: (request) => true,
              delay: (_) => Duration.zero,
            ),
          ],
        );

        final response = await client.post(
          Uri.parse('https://example.com/submit'),
          body: 'important payload',
        );

        expect(response.statusCode, equals(200));
        expect(sentBodies, equals(['important payload', 'important payload']));
        expect(sentHeaders, equals(['signature', 'signature']));

        client.close();
      },
    );

    test('binary body survives the cache round-trip byte for byte', () async {
      final payload = Uint8List.fromList(
        List.generate(64 * 1024, (i) => i % 251),
      );

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          return http.Response.bytes(payload, 200);
        }),
        middlewares: [SwrMiddleware(cache: InMemorySwrCache())],
      );

      final uri = Uri.parse('https://example.com/blob');
      final fresh = await client.get(uri);
      expect(fresh.bodyBytes, equals(payload));

      // Served from cache
      final cached = await client.get(uri);
      expect(cached.bodyBytes, equals(payload));

      client.close();
    });

    test('non-ASCII body survives the cache round-trip', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async {
          return http.Response(
            'Привет, мир! 你好 🎉',
            200,
            headers: {'content-type': 'text/plain; charset=utf-8'},
          );
        }),
        middlewares: [SwrMiddleware(cache: InMemorySwrCache())],
      );

      final uri = Uri.parse('https://example.com/text');
      await client.get(uri);
      final cached = await client.get(uri);

      expect(cached.body, equals('Привет, мир! 你好 🎉'));

      client.close();
    });

    test('response headers survive the cache round-trip', () async {
      final client = MiddlewareClient(
        inner: MockClient((request) async {
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json', 'etag': '"abc123"'},
          );
        }),
        middlewares: [SwrMiddleware(cache: InMemorySwrCache())],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);
      final cached = await client.get(uri);

      expect(cached.headers['content-type'], equals('application/json'));
      expect(cached.headers['etag'], equals('"abc123"'));

      client.close();
    });

    test('watch on a non-cacheable request emits one network event', () async {
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response('created', 201);
        }),
        middlewares: [SwrMiddleware(cache: InMemorySwrCache())],
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://example.com/items'),
      );
      final events = await client.watch(request).toList();

      expect(events, hasLength(1));
      expect(events.single.source, equals(WatchSource.network));
      expect(events.single.response.statusCode, equals(201));
      expect(networkCalls, equals(1));

      client.close();
    });

    test(
      'watch on a cold cache with a dead network emits only an error',
      () async {
        final client = MiddlewareClient(
          inner: MockClient((request) async {
            throw http.ClientException('no connection');
          }),
          middlewares: [SwrMiddleware(cache: InMemorySwrCache())],
        );

        await expectLater(
          client.watchGet(Uri.parse('https://example.com')),
          emitsError(isA<http.ClientException>()),
        );

        client.close();
      },
    );

    test('timeout covers headers arrival, not the body download', () async {
      final client = MiddlewareClient(
        inner: _SlowBodyClient(),
        middlewares: [const TimeoutMiddleware(Duration(milliseconds: 30))],
      );

      // Headers arrive instantly, the body takes ~100ms: must not throw
      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.body, equals('slow body'));

      client.close();
    });

    test('standard with maxRetries: 0 does not retry', () async {
      var calls = 0;

      final client = MiddlewareClient.standard(
        inner: MockClient((request) async {
          calls++;
          return http.Response('unavailable', 503);
        }),
        maxRetries: 0,
      );

      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, equals(503));
      expect(calls, equals(1));

      client.close();
    });

    test('skipUnchanged treats header-only changes as unchanged', () async {
      final cache = InMemorySwrCache();
      var networkCalls = 0;

      final client = MiddlewareClient(
        inner: MockClient((request) async {
          networkCalls++;
          return http.Response(
            'same',
            200,
            headers: {'x-generation': '$networkCalls'},
          );
        }),
        middlewares: [SwrMiddleware(cache: cache)],
      );

      final uri = Uri.parse('https://example.com/data');
      await client.get(uri);

      // Same status and body, only headers differ: suppressed by contract
      final events = await client.watchGet(uri, skipUnchanged: true).toList();

      expect(events, hasLength(1));

      client.close();
    });
  });
}

// Test helpers

class _FailInBackgroundMiddleware extends HttpMiddleware {
  _FailInBackgroundMiddleware({required this.onBackgroundAttempt});

  final void Function() onBackgroundAttempt;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) {
    if (context.isBackground) {
      onBackgroundAttempt();
      throw http.ClientException('outer middleware failure');
    }
    return next(context);
  }
}

class _SlowBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> body() async* {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      yield utf8.encode('slow body');
    }

    return http.StreamedResponse(body(), 200);
  }
}

class _CustomRequest extends http.BaseRequest {
  _CustomRequest(super.method, super.url);

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream.fromBytes(const []);
  }
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(const <int>[]), 200);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

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
  void onBackgroundError(
    Object error,
    StackTrace stackTrace,
    MiddlewareContext context,
  ) {
    onError();
  }
}

class _BackgroundErrorCaptureMiddleware extends HttpMiddleware {
  _BackgroundErrorCaptureMiddleware(this.onBackgroundErrorContext);

  final void Function(MiddlewareContext context) onBackgroundErrorContext;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) {
    return next(context);
  }

  @override
  void onBackgroundError(
    Object error,
    StackTrace stackTrace,
    MiddlewareContext context,
  ) {
    onBackgroundErrorContext(context);
  }
}

class _ContextCaptureMiddleware extends HttpMiddleware {
  _ContextCaptureMiddleware(this.contexts, {this.onlyBackground = false});

  final List<MiddlewareContext> contexts;
  final bool onlyBackground;

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) {
    if (!onlyBackground || context.isBackground) {
      contexts.add(context);
    }
    return next(context);
  }
}
