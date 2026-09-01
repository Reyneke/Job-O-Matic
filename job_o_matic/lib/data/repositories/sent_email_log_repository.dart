import 'package:logging/logging.dart';
import '../../models/sent_email_log_entry.dart';
import '../database/database_helper.dart';

/// Repository für das Versand-Audit-Log (`sent_email_log`).
///
/// Jeder Versandversuch (auch Wiederholungen und „Als Entwurf exportieren“)
/// erhält einen eigenen Eintrag – so lässt sich nachvollziehen, wann wie oft
/// an dieselbe Stelle gesendet wurde („Zuletzt gesendet am“ in der Ergebnisübersicht
/// und im Versand-Screen).
class SentEmailLogRepository {
  final Logger _log = Logger('SentEmailLogRepository');
  final DatabaseHelper _dbHelper;

  SentEmailLogRepository({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  /// Legt einen Log-Eintrag an und gibt dessen ID zurück.

  Future<int> insert(SentEmailLogEntry entry) async {
    final db = await _dbHelper.database;
    final id = await db.insert('sent_email_log', {
      'application_id': entry.applicationId,
      'recipient_email': entry.recipientEmail,
      'subject': entry.subject,
      'message_id': entry.messageId,
      'status': entry.status.storeValue,
      'error_message': entry.errorMessage,
      'sent_at': entry.sentAt.toUtc().toIso8601String(),
    });
    _log.fine(
      'Audit-Log-Eintrag ${entry.id ?? id}: ${entry.status.storeValue} für Application ${entry.applicationId}',
    );
    return id;
  }

  /// „Zuletzt gesendet am“ – MAX(sent_at) je Bewerbung.

  Future<DateTime?> latestSentAt(int applicationId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT MAX(sent_at) AS max_sent FROM sent_email_log WHERE application_id = ?',
      [applicationId],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['max_sent'] as String?;
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  /// History-Prüfung für den Dublettenschutz: Wurde an die Bewerbung bereits
  /// erfolgreich gesendet?
  Future<bool> hasSent(int applicationId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sent_email_log',
      where: 'application_id = ? AND status = ?',
      whereArgs: [applicationId, SentEmailLogStatus.sent.storeValue],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Löscht Log-Einträge älter als [cutoff] (Retention, DSGVO).
  Future<int> deleteOlderThan(DateTime cutoff) async {
    final db = await _dbHelper.database;
    final deleted = await db.delete(
      'sent_email_log',
      where: 'sent_at < ?',
      whereArgs: [cutoff.toUtc().toIso8601String()],
    );
    _log.fine('Retention: $deleted Log-Einträge älter als $cutoff gelöscht');
    return deleted;
  }

  /// Löscht alle Log-Einträge einer Bewerbung (z. B. vor dem Löschen der
  /// Application, da bewusst kein `ON DELETE CASCADE` gesetzt ist).
  Future<int> deleteByApplication(int applicationId) async {
    final db = await _dbHelper.database;
    return db.delete(
      'sent_email_log',
      where: 'application_id = ?',
      whereArgs: [applicationId],
    );
  }

  /// Löscht das gesamte Log (Button „Verlauf löschen“ in den Einstellungen).
  Future<int> deleteAll() async {
    final db = await _dbHelper.database;
    return db.delete('sent_email_log');
  }
}
