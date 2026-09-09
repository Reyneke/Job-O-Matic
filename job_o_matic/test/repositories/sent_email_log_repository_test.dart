import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/database/database_helper.dart';
import 'package:job_o_matic/data/repositories/database_repository.dart';
import 'package:job_o_matic/data/repositories/sent_email_log_repository.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:job_o_matic/models/sent_email_log_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase B - Audit-Log (`sent_email_log`): insert, "Zuletzt gesendet am",
/// History-Pruefung und Retention (DSGVO). Laeuft gegen In-Memory-SQLite mit
/// der echten Schema-Definition (DatabaseHelper.createSchemaForTesting).
void main() {
  late DatabaseHelper dbHelper;
  late SentEmailLogRepository repo;
  late DatabaseRepository dbRepo;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    dbHelper = DatabaseHelper();
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.schemaVersion,
        onCreate: (db, version) => dbHelper.createSchemaForTesting(db),
      ),
    );
    dbHelper.overrideDatabaseForTesting(db);

    repo = SentEmailLogRepository(dbHelper: dbHelper);
    dbRepo = DatabaseRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
  });

  Future<int> insertTestApplication() async {
    final app = Application(
      id: 0,
      jobTitle: 'Flutter-Entwickler',
      company: 'Firma GmbH',
      jobUrl: 'https://example.com/job/1',
      createdAt: DateTime.now(),
    );
    return dbRepo.insertApplication(app);
  }

  group('SentEmailLogRepository', () {
    test('insert legt Eintrag mit UTC-Zeitstempel an', () async {
      final appId = await insertTestApplication();
      final id = await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Bewerbung Flutter-Entwickler',
          messageId: 'brevo-msg-1',
          status: SentEmailLogStatus.sent,
          sentAt: DateTime.now(),
        ),
      );
      expect(id, greaterThan(0));

      final latest = await repo.latestSentAt(appId);
      expect(latest, isNotNull);
      expect(latest!.isUtc, isTrue);
    });

    test('latestSentAt liefert den juengsten Versuch (MAX sent_at)', () async {
      final appId = await insertTestApplication();
      final early = DateTime.utc(2026, 1, 1);
      final late = DateTime.utc(2026, 6, 1);

      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Erster Versuch',
          status: SentEmailLogStatus.failed,
          sentAt: early,
        ),
      );
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Zweiter Versuch',
          status: SentEmailLogStatus.sent,
          sentAt: late,
        ),
      );

      final latest = await repo.latestSentAt(appId);
      expect(latest, isNotNull);
      expect(latest!.toUtc(), late);
    });

    test(
      'hasSent ist nur true, wenn ein erfolgreicher Versand existiert',
      () async {
        final appId = await insertTestApplication();
        expect(await repo.hasSent(appId), isFalse);

        await repo.insert(
          SentEmailLogEntry(
            applicationId: appId,
            recipientEmail: 'hr@firma.de',
            subject: 'Fehlgeschlagen',
            status: SentEmailLogStatus.failed,
            sentAt: DateTime.now(),
          ),
        );
        expect(await repo.hasSent(appId), isFalse);

        await repo.insert(
          SentEmailLogEntry(
            applicationId: appId,
            recipientEmail: 'hr@firma.de',
            subject: 'Erfolgreich',
            status: SentEmailLogStatus.sent,
            sentAt: DateTime.now(),
          ),
        );
        expect(await repo.hasSent(appId), isTrue);
      },
    );

    test('deleteOlderThan entfernt nur Eintraege vor dem Cutoff', () async {
      final appId = await insertTestApplication();
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Alt',
          status: SentEmailLogStatus.sent,
          sentAt: DateTime.utc(2025, 6, 1),
        ),
      );
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Neu',
          status: SentEmailLogStatus.sent,
          sentAt: DateTime.now(),
        ),
      );

      final cutoff = DateTime.now().subtract(const Duration(days: 180));
      final deleted = await repo.deleteOlderThan(cutoff);
      expect(deleted, 1);
      expect(await repo.hasSent(appId), isTrue);
    });

    test('deleteByApplication entfernt alle Logs einer Bewerbung', () async {
      final appId = await insertTestApplication();
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Versuch 1',
          status: SentEmailLogStatus.failed,
          sentAt: DateTime.now(),
        ),
      );
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId,
          recipientEmail: 'hr@firma.de',
          subject: 'Versuch 2',
          status: SentEmailLogStatus.sent,
          sentAt: DateTime.now(),
        ),
      );

      final deleted = await repo.deleteByApplication(appId);
      expect(deleted, 2);
      expect(await repo.hasSent(appId), isFalse);
      expect(await repo.latestSentAt(appId), isNull);
    });

    test('deleteAll leert das gesamte Log', () async {
      final appId1 = await insertTestApplication();
      final appId2 = await insertTestApplication();
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId1,
          recipientEmail: 'hr@firma.de',
          subject: 'A',
          status: SentEmailLogStatus.sent,
          sentAt: DateTime.now(),
        ),
      );
      await repo.insert(
        SentEmailLogEntry(
          applicationId: appId2,
          recipientEmail: 'hr2@firma.de',
          subject: 'B',
          status: SentEmailLogStatus.draftExported,
          sentAt: DateTime.now(),
        ),
      );

      final deleted = await repo.deleteAll();
      expect(deleted, 2);
      expect(await repo.hasSent(appId1), isFalse);
      expect(await repo.hasSent(appId2), isFalse);
    });
  });
}
