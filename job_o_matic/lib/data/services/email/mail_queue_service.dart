import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Status eines Mail-Queue-Eintrags.
enum MailStatus {
  pending,
  queued,
  sending,
  sent,
  failed,
  bounced;

  String get displayName {
    switch (this) {
      case MailStatus.pending:
        return 'Ausstehend';
      case MailStatus.queued:
        return 'In Warteschlange';
      case MailStatus.sending:
        return 'Wird gesendet';
      case MailStatus.sent:
        return 'Gesendet';
      case MailStatus.failed:
        return 'Fehlgeschlagen';
      case MailStatus.bounced:
        return 'Zurückgewiesen';
    }
  }
}

/// Eintrag in der Mail-Queue.
class MailQueueEntry {
  final String id;
  final String to;
  final String subject;
  final String body;
  final String? pdfPath;
  final String? applicationId;
  final MailStatus status;
  final DateTime createdAt;
  final DateTime? lastTryAt;
  final DateTime? nextTryAt;
  final int retryCount;
  final String? errorMessage;

  const MailQueueEntry({
    required this.id,
    required this.to,
    required this.subject,
    required this.body,
    this.pdfPath,
    this.applicationId,
    this.status = MailStatus.pending,
    required this.createdAt,
    this.lastTryAt,
    this.nextTryAt,
    this.retryCount = 0,
    this.errorMessage,
  });

  MailQueueEntry copyWith({
    String? id,
    String? to,
    String? subject,
    String? body,
    String? pdfPath,
    String? applicationId,
    MailStatus? status,
    DateTime? createdAt,
    DateTime? lastTryAt,
    DateTime? nextTryAt,
    int? retryCount,
    String? errorMessage,
  }) {
    return MailQueueEntry(
      id: id ?? this.id,
      to: to ?? this.to,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      pdfPath: pdfPath ?? this.pdfPath,
      applicationId: applicationId ?? this.applicationId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      lastTryAt: lastTryAt ?? this.lastTryAt,
      nextTryAt: nextTryAt ?? this.nextTryAt,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Queue-System für den E-Mail-Versand.
///
/// Features:
/// - Einträge mit Status (pending → queued → sending → sent/failed/bounced)
/// - Retry mit exponentiellem Backoff (1min → 5min → 30min → 2h → max 4 Versuche)
/// - Rate-Limiter (konfigurierbar, Standard: 5 E-Mails pro Minute)
/// - Priorisierung von Einträgen
class MailQueueService {
  final Logger _log = Logger('MailQueueService');
  final Uuid _uuid = const Uuid();
  final Queue<MailQueueEntry> _queue = Queue();
  final List<MailQueueEntry> _allEntries = [];

  int _emailsSentInWindow = 0;
  DateTime _windowStart = DateTime.now();
  Timer? _rateLimitTimer;

  final int _maxEmailsPerMinute;
  final int _maxRetries;

  /// Callback für tatsächlichen E-Mail-Versand.
  Future<MailStatus> Function(MailQueueEntry entry)? onSendEmail;

  MailQueueService({
    int maxEmailsPerMinute = 5,
    int maxRetries = 4,
  })  : _maxEmailsPerMinute = maxEmailsPerMinute,
        _maxRetries = maxRetries;

  /// Fügt eine E-Mail zur Queue hinzu.
  String enqueue({
    required String to,
    required String subject,
    required String body,
    String? pdfPath,
    String? applicationId,
  }) {
    final entry = MailQueueEntry(
      id: _uuid.v4(),
      to: to,
      subject: subject,
      body: body,
      pdfPath: pdfPath,
      applicationId: applicationId,
      status: MailStatus.pending,
      createdAt: DateTime.now(),
    );
    _allEntries.add(entry);
    _queue.add(entry);
    _log.info('E-Mail gequeued: $subject → $to (ID: ${entry.id})');
    return entry.id;
  }

  /// Verarbeitet die Queue (wird periodisch aufgerufen).
  Future<void> processQueue() async {
    if (onSendEmail == null) {
      _log.warning('Kein sendEmail-Callback registriert');
      return;
    }

    _resetWindowIfNeeded();

    while (_queue.isNotEmpty && _emailsSentInWindow < _maxEmailsPerMinute) {
      final entry = _queue.first;

      // Prüfen, ob der Eintrag bereits gesendet werden darf
      if (entry.status == MailStatus.pending ||
          (entry.status == MailStatus.failed &&
              entry.nextTryAt != null &&
              DateTime.now().isBefore(entry.nextTryAt!))) {
        // Noch nicht bereit zum Senden
        break;
      }

      _queue.removeFirst();

      // Status auf sending setzen
      _updateEntry(entry, status: MailStatus.sending);

      try {
        _log.info('Sende E-Mail: ${entry.subject} → ${entry.to}');
        final result = await onSendEmail!(entry);

        _emailsSentInWindow++;

        if (result == MailStatus.sent) {
          _updateEntry(entry, status: MailStatus.sent);
          _log.info('E-Mail erfolgreich gesendet: ${entry.id}');
        } else {
          _handleFailure(entry, 'Versand fehlgeschlagen');
        }
      } catch (e) {
        _handleFailure(entry, e.toString());
      }
    }
  }

  /// Behandelt einen fehlgeschlagenen Versand mit Retry-Logik.
  void _handleFailure(MailQueueEntry entry, String errorMessage) {
    final newRetryCount = entry.retryCount + 1;

    if (newRetryCount >= _maxRetries) {
      // Endgültig fehlgeschlagen
      _updateEntry(
        entry,
        status: MailStatus.failed,
        retryCount: newRetryCount,
        errorMessage: errorMessage,
      );
      _log.severe('E-Mail endgültig fehlgeschlagen: ${entry.id} ($errorMessage)');
    } else {
      // Retry mit Backoff
      final backoff = _calculateBackoff(newRetryCount);
      _updateEntry(
        entry,
        status: MailStatus.failed,
        retryCount: newRetryCount,
        nextTryAt: DateTime.now().add(backoff),
        errorMessage: errorMessage,
      );
      _log.warning(
        'E-Mail-Versand fehlgeschlagen (Versuch $newRetryCount/$_maxRetries): '
        '${entry.id} – nächster Versuch in ${backoff.inMinutes}min',
      );
      // Wieder in die Queue einreihen
      _queue.add(entry);
    }
  }

  /// Exponentieller Backoff: 1min → 5min → 30min → 2h
  Duration _calculateBackoff(int retryCount) {
    switch (retryCount) {
      case 1:
        return const Duration(minutes: 1);
      case 2:
        return const Duration(minutes: 5);
      case 3:
        return const Duration(minutes: 30);
      default:
        return const Duration(hours: 2);
    }
  }

  void _updateEntry(
    MailQueueEntry entry, {
    MailStatus? status,
    int? retryCount,
    DateTime? lastTryAt,
    DateTime? nextTryAt,
    String? errorMessage,
  }) {
    final index = _allEntries.indexOf(entry);
    if (index >= 0) {
      _allEntries[index] = entry.copyWith(
        status: status,
        retryCount: retryCount,
        lastTryAt: lastTryAt ?? DateTime.now(),
        nextTryAt: nextTryAt,
        errorMessage: errorMessage,
      );
    }
  }

  void _resetWindowIfNeeded() {
    final now = DateTime.now();
    if (now.difference(_windowStart).inMinutes >= 1) {
      _emailsSentInWindow = 0;
      _windowStart = now;
      _log.fine('Rate-Limit-Fenster zurückgesetzt');
    }
  }

  /// Alle Queue-Einträge abrufen.
  List<MailQueueEntry> get allEntries => List.unmodifiable(_allEntries);

  /// Anzahl der ausstehenden E-Mails.
  int get pendingCount =>
      _allEntries.where((e) => e.status == MailStatus.pending).length;

  /// Anzahl der gesendeten E-Mails.
  int get sentCount =>
      _allEntries.where((e) => e.status == MailStatus.sent).length;

  /// Anzahl der fehlgeschlagenen E-Mails.
  int get failedCount =>
      _allEntries.where((e) => e.status == MailStatus.failed).length;

  void dispose() {
    _rateLimitTimer?.cancel();
  }
}