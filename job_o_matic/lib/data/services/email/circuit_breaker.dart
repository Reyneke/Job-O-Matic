import 'package:logging/logging.dart';

/// Circuit Breaker für API-Ausfälle.
///
/// Zustände:
/// - CLOSED: Normalbetrieb, Anfragen werden durchgelassen
/// - OPEN: Fehler > Threshold, Anfragen werden blockiert
/// - HALF_OPEN: Test-Anfrage nach Timeout, entscheidet über nächsten Zustand
///
/// Verhindert kaskadierende Fehler bei API-Ausfällen.
class CircuitBreaker {
  final Logger _log = Logger('CircuitBreaker');
  final int _failureThreshold;
  final Duration _timeout;
  final Duration _halfOpenMaxAge;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _lastStateChange;
  int _successCount = 0;

  CircuitBreaker({
    int failureThreshold = 5,
    Duration? timeout,
    Duration? halfOpenMaxAge,
  })  : _failureThreshold = failureThreshold,
        _timeout = timeout ?? const Duration(seconds: 30),
        _halfOpenMaxAge = halfOpenMaxAge ?? const Duration(seconds: 60);

  /// Prüft, ob eine Anfrage durchgelassen werden darf.
  bool get canPass {
    _evaluateState();
    return _state != CircuitBreakerState.open;
  }

  /// Aktuellen Zustand abrufen (evaluiert vorher, ob Timeout abgelaufen).
  CircuitBreakerState get state {
    _evaluateState();
    return _state;
  }

  /// Erfolgreiche Anfrage melden.
  void onSuccess() {
    if (_state == CircuitBreakerState.halfOpen) {
      _successCount++;
      if (_successCount >= 2) {
        _reset();
        _log.info('Circuit Breaker: CLOSED (wiederhergestellt)');
      }
    } else if (_state == CircuitBreakerState.closed) {
      // Bei Erfolg im Closed-Zustand: Failure-Count zurücksetzen
      _failureCount = 0;
    }
  }

  /// Fehlgeschlagene Anfrage melden.
  void onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_state == CircuitBreakerState.halfOpen) {
      _tripToOpen();
      _log.warning('Circuit Breaker: OPEN (HALF-OPEN fehlgeschlagen)');
    } else if (_failureCount >= _failureThreshold) {
      _tripToOpen();
      _log.warning(
        'Circuit Breaker: OPEN (${_failureCount} Fehler erreicht)',
      );
    }
  }

  void _evaluateState() {
    if (_state == CircuitBreakerState.open && _lastStateChange != null) {
      final elapsed = DateTime.now().difference(_lastStateChange!);
      if (elapsed >= _timeout) {
        _state = CircuitBreakerState.halfOpen;
        _lastStateChange = DateTime.now();
        _successCount = 0;
        _log.info('Circuit Breaker: HALF-OPEN (Timeout abgelaufen)');
      }
    }
  }

  void _tripToOpen() {
    _state = CircuitBreakerState.open;
    _lastStateChange = DateTime.now();
  }

  void _reset() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _lastFailureTime = null;
    _lastStateChange = null;
    _successCount = 0;
  }

  /// Setzt den Circuit Breaker zurück.
  void reset() {
    _reset();
    _log.info('Circuit Breaker: Manuell zurückgesetzt');
  }

  /// Statistiken abrufen.
  CircuitBreakerStats get stats => CircuitBreakerStats(
        state: _state,
        failureCount: _failureCount,
        successCount: _successCount,
        lastFailureTime: _lastFailureTime,
        failureThreshold: _failureThreshold,
        timeout: _timeout,
      );
}

enum CircuitBreakerState { closed, open, halfOpen }

class CircuitBreakerStats {
  final CircuitBreakerState state;
  final int failureCount;
  final int successCount;
  final DateTime? lastFailureTime;
  final int failureThreshold;
  final Duration timeout;

  const CircuitBreakerStats({
    required this.state,
    required this.failureCount,
    required this.successCount,
    this.lastFailureTime,
    required this.failureThreshold,
    required this.timeout,
  });

  bool get isOpen => state == CircuitBreakerState.open;
  bool get isClosed => state == CircuitBreakerState.closed;
  bool get isHalfOpen => state == CircuitBreakerState.halfOpen;
}