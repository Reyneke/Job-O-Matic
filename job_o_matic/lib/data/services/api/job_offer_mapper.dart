import '../../models/job_offer.dart';

/// Zentrale Mapper-Helfer für alle Job-Quellen (Jobsuche-Rev, Punkte 8 und 10).
///
/// Bündelt die bisher in `BaApiService` und `AdzunaApiService` duplizierte
/// Logik für Datums-/Gehalts-Formatierung sowie das Enum-Mapping von
/// Beschäftigungsart und Arbeitsmodell – an einer Stelle wartbar und
/// unit-testbar.
abstract final class JobOfferMapper {
  /// Parst ein Datum tolerant (ISO-8601 o. ä.); null bei leer/ungültig.
  static DateTime? parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Formatiert einen Betrag mit Tausender-Trennzeichen („45.000“).
  ///
  /// Ausgabe ohne Währungs-Suffix – der Aufrufer fügt „€“/„EUR“ passend zur
  /// Quelle an, damit die bestehenden UI-Formate (BA vs. Adzuna) erhalten
  /// bleiben.
  static String formatSalaryAmount(num value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]}.',
        );
  }

  /// Mappt die BA-Flags `arbeitszeitVollzeit`/`arbeitszeitTeilzeit` auf den
  /// [EmploymentType]. Beide gesetzt → `both`.
  static EmploymentType? employmentTypeFromBooleans({
    required bool isFullTime,
    required bool isPartTime,
  }) {
    if (isFullTime && isPartTime) return EmploymentType.both;
    if (isFullTime) return EmploymentType.fullTime;
    if (isPartTime) return EmploymentType.partTime;
    return null;
  }

  /// Mappt Adzuna-`contract_type`-Codes auf [EmploymentType].
  static EmploymentType? employmentTypeFromContract(String? contractType) {
    if (contractType == null) return null;
    const contractTypes = {
      'permanent': EmploymentType.fullTime,
      'contract': EmploymentType.fullTime,
      'part_time': EmploymentType.partTime,
      'full_time': EmploymentType.fullTime,
    };
    return contractTypes[contractType.toLowerCase()];
  }

  /// Leitet ein Arbeitsmodell aus einer (optionalen) Beschreibung ab.
  ///
  /// Liefert `null`, wenn die Beschreibung keinen eindeutigen Hinweis enthält.
  /// Quellen ohne Beschreibung (z. B. BA-Listen-Response) liefern bewusst
  /// `null` – der Filter in `JobSearchService` behandelt das als
  /// „nicht bewertbar → durchlassen“ (transparenter WorkModel-Filter).
  static WorkModel? workModelFromDescription(String? description) {
    if (description == null || description.trim().isEmpty) return null;
    final d = description.toLowerCase();

    if (d.contains('remote') ||
        d.contains('homeoffice') ||
        d.contains('home office') ||
        d.contains('voll remote') ||
        d.contains('100% remote')) {
      return WorkModel.remote;
    }
    if (d.contains('hybrid') || d.contains('flexibel')) {
      return WorkModel.hybrid;
    }
    if (d.contains('vor ort') ||
        d.contains('präsenz') ||
        d.contains('im büro') ||
        d.contains('on-site') ||
        d.contains('onsite')) {
      return WorkModel.onSite;
    }
    return null;
  }
}