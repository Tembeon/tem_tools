import 'package:http/http.dart' as http;

/// Where a [WatchEvent]'s data came from and whether more events follow.
enum WatchSource {
  /// Fresh response from the network. Always the final event of the stream.
  network,

  /// Cached (stale) response; a background refresh is in flight and its
  /// result will be emitted as the next event (unless `skipUnchanged`
  /// suppresses an identical response - then the stream just closes).
  cacheRevalidating,

  /// Cached (stale) response; no further events will be emitted on this
  /// stream. This happens when another request is already revalidating
  /// the same cache key, or when the request could not be cloned for
  /// revalidation.
  ///
  /// Note: the data may still get refreshed in the cache by that other
  /// request - it just won't arrive through this stream.
  cacheOnly,
}

/// A single emission of `MiddlewareClient.watch`.
///
/// Carries the response together with its origin, so subscribers can
/// distinguish cached data from fresh network data:
///
/// ```dart
/// client.watchGet(uri).listen((event) {
///   render(event.response.body);
///   switch (event.source) {
///     case WatchSource.cacheRevalidating:
///       showUpdatingBadge(); // stale data shown, fresh event follows
///     case WatchSource.cacheOnly:
///     case WatchSource.network:
///       hideUpdatingBadge(); // nothing else will arrive
///   }
/// });
/// ```
class WatchEvent {
  /// Creates a watch event.
  const WatchEvent({required this.response, required this.source});

  /// The buffered HTTP response.
  final http.Response response;

  /// Where the data came from and whether more events follow.
  final WatchSource source;

  /// True when [response] was served from cache (stale data),
  /// false when it came from the network.
  bool get isFromCache => source != WatchSource.network;

  /// True when a background refresh started by this watch is in flight
  /// and its result will be emitted as the next event.
  bool get isRevalidating => source == WatchSource.cacheRevalidating;

  @override
  String toString() {
    return 'WatchEvent(status: ${response.statusCode}, source: $source)';
  }
}
