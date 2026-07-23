import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'package:logging/logging.dart';
import '../database/database_helper.dart';
import '../../models/application.dart';
import '../../models/cv_data.dart';

/// Repository für direkte Datenbank-Zugriffe.
///
/// Kapselt alle SQL-Operationen und stellt typsichere Methoden
/// für die Geschäftslogik bereit.
class DatabaseRepository {
  final Logger _log = Logger('DatabaseRepository');
  final DatabaseHelper _dbHelper;

  DatabaseRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  // ---------------------------------------------------------------------------
  // APPLICATIONS
  // ---------------------------------------------------------------------------

  /// Alle Bewerbungen laden (sortiert nach created_at DESC).
  Future<List<Application>> loadApplications() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'applications',
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToApplication).toList();
  }

  /// Einzelne Bewerbung per ID laden.
  Future<Application?> loadApplication(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'applications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToApplication(rows.first);
  }

  /// Neue Bewerbung einfügen.
  Future<int> insertApplication(Application app) async {
    final db = await _dbHelper.database;
    final id = await db.insert('applications', _applicationToRow(app));
    _log.info('Application eingefügt: ID=$id, ${app.jobTitle}');
    return id;
  }

  /// Bewerbung aktualisieren.
  Future<void> updateApplication(Application app) async {
    final db = await _dbHelper.database;
    await db.update(
      'applications',
      _applicationToRowForUpdate(app),
      where: 'id = ?',
      whereArgs: [app.id],
    );
    _log.fine('Application ${app.id} aktualisiert: Status=${app.status.name}');
  }

  /// Bewerbung löschen.
  Future<void> deleteApplication(int id) async {
    final db = await _dbHelper.database;
    await db.delete('applications', where: 'id = ?', whereArgs: [id]);
    _log.info('Application $id gelöscht');
  }

  /// Prüfen, ob eine URL bereits in den letzten 90 Tagen verarbeitet wurde.
  Future<bool> isDuplicateUrl(String url) async {
    final db = await _dbHelper.database;
    final ninetyDaysAgo = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String();

    final result = await db.query(
      'applications',
      where: 'job_url = ? AND created_at >= ?',
      whereArgs: [url, ninetyDaysAgo],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Alle Bewerbungen mit bestimmtem Status.
  Future<List<Application>> loadApplicationsByStatus(
      ApplicationStatus status) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'applications',
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToApplication).toList();
  }

  // ---------------------------------------------------------------------------
  // VALIDATED URLS
  // ---------------------------------------------------------------------------

  /// Alle validierten URLs laden.
  Future<List<String>> loadValidatedUrls() async {
    final db = await _dbHelper.database;
    final rows = await db.query('validated_urls', orderBy: 'created_at DESC');
    return rows.map((r) => r['url'] as String).toList();
  }

  /// Validierte URLs speichern (zuvor alle löschen → ersetzen).
  Future<void> saveValidatedUrls(List<String> urls) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('validated_urls');
      final batch = txn.batch();
      for (final url in urls) {
        batch.insert('validated_urls', {
          'url': url,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    });
    _log.info('Validierte URLs gespeichert: ${urls.length}');
  }

  // ---------------------------------------------------------------------------
  // SEARCH FILTERS
  // ---------------------------------------------------------------------------

  /// Einzelnen Suchfilter laden.
  Future<String?> loadFilter(String key) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'search_filters',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  /// Alle Suchfilter laden.
  Future<Map<String, String>> loadAllFilters() async {
    final db = await _dbHelper.database;
    final rows = await db.query('search_filters');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  /// Suchfilter speichern (upsert).
  Future<void> saveFilter(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert(
      'search_filters',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mehrere Filter auf einmal speichern.
  Future<void> saveFilters(Map<String, String> filters) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final entry in filters.entries) {
      batch.insert(
        'search_filters',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------------------
  // RESET
  // ---------------------------------------------------------------------------

  /// Löscht die gesamte Datenbankdatei und erzwingt Neuerstellung.
  Future<void> forceResetDatabase() async {
    final dbHelper = _dbHelper;
    await dbHelper.forceReset();
    _log.info('Datenbank komplett zurückgesetzt');
  }

  // ---------------------------------------------------------------------------
  // CV DATA
  // ---------------------------------------------------------------------------

  /// Aktuelle CV-Daten laden (neuesten Eintrag).
  Future<CvData?> loadCvData() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'cv_data',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToCvData(rows.first);
  }

  /// CV-Daten speichern (alten Eintrag ersetzen).
  Future<void> saveCvData(CvData cvData) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('cv_data');
      await txn.insert('cv_data', _cvDataToRow(cvData));
    });
    _log.info('CV-Daten gespeichert für: ${cvData.personalData.fullName}');
  }

  // ---------------------------------------------------------------------------
  // KONVERTER
  // ---------------------------------------------------------------------------

  /// Converts Application to DB row. Excludes `id` for INSERT (AUTOINCREMENT).
  Map<String, dynamic> _applicationToRow(Application app,
      {bool includeId = false}) {
    final row = <String, dynamic>{
      'job_title': app.jobTitle,
      'company': app.company,
      'job_url': app.jobUrl,
      'status': app.status.name,
      'pdf_path': app.pdfPath,
      'error_message': app.errorMessage,
      'created_at': app.createdAt.toIso8601String(),
      'completed_at': app.completedAt?.toIso8601String(),
    };
    if (includeId) {
      row['id'] = app.id;
    }
    return row;
  }

  /// Converts Application to DB row for UPDATE (includes id).
  Map<String, dynamic> _applicationToRowForUpdate(Application app) =>
      _applicationToRow(app, includeId: true);

  Application _rowToApplication(Map<String, dynamic> row) => Application(
        id: row['id'] as int,
        jobTitle: row['job_title'] as String,
        company: row['company'] as String,
        jobUrl: row['job_url'] as String,
        status: ApplicationStatus.values.firstWhere(
          (e) => e.name == row['status'],
          orElse: () => ApplicationStatus.queued,
        ),
        pdfPath: row['pdf_path'] as String?,
        errorMessage: row['error_message'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        completedAt: row['completed_at'] != null
            ? DateTime.parse(row['completed_at'] as String)
            : null,
      );

  Map<String, dynamic> _cvDataToRow(CvData cvData) => {
        'personal_data_json': jsonEncode(cvData.personalData.toJson()),
        'work_experience_json':
            jsonEncode(cvData.workExperience.map((e) => e.toJson()).toList()),
        'education_json':
            jsonEncode(cvData.education.map((e) => e.toJson()).toList()),
        'skills_json':
            jsonEncode(cvData.skills.map((e) => e.toJson()).toList()),
        'loaded_at': DateTime.now().toIso8601String(),
      };

  CvData _rowToCvData(Map<String, dynamic> row) {
    return CvData(
      personalData: PersonalData.fromJson(
          jsonDecode(row['personal_data_json'] as String)
              as Map<String, dynamic>),
      workExperience: (jsonDecode(row['work_experience_json'] as String)
              as List<dynamic>)
          .map((e) => WorkExperience.fromJson(e as Map<String, dynamic>))
          .toList(),
      education: (jsonDecode(row['education_json'] as String) as List<dynamic>)
          .map((e) => Education.fromJson(e as Map<String, dynamic>))
          .toList(),
      skills: (jsonDecode(row['skills_json'] as String) as List<dynamic>)
          .map((e) => Skill.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}