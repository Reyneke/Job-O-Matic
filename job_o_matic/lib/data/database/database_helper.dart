import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';

/// Singleton zur Verwaltung der SQLite-Datenbank.
///
/// Features:
/// - Lazy-Initialisierung (DB wird erst bei Bedarf geöffnet)
/// - Schema-Migration über Versionierung
/// - Zentrale Logging aller Datenbank-Operationen
class DatabaseHelper {
  static final Logger _log = Logger('DatabaseHelper');
  static DatabaseHelper? _instance;
  static Database? _database;

  DatabaseHelper._internal();

  /// Cache für den aufgelösten DB-Pfad (muss nur einmal ermittelt werden).
  static String? _databasesPath;

  /// Singleton-Instanz
  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  /// Löst den dauerhaften Speicherort der Datenbank auf.
  ///
  /// Die DB liegt unter `<ApplicationSupportDirectory>/databases/`
  /// (unter Windows: `%APPDATA%\<org>\<app>\databases\`) und **nicht** im
  /// sqflite-ffi-Standard (`.dart_tool/sqflite_common_ffi/databases/`),
  /// da `.dart_tool` ein Cache-Ordner ist und z. B. von `flutter clean`
  /// komplett gelöscht wird – mit allen enthaltenen Daten.
  ///
  /// Migration: Existiert noch eine alte DB im Legacy-Pfad und noch keine
  /// am neuen Ort, wird sie einmalig dorthin kopiert.
  Future<String> _resolveDatabasesPath() async {
    final cached = _databasesPath;
    if (cached != null) return cached;

    final appDir = await getApplicationSupportDirectory();
    final dbDir = p.join(appDir.path, 'databases');
    await Directory(dbDir).create(recursive: true);

    // Einmalige Migration vom Legacy-Pfad (.dart_tool), falls vorhanden.
    final legacyPath = p.join(await getDatabasesPath(), 'job_o_matic.db');
    final newPath = p.join(dbDir, 'job_o_matic.db');
    final legacyFile = File(legacyPath);
    final newFile = File(newPath);
    if (await legacyFile.exists() && !await newFile.exists()) {
      await legacyFile.copy(newPath);
      // WAL/SHM mitnehmen, falls vorhanden (unbeschriebene Transaktionen).
      for (final suffix in ['-wal', '-shm']) {
        final side = File('$legacyPath$suffix');
        if (await side.exists()) {
          await side.copy('$newPath$suffix');
        }
      }
      _log.info('Datenbank vom Legacy-Pfad migriert: $legacyPath -> $newPath');
    }

    _databasesPath = dbDir;
    return dbDir;
  }

  /// Öffnet (oder erstellt) die Datenbank. Idempotent.
  /// Löscht die alte DB bei Schema-Änderungen (Entwicklung).
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Löscht die bestehende Datenbank (für Entwicklung/Reset).
  Future<void> deleteDatabaseFile() async {
    await close();
    final dbPath = await _resolveDatabasesPath();
    final path = p.join(dbPath, 'job_o_matic.db');
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      _log.info('Datenbank-Datei gelöscht: $path');
    }
  }

  /// Erzwingt einen kompletten Reset (DB löschen + neu erstellen).
  Future<void> forceReset() async {
    await deleteDatabaseFile();
    _database = null;
    _log.info('DB-Reset abgeschlossen');
  }

  Future<Database> _initDatabase() async {
    final dbPath = await _resolveDatabasesPath();
    final path = p.join(dbPath, 'job_o_matic.db');

    _log.info('Öffne Datenbank: $path');

    return openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// Wird beim ersten Erstellen der DB aufgerufen.
  Future<void> _onCreate(Database db, int version) async {
    _log.info('Erstelle Datenbank-Schema (Version $version)');

    await db.execute('''
      CREATE TABLE applications (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        job_title        TEXT    NOT NULL DEFAULT 'Unbekannte Stelle',
        company          TEXT    NOT NULL DEFAULT 'Unbekanntes Unternehmen',
        company_address  TEXT,
        job_url          TEXT    NOT NULL,
        job_description  TEXT,
        status           TEXT    NOT NULL DEFAULT 'queued'
                        CHECK(status IN ('queued','processing','completed','failed','exported')),
        pdf_path         TEXT,
        error_message    TEXT,
        created_at       TEXT    NOT NULL DEFAULT (datetime('now')),
        completed_at     TEXT,
        cover_letter_text TEXT,
        email_status     TEXT    NOT NULL DEFAULT 'new'
                          CHECK(email_status IN ('new','queued','sending','sent','failed')),
        email_address    TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_applications_status ON applications(status)
    ''');

    await db.execute('''
      CREATE INDEX idx_applications_job_url ON applications(job_url, created_at)
    ''');

    await db.execute('''
      CREATE TABLE validated_urls (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        url         TEXT    NOT NULL UNIQUE,
        created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE search_filters (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        key   TEXT    NOT NULL UNIQUE,
        value TEXT    NOT NULL
      )
    ''');

    // Standard-Suchfilter initial einfügen
    await _insertDefaultFilters(db);

    await db.execute('''
      CREATE TABLE cv_data (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        personal_data_json  TEXT    NOT NULL,
        work_experience_json TEXT   NOT NULL DEFAULT '[]',
        education_json      TEXT    NOT NULL DEFAULT '[]',
        certificates_json   TEXT    NOT NULL DEFAULT '[]',
        skills_json         TEXT    NOT NULL DEFAULT '[]',
        loaded_at           TEXT    NOT NULL DEFAULT (datetime('now'))
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
        sender_name     TEXT,
        sender_email    TEXT,
        cc              TEXT,
        bcc             TEXT,
        status          TEXT    NOT NULL DEFAULT 'pending'
                        CHECK(status IN ('pending','queued','sending','sent','failed','bounced')),
        retry_count     INTEGER NOT NULL DEFAULT 0,
        last_try_at     TEXT,
        next_try_at     TEXT,
        error_message   TEXT,
        created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_mail_queue_status ON mail_queue(status)
    ''');

    await db.execute('''
      CREATE INDEX idx_mail_queue_next_try ON mail_queue(next_try_at)
    ''');

    await db.execute('''
      CREATE TABLE sent_email_log (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        application_id   INTEGER NOT NULL REFERENCES applications(id),
        recipient_email  TEXT    NOT NULL,
        subject          TEXT    NOT NULL,
        message_id       TEXT,
        status           TEXT    NOT NULL
                         CHECK(status IN ('sent','failed','bounced','draft_exported')),
        error_message    TEXT,
        sent_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sent_email_log_application_sent
        ON sent_email_log(application_id, sent_at)
    ''');

    _log.info('Datenbank-Schema erfolgreich erstellt');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _log.info('Migriere Datenbank: $oldVersion → $newVersion');
    if (oldVersion < 2) {
      _log.info('Migration auf Version 2: mail_queue-Tabelle hinzufügen');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS mail_queue (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid            TEXT    NOT NULL UNIQUE,
          recipient_email TEXT    NOT NULL,
          subject         TEXT    NOT NULL,
          body            TEXT    NOT NULL,
          pdf_path        TEXT,
          application_id  INTEGER,
          status          TEXT    NOT NULL DEFAULT 'pending'
                          CHECK(status IN ('pending','queued','sending','sent','failed','bounced')),
          retry_count     INTEGER NOT NULL DEFAULT 0,
          last_try_at     TEXT,
          next_try_at     TEXT,
          error_message   TEXT,
          created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_mail_queue_status ON mail_queue(status)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_mail_queue_next_try ON mail_queue(next_try_at)
      ''');
    }
    if (oldVersion < 3) {
      _log.info('Migration auf Version 3: job_description-Spalte hinzufügen');
      await db.execute('''
        ALTER TABLE applications ADD COLUMN job_description TEXT
      ''');
    }
    if (oldVersion < 4) {
      _log.info('Migration auf Version 4: company_address-Spalte hinzufügen');
      await db.execute('''
        ALTER TABLE applications ADD COLUMN company_address TEXT
      ''');
    }
    if (oldVersion < 5) {
      _log.info('Migration auf Version 5: certificates_json-Spalte hinzufügen');
      await db.execute('''
        ALTER TABLE cv_data ADD COLUMN certificates_json TEXT NOT NULL DEFAULT '[]'
      ''');
    }
    if (oldVersion < 6) {
      _log.info('Migration auf Version 6: cover_letter_text-Spalte hinzufügen');
      await db.execute('''
        ALTER TABLE applications ADD COLUMN cover_letter_text TEXT
      ''');
    }
    if (oldVersion < 7) {
      _log.info(
        'Migration auf Version 7: email-Status/Persistenz (email_status, '
        'email_address, sent_email_log, mail_queue-Erweiterung)',
      );
      await db.execute('''
        ALTER TABLE applications ADD COLUMN email_status TEXT NOT NULL DEFAULT 'new'
          CHECK(email_status IN ('new','queued','sending','sent','failed'))
      ''');
      await db.execute('''
        ALTER TABLE applications ADD COLUMN email_address TEXT
      ''');
      await db.execute('''
        ALTER TABLE mail_queue ADD COLUMN sender_name TEXT
      ''');
      await db.execute('''
        ALTER TABLE mail_queue ADD COLUMN sender_email TEXT
      ''');
      await db.execute('''
        ALTER TABLE mail_queue ADD COLUMN cc TEXT
      ''');
      await db.execute('''
        ALTER TABLE mail_queue ADD COLUMN bcc TEXT
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sent_email_log (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          application_id   INTEGER NOT NULL REFERENCES applications(id),
          recipient_email  TEXT    NOT NULL,
          subject          TEXT    NOT NULL,
          message_id       TEXT,
          status           TEXT    NOT NULL
                           CHECK(status IN ('sent','failed','bounced','draft_exported')),
          error_message    TEXT,
          sent_at          TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sent_email_log_application_sent
          ON sent_email_log(application_id, sent_at)
      ''');
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA foreign_keys=ON');
  }

  Future<void> _insertDefaultFilters(Database db) async {
    final defaults = {
      'last_query': '{"text":"","location":"","radius":25}',
      'employment_type': 'both',
      'work_model': 'any',
      'target_companies': '[]',
      'salary_min': '',
      'salary_currency': 'EUR',
      'jobcenter_plz': '',
      'favorite_companies': '[]',
    };

    final batch = db.batch();
    for (final entry in defaults.entries) {
      batch.insert('search_filters', {'key': entry.key, 'value': entry.value});
    }
    await batch.commit(noResult: true);
  }

  /// Schließt die Datenbank (z. B. beim App-Beenden).
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
      _log.info('Datenbank geschlossen');
    }
  }

  /// Setzt die Datenbank zurück (für Tests).
  Future<void> reset() async {
    await close();
    final dbPath = await _resolveDatabasesPath();
    final path = p.join(dbPath, 'job_o_matic.db');
    await deleteDatabase(path);
    _log.info('Datenbank zurückgesetzt');
  }

  /// Test-Seam: ersetzt die interne DB durch eine fremde Instanz
  /// (z. B. In-Memory-SQLite via `sqflite_common_ffi` in Unit-Tests).
  @visibleForTesting
  void overrideDatabaseForTesting(Database db) {
    _database = db;
    _log.info('Datenbank für Tests überschrieben');
  }

  /// Test-Seam: legt das aktuelle Schema auf einer fremden DB-Instanz an
  /// (für In-Memory-SQLite in Unit-Tests, damit Repository-Tests gegen die
  /// echte Schema-Definition laufen statt einer Test-Kopie).
  @visibleForTesting
  Future<void> createSchemaForTesting(Database db) => _onCreate(db, 7);
}
