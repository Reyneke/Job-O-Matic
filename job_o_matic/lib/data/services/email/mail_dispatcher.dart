import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../../../models/sent_email_log_entry.dart';
import '../../repositories/database_repository.dart';
import '../../repositories/sent_email_log_repository.dart';
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
  final SentEmailLogRepository? _sentEmailLogRepository;
  final DatabaseRepository? _databaseRepository;

  /// Brevo Free-Tier: max. 300 E-Mails pro Kalendertag (siehe
  /// doc/plan/14-Email.md §Fehlerbehandlung).
  static const int _dailyMailLimit = 300;

  Timer? _processingTimer;
  bool _isProcessing = false;

  MailDispatcher({
    required MailQueueService queueService,
    required EmailService emailService,
    required EmailTemplateService templateService,
    CircuitBreaker? circuitBreaker,
    SentEmailLogRepository? sentEmailLogRepository,
    DatabaseRepository? databaseRepository,
  }) : _queueService = queueService,
       _emailService = emailService,
       _templateService = templateService,
       _circuitBreaker = circuitBreaker ?? CircuitBreaker(),
       _sentEmailLogRepository = sentEmailLogRepository,
       _databaseRepository = databaseRepository;

  /// Startet die periodische Queue-Verarbeitung.
  void start({Duration interval = const Duration(minutes: 1)}) {
    _queueService.onSendEmail = _sendEmail;

    _processingTimer = Timer.periodic(interval, (_) async {
      await processQueue();
    });

    _log.info('MailDispatcher gestartet (Intervall: ${interval.inMinutes}min)');
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
      _log.warning('Circuit Breaker ist OPEN – Queue-Verarbeitung pausiert');
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
  Future<String> enqueueApplicationEmail({
    required String to,
    required String position,
    required String company,
    required String fullName,
    String? customBodyTemplate,
    String? customSubjectTemplate,
    String? pdfPath,
    String? applicationId,
    String? senderName,
    String? senderEmail,
    List<String>? cc,
    List<String>? bcc,
  }) async {
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
      senderName: senderName,
      senderEmail: senderEmail,
      cc: cc,
      bcc: bcc,
    );
  }

  /// Callback für den tatsächlichen E-Mail-Versand.
  Future<MailStatus> _sendEmail(MailQueueEntry entry) async {
    if (!_circuitBreaker.canPass) {
      _log.warning('Circuit Breaker blockiert den Versand');
      return MailStatus.failed;
    }

    // Anhänge laden (MVP: die kombinierte Bewerbungs-PDF aus pdfPath).
    final attachments = await _loadAttachments(entry.pdfPath);
    if (attachments == null) {
      return MailStatus.failed;
    }

    try {
      // Persistentes Tageslimit (300/Tag Free-Tier): vor dem Versand prüfen –
      // der Zähler in `search_filters` überlebt den App-Neustart.
      final repo = _databaseRepository;
      if (repo != null) {
        final todayCount = await repo.getMailCountForToday();
        if (todayCount >= _dailyMailLimit) {
          _log.warning(
            'Tageslimit erreicht ($todayCount/$_dailyMailLimit) – Versand '
            'übersprungen für ${entry.id} (Rest bleibt pending)',
          );
          return MailStatus.failed;
        }
      }

      final result = await _emailService.sendEmail(
        to: entry.to,
        subject: entry.subject,
        htmlContent: entry.body.replaceAll('\n', '<br>\n'),
        attachments: attachments,
        senderName: entry.senderName,
        senderEmail: entry.senderEmail,
        replyToName: entry.senderName,
        replyToEmail: entry.senderEmail ?? EmailService.defaultSenderEmail,
        cc: entry.cc.isEmpty ? null : entry.cc,
        bcc: entry.bcc.isEmpty ? null : entry.bcc,
      );

      if (result.success) {
        _circuitBreaker.onSuccess();
        await _writeAuditLog(
          entry,
          status: SentEmailLogStatus.sent,
          messageId: result.messageId,
        );
        await repo?.incrementMailCountForToday();
        return MailStatus.sent;
      } else {
        _circuitBreaker.onFailure();
        _logFailure(result);
        _queueService.recordSendError(
          entry.id,
          result.errorMessage ?? 'Versand fehlgeschlagen',
        );
        await _writeAuditLog(
          entry,
          status: SentEmailLogStatus.failed,
          errorMessage: result.errorMessage,
        );
        return MailStatus.failed;
      }
    } catch (e) {
      _circuitBreaker.onFailure();
      _log.severe('Fehler beim E-Mail-Versand: $e');
      _queueService.recordSendError(entry.id, e.toString());
      await _writeAuditLog(
        entry,
        status: SentEmailLogStatus.failed,
        errorMessage: e.toString(),
      );
      return MailStatus.failed;
    }
  }

  /// Schreibt einen Audit-Log-Eintrag in `sent_email_log` – ein Eintrag pro
  /// Versandversuch (auch Wiederholungen). Bewusst ohne Blockieren des
  /// Versands: Logging-Fehler werden geloggt, aber nicht weitergereicht.
  Future<void> _writeAuditLog(
    MailQueueEntry entry, {
    required SentEmailLogStatus status,
    String? messageId,
    String? errorMessage,
  }) async {
    final repo = _sentEmailLogRepository;
    final applicationId = int.tryParse(entry.applicationId ?? '');
    if (repo == null || applicationId == null) return;
    try {
      await repo.insert(
        SentEmailLogEntry(
          applicationId: applicationId,
          recipientEmail: entry.to,
          subject: entry.subject,
          messageId: messageId,
          status: status,
          errorMessage: errorMessage,
          sentAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _log.severe('Audit-Log-Eintrag konnte nicht geschrieben werden: $e');
    }
  }

  /// Lädt die Bewerbungs-PDF als Anhang. Gibt `null` zurück, wenn keine
  /// PDF vorhanden (bzw. nicht lesbar) ist → Eintrag wird als failed markiert.
  Future<List<EmailAttachment>?> _loadAttachments(String? pdfPath) async {
    if (pdfPath == null) {
      _log.warning(
        'Keine PDF hinterlegt (pdfPath == null) – Eintrag wird als failed '
        'markiert („PDF fehlt – neu generieren“)',
      );
      return null;
    }
    try {
      final file = File(pdfPath);
      if (!await file.exists()) {
        _log.warning(
          'PDF nicht gefunden: $pdfPath – Eintrag wird als failed markiert',
        );
        return null;
      }
      final bytes = await file.readAsBytes();
      return [EmailAttachment(filename: p.basename(pdfPath), bytes: bytes)];
    } catch (e) {
      _log.severe('PDF konnte nicht als Anhang geladen werden: $e');
      return null;
    }
  }

  /// Loggt die Fehlerklassifikation (Grundlage für UI-Fallbacks wie
  /// „Als Entwurf exportieren“ bei nicht verifiziertem Absender).
  void _logFailure(EmailResult result) {
    final failure = result.failure;
    if (failure == EmailFailure.unverifiedSender) {
      _log.severe(
        'Absender nicht verifiziert (401) – „Als Entwurf exportieren“ wird '
        'empfohlen: ${result.errorMessage}',
      );
    } else if (failure == EmailFailure.rateLimited) {
      _log.warning('Brevo-Rate-Limit erreicht (429): ${result.errorMessage}');
    } else if (failure == EmailFailure.server) {
      _log.severe('Brevo-Serverfehler: ${result.errorMessage}');
    } else {
      _log.severe('E-Mail-Versand fehlgeschlagen: ${result.errorMessage}');
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
