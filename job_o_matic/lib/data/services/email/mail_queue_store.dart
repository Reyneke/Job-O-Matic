import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import 'mail_queue_service.dart';

/// Persistenz-Schnittstelle für die Mail-Queue.
///
/// Ermöglicht In-Memory-Tests (ohne Store) sowie SQLite-Persistenz,
///damit offene `pending`/`queued`-Einträge einen App-Neustart überleben.

abstract class MailQueueStore {
  Future<void> insert(MailQueueEntry entry);
  Future<void> update(MailQueueEntry entry);
  Future<List<MailQueueEntry>> loadAll();
  Future<void> updateStatus(
    String id,
    MailStatus status, {
    int? retryCount,
    DateTime? lastTryAt,
    DateTime? nextTryAt,
    String? errorMessage,
  });
  Future<List<MailQueueEntry>> loadPending();
  Future<int> countByStatus(
    MailStatus status, {
    int? limit,
    int? offset,
    String orderBy = 'created_at ASC',
  });
  Future<void> deleteAllCompleted();
}

/// SQLite-Implementierung über die bestehende `mail_queue`-Tabelle
/// (Migration v2 bzw. v7, siehe DatabaseHelper._onUpgrade).
class SqliteMailQueueStore implements MailQueueStore {
  final Logger _log = Logger('SqliteMailQueueStore');
  final DatabaseHelper _dbHelper;

  SqliteMailQueueStore({DatabaseHelper? dbHelper})
    : _dbHelper = dbHelper ?? DatabaseHelper();

  @override
  Future<void> insert(MailQueueEntry entry) async {
    final db = await _dbHelper.database;
    await db.insert('mail_queue', _toRow(entry));
    _log.fine('Mail-Queue persistiert: ${entry.id} → ${entry.to}');
  }

  @override
  Future<void> update(MailQueueEntry entry) async {
    final db = await _dbHelper.database;
    await db.update(
      'mail_queue',
      _toRow(entry),
      where: 'uuid = ?',
      whereArgs: [entry.id],
    );
  }

  @override
  Future<List<MailQueueEntry>> loadAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('mail_queue', orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> updateStatus(
    String id,
    MailStatus status, {
    int? retryCount,
    DateTime? lastTryAt,
    DateTime? nextTryAt,
    String? errorMessage,
  }) async {
    final db = await _dbHelper.database;
    final values = <String, dynamic>{
      'status': status.name,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastTryAt != null) 'last_try_at': lastTryAt.toIso8601String(),
      if (nextTryAt != null) 'next_try_at': nextTryAt.toIso8601String(),
      if (errorMessage != null) 'error_message': errorMessage,
    };
    await db.update('mail_queue', values, where: 'uuid = ?', whereArgs: [id]);
    _log.fine('Queue-Status aktualisiert: $id → ${status.name}');
  }

  @override
  Future<List<MailQueueEntry>> loadPending() async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'mail_queue',
      // „Offen“ = pending/queued oder failed, dessen Retry-Zeitpunkt
      // erreicht/überschritten ist (failed mit zukünftigem Retry wird NICHT
      // als sendbereit angeboten).
      where:
          "status IN ('pending', 'queued') OR "
          "(status = 'failed' AND (next_try_at IS NULL OR next_try_at <= ?))",
      whereArgs: [now],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> countByStatus(
    MailStatus status, {
    int? limit,
    int? offset,
    String orderBy = 'created_at ASC',
  }) async {
    final db = await _dbHelper.database;
    final conditions = <String>[];
    final args = <dynamic>[];
    if (status == MailStatus.pending) {
      conditions.add("status IN ('pending', 'queued')");
    } else {
      conditions.add('status = ?');
      args.add(status.name);
    }
    final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;
    final count = Sqflite.firstIntValue(
      await db.query(
        'mail_queue',
        columns: ['COUNT(*)'],
        where: whereClause,
        whereArgs: args.isNotEmpty ? args : null,
      ),
    );
    return count ?? 0;
  }

  @override
  Future<void> deleteAllCompleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'mail_queue',
      where: "status IN ('sent', 'failed', 'bounced')",
    );
    _log.info('Abgeschlossene Queue-Einträge bereinigt');
  }

  Map<String, dynamic> _toRow(MailQueueEntry e) => {
    'uuid': e.id,
    'recipient_email': e.to,
    'subject': e.subject,
    'body': e.body,
    'pdf_path': e.pdfPath,
    'application_id': e.applicationId != null
        ? int.tryParse(e.applicationId!)
        : null,
    'sender_name': e.senderName,
    'sender_email': e.senderEmail,
    'cc': jsonEncode(e.cc),
    'bcc': jsonEncode(e.bcc),
    'status': e.status.name,
    'retry_count': e.retryCount,
    'last_try_at': e.lastTryAt?.toIso8601String(),
    'next_try_at': e.nextTryAt?.toIso8601String(),
    'error_message': e.errorMessage,
    'created_at': e.createdAt.toIso8601String(),
  };

  List<String> _jsonStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  MailQueueEntry _fromRow(Map<String, dynamic> row) {
    final status = MailStatus.values.firstWhere(
      (s) => s.name == row['status'],
      orElse: () => MailStatus.pending,
    );
    return MailQueueEntry(
      id: row['uuid'] as String,
      to: row['recipient_email'] as String,
      subject: row['subject'] as String,
      body: row['body'] as String,
      pdfPath: row['pdf_path'] as String?,
      applicationId: row['application_id']?.toString(),
      senderName: row['sender_name'] as String?,
      senderEmail: row['sender_email'] as String?,
      cc: _jsonStringList(row['cc'] as String?),
      bcc: _jsonStringList(row['bcc'] as String?),
      status: status,
      retryCount: (row['retry_count'] as int?) ?? 0,
      lastTryAt: _tryParseDate(row['last_try_at'] as String?),
      nextTryAt: _tryParseDate(row['next_try_at'] as String?),
      errorMessage: row['error_message'] as String?,
      createdAt: _tryParseDate(row['created_at'] as String?) ?? DateTime.now(),
    );
  }

  DateTime? _tryParseDate(String? raw) =>
      raw != null ? DateTime.tryParse(raw) : null;
}
