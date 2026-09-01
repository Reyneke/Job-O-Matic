import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'mail_queue_store.dart';

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
  final String? senderName;
  final String? senderEmail;
  final List<String> cc;
  final List<String> bcc;

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
    this.senderName,
    this.senderEmail,
    this.cc = const [],
    this.bcc = const [],
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
    String? senderName,
    String? senderEmail,
    List<String>? cc,
    List<String>? bcc,
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
      senderName: senderName ?? this.senderName,
      senderEmail: senderEmail ?? this.senderEmail,
      cc: cc ?? this.cc,
      bcc: bcc ?? this.bcc,
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
  final MailQueueStore? _store;

  /// Callback für tatsächlichen E-Mail-Versand.
  Future<MailStatus> Function(MailQueueEntry entry)? onSendEmail;

  MailQueueService({
    int maxEmailsPerMinute = 5,
    int maxRetries = 4,
    MailQueueStore? store,
  }) : _maxEmailsPerMinute = maxEmailsPerMinute,
       _maxRetries = maxRetries,
       _store = store;

  /// Loads pending queue entries (`pending`/`queued`, or `failed` with
  /// expired retry) from the store on app start.
  ///
  /// No silent auto-send — entries are surfaced in the send screen and the
  /// user re-confirms dispatch (per doc/plan/14-Email.md §Fehlerbehandlung).
  Future<void> requeuePendingEmails() async {
    final store = _store;
    if (store == null) return;
    final pending = await store.loadPending();
    if (pending.isEmpty) return;
    for (final entry in pending) {
      _allEntries.add(entry);
      if (entry.status == MailStatus.pending ||
          entry.status == MailStatus.queued) {
        _queue.add(entry);
      } else if (entry.status == MailStatus.failed &&
          entry.nextTryAt != null &&
          DateTime.now().isAfter(entry.nextTryAt!)) {
        _queue.add(entry);
      }
    }
    _log.info(
      '${pending.length} pending queue entries reloaded after app start',
    );
  }

  /// Fügt eine E-Mail zur Queue hinzu (persistiert, falls ein Store gesetzt ist).
  Future<String> enqueue({
    required String to,
    required String subject,
    required String body,
    String? pdfPath,
    String? applicationId,
    String? senderName,
    String? senderEmail,
    List<String>? cc,
    List<String>? bcc,
  }) async {
    final entry = MailQueueEntry(
      id: _uuid.v4(),
      to: to,
      subject: subject,
      body: body,
      pdfPath: pdfPath,
      applicationId: applicationId,
      status: MailStatus.pending,
      createdAt: DateTime.now(),
      senderName: senderName,
      senderEmail: senderEmail,
      cc: cc ?? const [],
      bcc: bcc ?? const [],
    );
    _allEntries.add(entry);
    _queue.add(entry);
    final store = _store;
    if (store != null) {
      await store.insert(entry);
    }
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

      // Nur fehlgeschlagene Einträge mit zukünftigem Retry überspringen.
      // Pending-Einträge werden sofort versandt (Status-Übergang pending → sending).
      if (entry.status == MailStatus.failed &&
          entry.nextTryAt != null &&
          DateTime.now().isBefore(entry.nextTryAt!)) {
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
      _log.severe(
        'E-Mail endgültig fehlgeschlagen: ${entry.id} ($errorMessage)',
      );
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
    // Per ID statt Objekt-Identität suchen – nach copyWith-Updates ist das
    // Original-Objekt nicht mehr in der Liste (sonst gehen Status-Updates
    // bei Retries ins Leere). Siehe doc/plan/14-Email.md Phase B (Gap fix).
    final index = _allEntries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      _allEntries[index] = _allEntries[index].copyWith(
        status: status,
        retryCount: retryCount,
        lastTryAt: lastTryAt ?? DateTime.now(),
        nextTryAt: nextTryAt,
        errorMessage: errorMessage,
      );
    }
    // Persistenz: Status/Fehler/NextTryAt im Store aktualisieren, falls
    // ein Store konfiguriert ist. (Vollständige Entry-Synchronisation
    // läuft über `update`; hier reicht der Status-Teil für die Lifecycle-
    // States.)
    final store = _store;
    if (store != null) {
      store.updateStatus(
        entry.id,
        status ?? entry.status,
        retryCount: retryCount ?? (status != null ? entry.retryCount : null),
        lastTryAt: lastTryAt ?? (status != null ? DateTime.now() : null),
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
