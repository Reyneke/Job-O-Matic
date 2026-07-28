import 'dart:async';
import 'package:logging/logging.dart';
import 'email_service.dart';
import 'mail_queue_service.dart';
import 'email_template_service.dart';
import 'circuit_breaker.dart';

/// Orchestriert den E-Mail-Versand mit Queue, Circuit Breaker und Template.
///
/// Verbindet MailQueueService, EmailService, EmailTemplateService
/// und CircuitBreaker zu einer Einheit.
class MailDispatcher {
  final Logger _log = Logger('MailDispatcher');
  final MailQueueService _queueService;
  final EmailService _emailService;
  final EmailTemplateService _templateService;
  final CircuitBreaker _circuitBreaker;

  Timer? _processingTimer;
  bool _isProcessing = false;

  MailDispatcher({
    required MailQueueService queueService,
    required EmailService emailService,
    required EmailTemplateService templateService,
    CircuitBreaker? circuitBreaker,
  })  : _queueService = queueService,
        _emailService = emailService,
        _templateService = templateService,
        _circuitBreaker = circuitBreaker ?? CircuitBreaker();

  /// Startet die periodische Queue-Verarbeitung.
  void start({Duration interval = const Duration(minutes: 1)}) {
    _queueService.onSendEmail = _sendEmail;

    _processingTimer = Timer.periodic(interval, (_) async {
      await processQueue();
    });

    _log.info(
      'MailDispatcher gestartet (Intervall: ${interval.inMinutes}min)',
    );
  }

  /// Stoppt die Queue-Verarbeitung.
  void stop() {
    _processingTimer?.cancel();
    _processingTimer = null;
    _queueService.onSendEmail = null;
    _log.info('MailDispatcher gestoppt');
  }

  /// Einmalige Queue-Verarbeitung.
  Future<void> processQueue() async {
    if (_isProcessing) {
      _log.fine('Queue wird bereits verarbeitet – übersprungen');
      return;
    }

    if (!_circuitBreaker.canPass) {
      _log.warning(
        'Circuit Breaker ist OPEN – Queue-Verarbeitung pausiert',
      );
      return;
    }

    _isProcessing = true;
    try {
      await _queueService.processQueue();

      // Bei Erfolg: Circuit Breaker zurücksetzen
      if (_queueService.sentCount > 0) {
        _circuitBreaker.onSuccess();
      }
    } catch (e) {
      _circuitBreaker.onFailure();
      _log.severe('Fehler bei Queue-Verarbeitung: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Fügt eine E-Mail zur Queue hinzu.
  String enqueueApplicationEmail({
    required String to,
    required String position,
    required String company,
    required String fullName,
    String? customBodyTemplate,
    String? customSubjectTemplate,
    String? pdfPath,
    String? applicationId,
  }) {
    final subject = _templateService.buildSubject(
      position: position,
      company: company,
      customTemplate: customSubjectTemplate,
    );

    final body = _templateService.buildApplicationBody(
      position: position,
      company: company,
      fullName: fullName,
      customTemplate: customBodyTemplate,
    );

    return _queueService.enqueue(
      to: to,
      subject: subject,
      body: body,
      pdfPath: pdfPath,
      applicationId: applicationId,
    );
  }

  /// Callback für den tatsächlichen E-Mail-Versand.
  Future<MailStatus> _sendEmail(MailQueueEntry entry) async {
    if (!_circuitBreaker.canPass) {
      _log.warning('Circuit Breaker blockiert den Versand');
      return MailStatus.failed;
    }

    try {
      final result = await _emailService.sendEmail(
        to: entry.to,
        subject: entry.subject,
        htmlContent: entry.body.replaceAll('\n', '<br>\n'),
      );

      if (result.success) {
        _circuitBreaker.onSuccess();
        return MailStatus.sent;
      } else {
        _circuitBreaker.onFailure();
        _log.severe(
          'E-Mail-Versand fehlgeschlagen: ${result.errorMessage}',
        );
        return MailStatus.failed;
      }
    } catch (e) {
      _circuitBreaker.onFailure();
      _log.severe('Fehler beim E-Mail-Versand: $e');
      return MailStatus.failed;
    }
  }

  /// Prüft, ob der E-Mail-Dienst konfiguriert ist.
  Future<bool> isConfigured() => _emailService.isConfigured();

  /// Statistiken abrufen.
  MailDispatcherStats get stats => MailDispatcherStats(
        queueLength: _queueService.allEntries.length,
        pendingCount: _queueService.pendingCount,
        sentCount: _queueService.sentCount,
        failedCount: _queueService.failedCount,
        circuitBreakerState: _circuitBreaker.state,
        isProcessing: _isProcessing,
      );

  void dispose() {
    stop();
    _emailService.dispose();
    _queueService.dispose();
  }
}

class MailDispatcherStats {
  final int queueLength;
  final int pendingCount;
  final int sentCount;
  final int failedCount;
  final CircuitBreakerState circuitBreakerState;
  final bool isProcessing;

  const MailDispatcherStats({
    required this.queueLength,
    required this.pendingCount,
    required this.sentCount,
    required this.failedCount,
    required this.circuitBreakerState,
    required this.isProcessing,
  });
}