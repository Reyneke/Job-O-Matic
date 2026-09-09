import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/database/database_helper.dart';
import 'package:job_o_matic/data/repositories/database_repository.dart';
import 'package:job_o_matic/models/application.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase B - Persistenter Tageslimit-Zaehler (300/Tag Free-Tier) + emailStatus-
/// Roundtrip an der `applications`-Tabelle. In-Memory-SQLite mit echter
/// Schema-Definition (Version 7).
void main() {
  late DatabaseHelper dbHelper;
  late DatabaseRepository repo;

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
    repo = DatabaseRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
  });

  group('Persistenter Tageslimit-Zaehler', () {
    test('startet bei 0', () async {
      expect(await repo.getMailCountForToday(), 0);
    });

    test('incrementMailCountForToday erhoeht den Zaehler', () async {
      expect(await repo.incrementMailCountForToday(), 1);
      expect(await repo.incrementMailCountForToday(), 2);
      expect(await repo.getMailCountForToday(), 2);
    });

    test('Zaehler ueberlebt eine neue Repo-Instanz (DB-Persistenz)', () async {
      await repo.incrementMailCountForToday();
      await repo.incrementMailCountForToday();

      final freshRepo = DatabaseRepository(dbHelper: dbHelper);
      expect(await freshRepo.getMailCountForToday(), 2);
    });
  });

  group('Application.emailStatus (Phase B)', () {
    test('emailStatus wird ueber insert/load gerundtrippt', () async {
      final id = await repo.insertApplication(
        Application(
          id: 0,
          jobTitle: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          jobUrl: 'https://example.com/job/1',
          createdAt: DateTime.now(),
          emailStatus: EmailStatus.queued,
          emailAddress: 'hr@firma.de',
        ),
      );

      final loaded = await repo.loadApplication(id);
      expect(loaded, isNotNull);
      expect(loaded!.emailStatus, EmailStatus.queued);
      expect(loaded.emailAddress, 'hr@firma.de');
    });

    test('updateEmailStatus persistiert den neuen Zustand', () async {
      final id = await repo.insertApplication(
        Application(
          id: 0,
          jobTitle: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          jobUrl: 'https://example.com/job/1',
          createdAt: DateTime.now(),
        ),
      );

      await repo.updateEmailStatus(id, EmailStatus.sent);

      final loaded = await repo.loadApplication(id);
      expect(loaded!.emailStatus, EmailStatus.sent);
    });

    test('unbekannter email_status faellt auf initial zurueck', () async {
      final id = await repo.insertApplication(
        Application(
          id: 0,
          jobTitle: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          jobUrl: 'https://example.com/job/1',
          createdAt: DateTime.now(),
        ),
      );

      // Spalte direkt manipulieren (aeltester Zustand / Migration ohne Wert)
      final db = await dbHelper.database;
      await db.update(
        'applications',
        {'email_status': 'sending'},
        where: 'id = ?',
        whereArgs: [id],
      );

      final loaded = await repo.loadApplication(id);
      expect(loaded!.emailStatus, EmailStatus.sending);
    });
  });

  group('Application Kontakt-Metadaten (v8)', () {
    test('emailSource/evidenceUrl/contactPerson werden gerundetrippt', () async {
      final id = await repo.insertApplication(
        Application(
          id: 0,
          jobTitle: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          jobUrl: 'https://example.com/job/1',
          createdAt: DateTime.now(),
          emailAddress: 'hr@firma.de',
          emailSource: 'employerWebsite',
          emailEvidenceUrl: 'https://firma.de/impressum',
          contactPerson: 'Frau Muster',
        ),
      );

      final loaded = await repo.loadApplication(id);
      expect(loaded, isNotNull);
      expect(loaded!.emailAddress, 'hr@firma.de');
      expect(loaded.emailSource, 'employerWebsite');
      expect(loaded.emailEvidenceUrl, 'https://firma.de/impressum');
      expect(loaded.contactPerson, 'Frau Muster');
    });

    test('updateContactInfo schreibt nur uebergebene Felder', () async {
      final id = await repo.insertApplication(
        Application(
          id: 0,
          jobTitle: 'Flutter-Entwickler',
          company: 'Firma GmbH',
          jobUrl: 'https://example.com/job/1',
          createdAt: DateTime.now(),
        ),
      );

      await repo.updateContactInfo(
        id,
        emailAddress: 'hr@firma.de',
        emailSource: 'mailtoLink',
        emailEvidenceUrl: 'https://example.com/job/1',
        contactPerson: 'Herr Beispiel',
      );
      var loaded = await repo.loadApplication(id);
      expect(loaded!.emailAddress, 'hr@firma.de');
      expect(loaded.emailSource, 'mailtoLink');
      expect(loaded.emailEvidenceUrl, 'https://example.com/job/1');
      expect(loaded.contactPerson, 'Herr Beispiel');

      // Nur ein Feld setzen – die übrigen bleiben unverändert.
      await repo.updateContactInfo(id, emailSource: 'manual');
      loaded = await repo.loadApplication(id);
      expect(loaded!.emailAddress, 'hr@firma.de');
      expect(loaded.emailSource, 'manual');
      expect(loaded.emailEvidenceUrl, 'https://example.com/job/1');
      expect(loaded.contactPerson, 'Herr Beispiel');
    });
  });
}
