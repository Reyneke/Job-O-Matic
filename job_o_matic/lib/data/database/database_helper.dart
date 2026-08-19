import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
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

  /// Singleton-Instanz
  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
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
    final dbPath = await getDatabasesPath();
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
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'job_o_matic.db');

    _log.info('Öffne Datenbank: $path');

    return openDatabase(
      path,
      version: 4,
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
        completed_at     TEXT
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
      batch.insert('search_filters', {
        'key': entry.key,
        'value': entry.value,
      });
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
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'job_o_matic.db');
    await deleteDatabase(path);
    _log.info('Datenbank zurückgesetzt');
  }
}