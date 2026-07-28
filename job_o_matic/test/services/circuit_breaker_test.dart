import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/email/circuit_breaker.dart';

void main() {
  group('CircuitBreaker', () {
    late CircuitBreaker breaker;

    setUp(() {
      breaker = CircuitBreaker(
        failureThreshold: 3,
        timeout: const Duration(milliseconds: 100),
      );
    });

    test('initial state is closed', () {
      expect(breaker.state, CircuitBreakerState.closed);
      expect(breaker.canPass, isTrue);
    });

    test('trips to open after threshold failures', () {
      breaker.onFailure();
      expect(breaker.state, CircuitBreakerState.closed);

      breaker.onFailure();
      expect(breaker.state, CircuitBreakerState.closed);

      breaker.onFailure();
      expect(breaker.state, CircuitBreakerState.open);
      expect(breaker.canPass, isFalse);
    });

    test('resets failure count on success in closed state', () {
      breaker.onFailure();
      breaker.onFailure();
      breaker.onSuccess();

      // One more failure should not trip since counter was reset
      breaker.onFailure();
      expect(breaker.state, CircuitBreakerState.closed);
    });

    test('transitions to half-open after timeout', () async {
      breaker.onFailure();
      breaker.onFailure();
      breaker.onFailure();
      expect(breaker.state, CircuitBreakerState.open);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(breaker.canPass, isTrue);
      expect(breaker.state, CircuitBreakerState.halfOpen);
    });

    test('closes after success in half-open state', () async {
      final localBreaker = CircuitBreaker(
        failureThreshold: 3,
        timeout: const Duration(milliseconds: 50),
      );
      localBreaker.onFailure();
      localBreaker.onFailure();
      localBreaker.onFailure();

      await Future.delayed(const Duration(milliseconds: 80));

      expect(localBreaker.state, CircuitBreakerState.halfOpen);

      localBreaker.onSuccess();
      localBreaker.onSuccess();
      expect(localBreaker.state, CircuitBreakerState.closed);
    });

    test('opens again on failure in half-open state', () async {
      final localBreaker = CircuitBreaker(
        failureThreshold: 3,
        timeout: const Duration(milliseconds: 50),
      );
      localBreaker.onFailure();
      localBreaker.onFailure();
      localBreaker.onFailure();

      await Future.delayed(const Duration(milliseconds: 80));

      localBreaker.onFailure();
      expect(localBreaker.state, CircuitBreakerState.open);
    });

    test('reset restores closed state', () {
      breaker.onFailure();
      breaker.onFailure();
      breaker.onFailure();
      expect(breaker.state, CircuitBreakerState.open);

      breaker.reset();
      expect(breaker.state, CircuitBreakerState.closed);
      expect(breaker.canPass, isTrue);
    });

    test('stats provide accurate information', () {
      breaker.onFailure();
      breaker.onFailure();

      final stats = breaker.stats;
      expect(stats.failureCount, 2);
      expect(stats.isClosed, isTrue);
      expect(stats.failureThreshold, 3);
    });
  });
}