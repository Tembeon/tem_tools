import 'dart:async';

import 'package:http/http.dart' as http;

import '../http_middleware.dart';
import '../middleware_context.dart';
import '../middleware_response.dart';

/// The state of a single circuit.
enum CircuitState {
  /// Normal operation: requests pass through, failures are counted.
  closed,

  /// The circuit tripped: requests are rejected immediately with
  /// [CircuitOpenException] without touching the network.
  open,

  /// Recovery probe: a limited number of requests are let through.
  /// Success closes the circuit, failure reopens it.
  halfOpen,
}

/// Generates a circuit key from a request.
///
/// Requests with the same key share one circuit. The default groups
/// by scheme, host and port.
typedef CircuitKeyGenerator = String Function(http.BaseRequest request);

/// Determines if a request participates in circuit breaking at all.
///
/// Useful for exempting health checks or critical endpoints.
typedef ShouldBreakRequest = bool Function(http.BaseRequest request);

/// Determines if a response counts as a failure.
typedef IsFailureResponse = bool Function(http.StreamedResponse response);

/// Determines if a thrown error counts as a failure.
typedef IsFailureError = bool Function(Object error);

/// Called on every circuit state transition.
///
/// Useful for logging and metrics.
typedef CircuitStateListener =
    void Function(String key, CircuitState from, CircuitState to);

/// Thrown when a request is rejected because its circuit is open.
///
/// Deliberately NOT an [http.ClientException]: [RetryMiddleware] does not
/// retry it by default, so an open circuit fails fast instead of being
/// hammered by retries.
class CircuitOpenException implements Exception {
  /// Creates an exception for the circuit [key].
  CircuitOpenException({required this.key, required this.retryAfter});

  /// The circuit key that rejected the request.
  final String key;

  /// Time until the circuit transitions to half-open and allows a probe.
  ///
  /// [Duration.zero] means the circuit is half-open but its probe slots
  /// are taken.
  final Duration retryAfter;

  @override
  String toString() {
    return 'CircuitOpenException: circuit "$key" is open, '
        'retry after $retryAfter';
  }
}

/// A middleware implementing the Circuit Breaker pattern.
///
/// When a backend keeps failing, the circuit "trips" (opens) and further
/// requests are rejected locally with [CircuitOpenException] - instantly,
/// without touching the network. This gives users a fast failure instead
/// of a hanging spinner and gives the struggling backend room to recover.
///
/// ## State machine
///
/// Each circuit key (by default: scheme + host + port) has its own state:
///
/// - **closed** - requests flow, consecutive failures are counted.
///   Reaching [failureThreshold] opens the circuit.
/// - **open** - requests are rejected immediately. After [openDuration]
///   the circuit becomes half-open.
/// - **halfOpen** - up to [halfOpenProbes] requests are let through.
///   The first success closes the circuit; a failure reopens it.
///
/// ## Basic Usage
///
/// ```dart
/// final client = MiddlewareClient(
///   middlewares: [
///     SwrMiddleware(cache: cache),
///     RetryMiddleware(),
///     CircuitBreakerMiddleware(
///       failureThreshold: 5,
///       openDuration: const Duration(seconds: 30),
///     ),
///     TimeoutMiddleware(const Duration(seconds: 10)),
///   ],
/// );
/// ```
///
/// ## Placement
///
/// Place the breaker below [RetryMiddleware] and above [TimeoutMiddleware]:
///
/// - Below Retry: every retry attempt is checked and recorded, so a
///   failing backend trips the circuit faster, and [CircuitOpenException]
///   is not retried by default - retries stop as soon as the circuit opens.
/// - Above Timeout: timeouts propagate through the breaker and count
///   as failures.
///
/// With [SwrMiddleware] above the breaker, an open circuit degrades
/// gracefully: cache hits are still served instantly, only cache misses
/// and revalidations fail fast.
///
/// ## What counts as a failure
///
/// By default: 5xx responses, [http.ClientException] and
/// [TimeoutException] errors. Tune via [isFailureResponse] and
/// [isFailureError]:
///
/// ```dart
/// CircuitBreakerMiddleware(
///   // Also treat rate limiting as a reason to back off
///   isFailureResponse: (response) =>
///       response.statusCode >= 500 || response.statusCode == 429,
/// )
/// ```
///
/// Responses served from cache are ignored - they say nothing about
/// backend health.
///
/// ## Scoping
///
/// One middleware instance manages independent circuits per key.
/// Customize the key to scope circuits per endpoint instead of per host:
///
/// ```dart
/// CircuitBreakerMiddleware(
///   keyGenerator: (request) => '${request.url.host}${request.url.path}',
/// )
/// ```
///
/// ## Observability
///
/// Subscribe to transitions and inspect state:
///
/// ```dart
/// final breaker = CircuitBreakerMiddleware(
///   onStateChange: (key, from, to) => log.warning('$key: $from -> $to'),
/// );
///
/// breaker.stateForKey('https://api.example.com:443'); // CircuitState
/// breaker.reset(); // manually close all circuits
/// ```
class CircuitBreakerMiddleware extends HttpMiddleware {
  /// Creates a circuit breaker middleware.
  ///
  /// [failureThreshold] - consecutive failures that open the circuit.
  ///
  /// [openDuration] - how long the circuit stays open before allowing
  /// recovery probes.
  ///
  /// [halfOpenProbes] - how many concurrent probe requests are allowed
  /// in the half-open state.
  ///
  /// [keyGenerator] - groups requests into circuits.
  /// Defaults to `scheme://host:port`.
  ///
  /// [shouldBreak] - whether a request participates in circuit breaking.
  /// Defaults to all requests.
  ///
  /// [isFailureResponse] - whether a response counts as a failure.
  /// Defaults to 5xx.
  ///
  /// [isFailureError] - whether a thrown error counts as a failure.
  /// Defaults to [http.ClientException] and [TimeoutException].
  ///
  /// [onStateChange] - called on every state transition.
  ///
  /// [now] - clock override for testing.
  CircuitBreakerMiddleware({
    this.failureThreshold = 5,
    this.openDuration = const Duration(seconds: 30),
    this.halfOpenProbes = 1,
    CircuitKeyGenerator? keyGenerator,
    ShouldBreakRequest? shouldBreak,
    IsFailureResponse? isFailureResponse,
    IsFailureError? isFailureError,
    this.onStateChange,
    DateTime Function()? now,
  }) : assert(failureThreshold > 0, 'failureThreshold must be positive'),
       assert(halfOpenProbes > 0, 'halfOpenProbes must be positive'),
       keyGenerator = keyGenerator ?? _defaultKeyGenerator,
       shouldBreak = shouldBreak ?? _defaultShouldBreak,
       isFailureResponse = isFailureResponse ?? _defaultIsFailureResponse,
       isFailureError = isFailureError ?? _defaultIsFailureError,
       _now = now ?? DateTime.now;

  /// Consecutive failures that open the circuit.
  final int failureThreshold;

  /// How long the circuit stays open before allowing probes.
  final Duration openDuration;

  /// Concurrent probe requests allowed in the half-open state.
  final int halfOpenProbes;

  /// Groups requests into circuits.
  final CircuitKeyGenerator keyGenerator;

  /// Whether a request participates in circuit breaking.
  final ShouldBreakRequest shouldBreak;

  /// Whether a response counts as a failure.
  final IsFailureResponse isFailureResponse;

  /// Whether a thrown error counts as a failure.
  final IsFailureError isFailureError;

  /// Called on every state transition.
  final CircuitStateListener? onStateChange;

  final DateTime Function() _now;

  final Map<String, _Circuit> _circuits = {};

  static String _defaultKeyGenerator(http.BaseRequest request) {
    final url = request.url;
    return '${url.scheme}://${url.host}:${url.port}';
  }

  static bool _defaultShouldBreak(http.BaseRequest request) => true;

  static bool _defaultIsFailureResponse(http.StreamedResponse response) {
    return response.statusCode >= 500;
  }

  static bool _defaultIsFailureError(Object error) {
    return error is http.ClientException || error is TimeoutException;
  }

  @override
  Future<MiddlewareResponse> process(
    MiddlewareContext context,
    MiddlewareNext next,
  ) async {
    if (!shouldBreak(context.request)) {
      return next(context);
    }

    final key = keyGenerator(context.request);
    context.metadata['circuitBreaker:key'] = key;

    final circuit = _circuits.putIfAbsent(key, _Circuit.new);

    // Open -> halfOpen once the cooldown elapsed
    if (circuit.state == CircuitState.open) {
      final elapsed = _now().difference(circuit.openedAt!);
      if (elapsed >= openDuration) {
        _transition(key, circuit, CircuitState.halfOpen);
      } else {
        throw CircuitOpenException(
          key: key,
          retryAfter: openDuration - elapsed,
        );
      }
    }

    final isProbe = circuit.state == CircuitState.halfOpen;
    if (isProbe) {
      if (circuit.probesInFlight >= halfOpenProbes) {
        throw CircuitOpenException(key: key, retryAfter: Duration.zero);
      }
      circuit.probesInFlight++;
    }

    final MiddlewareResponse result;
    try {
      result = await next(context);
    } catch (error) {
      if (isFailureError(error)) {
        _recordFailure(key, circuit);
      }
      rethrow;
    } finally {
      if (isProbe) {
        circuit.probesInFlight--;
      }
    }

    // A cache hit says nothing about backend health
    if (context.isFromCache) {
      return result;
    }

    if (isFailureResponse(result.response)) {
      _recordFailure(key, circuit);
    } else {
      _recordSuccess(key, circuit);
    }

    return result;
  }

  void _recordFailure(String key, _Circuit circuit) {
    switch (circuit.state) {
      case CircuitState.closed:
        circuit.consecutiveFailures++;
        if (circuit.consecutiveFailures >= failureThreshold) {
          circuit.openedAt = _now();
          _transition(key, circuit, CircuitState.open);
        }
      case CircuitState.halfOpen:
        circuit.openedAt = _now();
        _transition(key, circuit, CircuitState.open);
      case CircuitState.open:
        // Late result of a request started before the circuit opened
        break;
    }
  }

  void _recordSuccess(String key, _Circuit circuit) {
    switch (circuit.state) {
      case CircuitState.closed:
        circuit.consecutiveFailures = 0;
      case CircuitState.halfOpen:
        _transition(key, circuit, CircuitState.closed);
      case CircuitState.open:
        // Late result of a request started before the circuit opened
        break;
    }
  }

  void _transition(String key, _Circuit circuit, CircuitState to) {
    final from = circuit.state;
    circuit.state = to;

    if (to == CircuitState.closed) {
      circuit.consecutiveFailures = 0;
      circuit.openedAt = null;
    }

    final listener = onStateChange;
    if (listener != null) {
      try {
        listener(key, from, to);
      } catch (_) {
        // Listener errors must not affect request processing
      }
    }
  }

  /// The current state of the circuit for [key].
  ///
  /// Returns [CircuitState.closed] for keys that were never used.
  /// Note that an open circuit reports [CircuitState.open] until a
  /// request actually probes it, even if [openDuration] already elapsed.
  CircuitState stateForKey(String key) {
    return _circuits[key]?.state ?? CircuitState.closed;
  }

  /// The current state of the circuit that [request] belongs to.
  CircuitState stateFor(http.BaseRequest request) {
    return stateForKey(keyGenerator(request));
  }

  /// Manually closes the circuit for [key], or all circuits when
  /// [key] is null.
  void reset([String? key]) {
    if (key != null) {
      final circuit = _circuits[key];
      if (circuit != null && circuit.state != CircuitState.closed) {
        _transition(key, circuit, CircuitState.closed);
      }
      return;
    }
    for (final entry in _circuits.entries) {
      if (entry.value.state != CircuitState.closed) {
        _transition(entry.key, entry.value, CircuitState.closed);
      }
    }
  }
}

/// Mutable state of a single circuit.
class _Circuit {
  CircuitState state = CircuitState.closed;

  /// Consecutive failures while closed.
  int consecutiveFailures = 0;

  /// When the circuit last opened. Non-null in the open state.
  DateTime? openedAt;

  /// Probe requests currently in flight while half-open.
  int probesInFlight = 0;
}
