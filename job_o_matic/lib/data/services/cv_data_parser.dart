import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:yaml/yaml.dart';
import '../../models/cv_data.dart';

/// Errors discovered during CV data parsing/validation.
class CvValidationError {
  final String field;
  final String message;

  const CvValidationError({required this.field, required this.message});

  @override
  String toString() => '$field: $message';
}

/// Result of parsing and validating CV data.
class CvParseResult {
  final CvData? data;
  final List<CvValidationError> errors;
  final bool isSuccess;

  const CvParseResult({
    this.data,
    this.errors = const [],
    this.isSuccess = false,
  });
}

/// Parser for structured CV data from YAML files.
///
/// Liest CV-Daten aus `assets/mydata/cv/cv_data.yaml`, validiert sie
/// und deserialisiert sie in die Datenmodelle (`CvData`, `PersonalData`, etc.).
class CvDataParser {
  final Logger _log = Logger('CvDataParser');

  /// Path to the CV data YAML file (relative to assets).
  static const String _defaultAssetPath = 'assets/mydata/cv/cv_data.yaml';

  /// Load and parse CV data from the default asset path.
  Future<CvParseResult> loadFromAssets({String? assetPath}) async {
    final path = assetPath ?? _defaultAssetPath;
    try {
      final yamlString = await rootBundle.loadString(path);
      return parse(yamlString);
    } catch (e) {
      _log.severe('Fehler beim Laden der CV-Daten aus $path: $e');
      return CvParseResult(
        errors: [
          CvValidationError(
            field: 'file',
            message: 'CV-Daten konnten nicht geladen werden: $e',
          ),
        ],
      );
    }
  }

  /// Parse a raw YAML string into validated CV data.
  CvParseResult parse(String yamlString) {
    final errors = <CvValidationError>[];

    try {
      final dynamic parsed = loadYaml(yamlString);
      if (parsed is! YamlMap) {
        return CvParseResult(
          errors: [
            CvValidationError(
              field: 'root',
              message: 'CV-Daten müssen ein YAML-Objekt sein.',
            ),
          ],
        );
      }

      final Map<String, dynamic> data = {};

      // Normalisiere Schlüssel (YamlMap → Map)
      for (final entry in parsed.entries) {
        data[entry.key.toString()] = entry.value;
      }

      // ── PersonalData parsen ──────────────────────────────────────
      PersonalData? personalData;
      if (data['personal_data'] is Map) {
        final pd = data['personal_data'] as Map;

        final firstName = _stringField(pd, 'first_name');
        final lastName = _stringField(pd, 'last_name');

        if (firstName == null) {
          errors.add(CvValidationError(
            field: 'personal_data.first_name',
            message: 'Vorname ist erforderlich.',
          ));
        }
        if (lastName == null) {
          errors.add(CvValidationError(
            field: 'personal_data.last_name',
            message: 'Nachname ist erforderlich.',
          ));
        }

        if (firstName != null && lastName != null) {
          personalData = PersonalData(
            firstName: firstName,
            lastName: lastName,
            email: _stringField(pd, 'email'),
            phone: _stringField(pd, 'phone'),
            address: _stringField(pd, 'address'),
            photoPath: _stringField(pd, 'photo_path'),
          );
        }
      } else {
        errors.add(CvValidationError(
          field: 'personal_data',
          message: 'Persönliche Daten (personal_data) fehlen oder sind ungültig.',
        ));
      }

      // ── WorkExperience parsen ────────────────────────────────────
      final workExperience = <WorkExperience>[];
      if (data['work_experience'] is List) {
        for (int i = 0; i < (data['work_experience'] as List).length; i++) {
          final we = (data['work_experience'] as List)[i] as Map?;
          if (we == null) continue;

          final company = _stringField(we, 'company');
          final position = _stringField(we, 'position');

          if (company == null) {
            errors.add(CvValidationError(
              field: 'work_experience[$i].company',
              message: 'Firmenname ist erforderlich.',
            ));
          }
          if (position == null) {
            errors.add(CvValidationError(
              field: 'work_experience[$i].position',
              message: 'Position ist erforderlich.',
            ));
          }

          final startDate = _dateField(we, 'start_date');
          final endDate = _dateField(we, 'end_date');

          if (startDate == null) {
            errors.add(CvValidationError(
              field: 'work_experience[$i].start_date',
              message: 'Startdatum ist erforderlich (Format: YYYY-MM-DD).',
            ));
          }

          // Validierung: endDate nicht vor startDate
          if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
            errors.add(CvValidationError(
              field: 'work_experience[$i].end_date',
              message: 'Enddatum darf nicht vor dem Startdatum liegen.',
            ));
          }

          if (company != null && position != null && startDate != null) {
            workExperience.add(WorkExperience(
              company: company,
              position: position,
              startDate: startDate,
              endDate: endDate,
              description: _stringField(we, 'description'),
            ));
          }
        }
      }

      // ── Education parsen ────────────────────────────────────────
      final education = <Education>[];
      if (data['education'] is List) {
        for (int i = 0; i < (data['education'] as List).length; i++) {
          final ed = (data['education'] as List)[i] as Map?;
          if (ed == null) continue;

          final institution = _stringField(ed, 'institution');
          final degree = _stringField(ed, 'degree');

          if (institution == null) {
            errors.add(CvValidationError(
              field: 'education[$i].institution',
              message: 'Institution ist erforderlich.',
            ));
          }
          if (degree == null) {
            errors.add(CvValidationError(
              field: 'education[$i].degree',
              message: 'Abschluss ist erforderlich.',
            ));
          }

          final startDate = _dateField(ed, 'start_date');
          final endDate = _dateField(ed, 'end_date');

          if (startDate == null) {
            errors.add(CvValidationError(
              field: 'education[$i].start_date',
              message: 'Startdatum ist erforderlich (Format: YYYY-MM-DD).',
            ));
          }

          if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
            errors.add(CvValidationError(
              field: 'education[$i].end_date',
              message: 'Enddatum darf nicht vor dem Startdatum liegen.',
            ));
          }

          if (institution != null && degree != null && startDate != null) {
            education.add(Education(
              institution: institution,
              degree: degree,
              startDate: startDate,
              endDate: endDate,
              field: _stringField(ed, 'field'),
            ));
          }
        }
      }

      // ── Skills parsen ───────────────────────────────────────────
      final skills = <Skill>[];
      if (data['skills'] is List) {
        for (int i = 0; i < (data['skills'] as List).length; i++) {
          final sk = (data['skills'] as List)[i] as Map?;
          if (sk == null) continue;

          final name = _stringField(sk, 'name');
          final proficiency = _doubleField(sk, 'proficiency');

          if (name == null) {
            errors.add(CvValidationError(
              field: 'skills[$i].name',
              message: 'Skill-Name ist erforderlich.',
            ));
          }
          if (proficiency == null) {
            errors.add(CvValidationError(
              field: 'skills[$i].proficiency',
              message: 'Skill-Wert (0.0–1.0) ist erforderlich.',
            ));
          } else if (proficiency < 0.0 || proficiency > 1.0) {
            errors.add(CvValidationError(
              field: 'skills[$i].proficiency',
              message: 'Skill-Wert muss zwischen 0.0 und 1.0 liegen (aktuell: $proficiency).',
            ));
          }

          if (name != null && proficiency != null &&
              proficiency >= 0.0 && proficiency <= 1.0) {
            skills.add(Skill(
              name: name,
              proficiency: proficiency,
            ));
          }
        }
      }

      // ── Ergebnis ────────────────────────────────────────────────
      if (personalData == null || errors.isNotEmpty) {
        _log.warning(
            'CV-Daten-Parsing abgeschlossen mit ${errors.length} Fehlern');
        return CvParseResult(
          data: personalData != null
              ? CvData(
                  personalData: personalData,
                  workExperience: workExperience,
                  education: education,
                  skills: skills,
                )
              : null,
          errors: errors,
          isSuccess: false,
        );
      }

      final cvData = CvData(
        personalData: personalData,
        workExperience: workExperience,
        education: education,
        skills: skills,
      );

      _log.info(
        'CV-Daten erfolgreich geladen: ${personalData.fullName}, '
        '${workExperience.length} Berufserfahrungen, '
        '${education.length} Ausbildungen, '
        '${skills.length} Skills',
      );

      return CvParseResult(
        data: cvData,
        errors: errors,
        isSuccess: true,
      );
    } catch (e, stack) {
      _log.severe('Fehler beim Parsen der CV-Daten: $e\n$stack');
      return CvParseResult(
        errors: [
          CvValidationError(
            field: 'parse',
            message: 'Allgemeiner Parsing-Fehler: $e',
          ),
        ],
      );
    }
  }

  // ── Hilfsfunktionen ──────────────────────────────────────────

  String? _stringField(Map map, String key) {
    final value = map[key];
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  double? _doubleField(Map map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  DateTime? _dateField(Map map, String key) {
    final value = map[key];
    if (value == null) return null;
    return DateTime.tryParse(value.toString().trim());
  }
}