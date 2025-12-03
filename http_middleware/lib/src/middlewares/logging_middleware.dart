import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// A callback function for custom log output.
typedef LogCallback = void Function(String message);

/// A middleware that logs HTTP requests and responses.
///
/// This is a simple but useful middleware that demonstrates the basic
/// middleware pattern. It logs request method, URL, response status,
/// and timing information.
///
/// ## Basic Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(),
///   ],
/// );
/// ```
///
/// ## Custom Logger
///
/// You can provide a custom logging function:
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     LoggingMiddleware(
///       onLog: (message) => myLogger.info(message),
///     ),
///   ],
/// );
/// ```
///
/// ## Output Format
///
/// Requests are logged as:
/// ```
/// --> GET https://api.example.com/data
/// <-- 200 OK (123ms)
/// ```
///
/// Background requests are prefixed with [BG]:
/// ```
/// [BG] --> GET https://api.example.com/data
/// [BG] <-- 200 OK (456ms)
/// ```
///
/// Cache hits are noted:
/// ```
/// --> GET https://api.example.com/data
/// <-- 200 OK [CACHE] (2ms)
/// ```
class LoggingMiddleware extends HttpMiddleware {
  /// Creates a logging middleware.
  ///
  /// [onLog] is an optional callback for custom log output.
  /// If not provided, logs are printed to stdout using [print].
  ///
  /// [includeHeaders] controls whether request/response headers are logged.
  /// Defaults to false for privacy and brevity.
  const LoggingMiddleware({
    LogCallback? onLog,
    this.includeHeaders = false,
  }) : _onLog = onLog;

  final LogCallback? _onLog;

  /// Whether to include headers in the log output.
  final bool includeHeaders;

  void _log(String message) {
    if (_onLog != null) {
      _onLog(message);
    } else {
      print(message);
    }
  }

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    final request = context.request;
    final prefix = context.isBackground ? '[BG] ' : '';

    // Log request
    _log('$prefix--> ${request.method} ${request.url}');
    if (includeHeaders && request.headers.isNotEmpty) {
      for (final entry in request.headers.entries) {
        _log('$prefix    ${entry.key}: ${entry.value}');
      }
    }

    // Time the request
    final stopwatch = Stopwatch()..start();

    try {
      final response = await next(context);
      stopwatch.stop();

      // Build status info
      final cacheInfo = context.isFromCache ? ' [CACHE]' : '';
      final statusText = response.response.reasonPhrase ?? '';

      // Log response
      _log('$prefix<-- ${response.response.statusCode} $statusText'
          '$cacheInfo (${stopwatch.elapsedMilliseconds}ms)');

      if (includeHeaders && response.response.headers.isNotEmpty) {
        for (final entry in response.response.headers.entries) {
          _log('$prefix    ${entry.key}: ${entry.value}');
        }
      }

      return response;
    } catch (error) {
      stopwatch.stop();
      _log('$prefix<-- ERROR: $error (${stopwatch.elapsedMilliseconds}ms)');
      rethrow;
    }
  }

  @override
  void onBackgroundError(Object error, StackTrace stackTrace) {
    _log('[BG] Background request failed: $error');
  }
}
