import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migrationstest v6 -> v7 (doc/plan/14-Email.md Phase B/F):
/// - bestehende Daten (applications, mail_queue) bleiben erhalten,
/// - neue Spalten (email_status/email_address, sender/cc/bcc) kommen dazu,
/// - `sent_email_log` wird angelegt,
/// - Fremdschluessel: ohne CASCADE verhindert ein Log-Eintrag das Loeschen
///   der Application (bewusste Entscheidung „Audit-Log erhalten“).
void main() {
  late Directory tmpDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('job_o_matic_migration');
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  /// Legt eine Datenbank im (vereinfachten) v6-Zustand an.
  Future<Database> openV6(String path) {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE applications (
              id               INTEGER PRIMARY KEY AUTOINCREMENT,
              job_title        TEXT    NOT NULL DEFAULT 'Unbekannte Stelle',
              company          TEXT    NOT NULL DEFAULT 'Unbekanntes Unternehmen',
              company_address  TEXT,
              job_url          TEXT    NOT NULL,
              job_description  TEXT,
              status           TEXT    NOT NULL DEFAULT 'queued',
              pdf_path         TEXT,
              error_message    TEXT,
              created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
              completed_at     TEXT,
              cover_letter_text TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE mail_queue (
              id              INTEGER PRIMARY KEY AUTOINCREMENT,
              uuid            TEXT    NOT NULL UNIQUE,
              recipient_email TEXT    NOT NULL,
              subject         TEXT    NOT NULL,
              body            TEXT    NOT NULL,
              pdf_path        TEXT,
              application_id  INTEGER,
              status          TEXT    NOT NULL DEFAULT 'pending',
              retry_count     INTEGER NOT NULL DEFAULT 0,
              last_try_at     TEXT,
              next_try_at     TEXT,
              error_message   TEXT,
              created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
            )
          ''');
        },
      ),
    );
  }

  test(
    'v6 -> v7 erhaelt Daten und ergaenzt Spalten + sent_email_log',
    () async {
      final dbHelper = DatabaseHelper();
      final path = '${tmpDir.path}/job_o_matic.db';

      // v6-Daten anlegen
      final db6 = await openV6(path);
      final appId = await db6.insert('applications', {
        'job_title': 'Flutter-Entwickler',
        'company': 'Firma GmbH',
        'job_url': 'https://example.com/job/1',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db6.insert('mail_queue', {
        'uuid': 'entry-1',
        'recipient_email': 'hr@firma.de',
        'subject': 'Bewerbung',
        'body': 'Text',
        'application_id': appId,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db6.close();

      // Auf v7 migrieren (echte Migrationslogik von DatabaseHelper)
      final db7 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onUpgrade: (db, oldVersion, newVersion) =>
              dbHelper.runMigrationForTesting(db, oldVersion, newVersion),
        ),
      );

      // Bestehende Daten erhalten
      final apps = await db7.query('applications');
      expect(apps, hasLength(1));
      expect(apps.single['job_title'], 'Flutter-Entwickler');
      final queueRows = await db7.query('mail_queue');
      expect(queueRows, hasLength(1));
      expect(queueRows.single['uuid'], 'entry-1');

      // Neue Spalten vorhanden
      final appCols = (await db7.rawQuery(
        'PRAGMA table_info(applications)',
      )).map((r) => r['name']).toSet();
      expect(appCols, contains('email_status'));
      expect(appCols, contains('email_address'));
      final queueCols = (await db7.rawQuery(
        'PRAGMA table_info(mail_queue)',
      )).map((r) => r['name']).toSet();
      expect(queueCols, contains('sender_name'));
      expect(queueCols, contains('sender_email'));
      expect(queueCols, contains('cc'));
      expect(queueCols, contains('bcc'));

      // sent_email_log existiert und akzeptiert Eintraege
      final logId = await db7.insert('sent_email_log', {
        'application_id': appId,
        'recipient_email': 'hr@firma.de',
        'subject': 'Bewerbung',
        'status': 'sent',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      });
      expect(logId, greaterThan(0));

      await db7.close();
    },
  );

  test(
    'Fremdschluessel: Log-Eintrag blockiert Loeschen (kein CASCADE)',
    () async {
      final dbHelper = DatabaseHelper();
      final path = '${tmpDir.path}/job_o_matic.db';

      final db6 = await openV6(path);
      final appId = await db6.insert('applications', {
        'job_title': 'Job',
        'company': 'Firma',
        'job_url': 'https://example.com/job/2',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db6.close();

      final db7 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onUpgrade: (db, oldVersion, newVersion) =>
              dbHelper.runMigrationForTesting(db, oldVersion, newVersion),
        ),
      );
      await db7.execute('PRAGMA foreign_keys=ON');
      await db7.insert('sent_email_log', {
        'application_id': appId,
        'recipient_email': 'hr@firma.de',
        'subject': 'Bewerbung',
        'status': 'sent',
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Bewerbung mit Historie darf NICHT geloescht werden (FK NO ACTION).
      expect(
        () => db7.delete('applications', where: 'id = ?', whereArgs: [appId]),
        throwsA(isA<DatabaseException>()),
      );

      // Erst Logs entfernen (deleteByApplication), dann gelingt das Loeschen.
      await db7.delete(
        'sent_email_log',
        where: 'application_id = ?',
        whereArgs: [appId],
      );
      final deleted = await db7.delete(
        'applications',
        where: 'id = ?',
        whereArgs: [appId],
      );
      expect(deleted, 1);
      await db7.close();
    },
  );
}
