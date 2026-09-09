import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/database/database_helper.dart';
import 'package:job_o_matic/data/services/email/mail_queue_service.dart';
import 'package:job_o_matic/data/services/email/mail_queue_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase B - Persistenz der Mail-Queue: Eintraege ueberleben den App-Neustart
/// (Insert/Update/Status), offene `pending`/`queued` werden wieder geladen,
/// Status-Zaehler fuer die UI. Laeuft gegen In-Memory-SQLite mit der echten
/// Schema-Definition (DatabaseHelper.createSchemaForTesting).
void main() {
  late DatabaseHelper dbHelper;
  late SqliteMailQueueStore store;

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
    store = SqliteMailQueueStore(dbHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
  });

  MailQueueEntry entry({
    String id = 'e1',
    MailStatus status = MailStatus.pending,
    int retryCount = 0,
    DateTime? nextTryAt,
  }) => MailQueueEntry(
    id: id,
    to: 'hr@firma.de',
    subject: 'Bewerbung Flutter-Entwickler',
    body: 'Sehr geehrte Damen und Herren,',
    applicationId: '42',
    senderName: 'Max Mustermann',
    senderEmail: 'kleitmiandefoot@gmail.com',
    cc: ['cc@firma.de'],
    bcc: ['bcc@firma.de'],
    status: status,
    retryCount: retryCount,
    nextTryAt: nextTryAt,
    createdAt: DateTime.utc(2026, 1, 1),
  );

  group('SqliteMailQueueStore', () {
    test('insert + loadAll Roundtrip erhaelt alle Felder', () async {
      await store.insert(entry());

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      final e = loaded.single;
      expect(e.id, 'e1');
      expect(e.to, 'hr@firma.de');
      expect(e.applicationId, '42');
      expect(e.senderName, 'Max Mustermann');
      expect(e.senderEmail, 'kleitmiandefoot@gmail.com');
      expect(e.cc, ['cc@firma.de']);
      expect(e.bcc, ['bcc@firma.de']);
      expect(e.status, MailStatus.pending);
      expect(e.retryCount, 0);
    });

    test('updateStatus persistiert Status + Fehler + nextTryAt', () async {
      await store.insert(entry());
      await store.updateStatus(
        'e1',
        MailStatus.failed,
        retryCount: 2,
        nextTryAt: DateTime.utc(2026, 1, 2),
        errorMessage: 'Brevo 429',
      );

      final loaded = await store.loadAll();
      final e = loaded.single;
      expect(e.status, MailStatus.failed);
      expect(e.retryCount, 2);
      expect(e.errorMessage, 'Brevo 429');
      expect(e.nextTryAt, DateTime.utc(2026, 1, 2));
    });

    test('loadPending laedt pending/queued und abgelaufene failed', () async {
      await store.insert(entry(id: 'a', status: MailStatus.pending));
      await store.insert(entry(id: 'b', status: MailStatus.queued));
      await store.insert(
        entry(
          id: 'c',
          status: MailStatus.failed,
          nextTryAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      await store.insert(
        entry(
          id: 'd',
          status: MailStatus.failed,
          nextTryAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
      );
      await store.insert(entry(id: 'e', status: MailStatus.sent));

      final pending = await store.loadPending();
      final ids = pending.map((e) => e.id).toSet();
      expect(ids, contains('a'));
      expect(ids, contains('b'));
      // failed mit zukuenftigem Retry wird NICHT als pending angeboten
      expect(ids, isNot(contains('d')));
      // sent gehoert nicht zu den offenen Eintraegen
      expect(ids, isNot(contains('e')));
    });

    test('countByStatus zaehlt offene bzw. gesendete Eintraege', () async {
      await store.insert(entry(id: 'a', status: MailStatus.pending));
      await store.insert(entry(id: 'b', status: MailStatus.queued));
      await store.insert(entry(id: 'c', status: MailStatus.sent));
      await store.insert(entry(id: 'd', status: MailStatus.sent));

      expect(await store.countByStatus(MailStatus.pending), 2);
      expect(await store.countByStatus(MailStatus.sent), 2);
      expect(await store.countByStatus(MailStatus.failed), 0);
    });

    test('deleteAllCompleted raeumt sent/failed/bounced auf', () async {
      await store.insert(entry(id: 'a', status: MailStatus.pending));
      await store.insert(entry(id: 'b', status: MailStatus.sent));
      await store.insert(entry(id: 'c', status: MailStatus.failed));

      await store.deleteAllCompleted();

      final ids = (await store.loadAll()).map((e) => e.id).toSet();
      expect(ids, contains('a'));
      expect(ids, isNot(contains('b')));
      expect(ids, isNot(contains('c')));
    });
  });
}
