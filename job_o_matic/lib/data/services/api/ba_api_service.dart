import 'dart:convert';
import 'package:logging/logging.dart';
import 'api_client.dart';
import '../../models/job_offer.dart';

/// Service für die Bundesagentur für Arbeit (JOBBÖRSE-API).
///
/// API-Dokumentation: https://github.com/bundesAPI/jobsuche-api
///
/// **Wichtiger Hinweis zur Authentifizierung:**
/// Die API verwendet einen **festen, öffentlichen API-Key** – keine individuelle Registrierung nötig.
/// - Header: `X-API-Key: jobboerse-jobsuche`
/// - Fallback: `X-API-KEY: jobboerse-jobsuche` (andere Schreibweise)
///
/// **Endpunkt:**
/// - Jobsuche: `/jobboerse/jobsuche-service/pc/v6/jobs`
/// - Jobdetails: `/jobboerse/jobsuche-service/pc/v4/jobdetails/{base64(refnr)}`
/// - Logo: `/vermittlung/ag-darstellung-service/ct/v1/arbeitgeberlogo/{hash}`
class BaApiService {
  final Logger _log = Logger('BaApiService');
  final ApiClient _client;

  static const _baseUrl = 'rest.arbeitsagentur.de';
  static const _searchPath = '/jobboerse/jobsuche-service/pc/v6/jobs';
  static const _apiKey = 'jobboerse-jobsuche';

  BaApiService({required this._client});

  /// Sucht Stellen über die BA-JOBBÖRSE-API.
  Future<List<JobOffer>> search({
    required String query,
    String? location,
    int radius = 25,
    EmploymentType? employmentType,
    int page = 1,
    int size = 20,
  }) async {
    final params = <String, String>{
      'was': query,
      'page': page.toString(),
      'size': size.toString(),
    };

    if (location != null && location.isNotEmpty) {
      params['wo'] = location;
      params['umkreis'] = radius.toString();
    }

    if (employmentType == EmploymentType.fullTime) {
      params['arbeitszeit'] = 'vz';
    } else if (employmentType == EmploymentType.partTime) {
      params['arbeitszeit'] = 'tz';
    }

    final uri = Uri.https(_baseUrl, _searchPath, params);

    final response = await _client.get(
      uri,
      extraHeaders: {
        'Accept': 'application/json',
        'X-API-Key': _apiKey,
      },
    );

    if (response.statusCode != 200) {
      throw JobApiException(
        'BA-API-Fehler',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseJobOffers(data);
  }

  List<JobOffer> _parseJobOffers(Map<String, dynamic> data) {
    final results = <JobOffer>[];
    // Verifizierte Response-Struktur (Stand: 2026-07-26):
    // - Ergebnisliste: data['ergebnisliste']
    // - Job-ID:        map['referenznummer']
    // - Titel:         map['stellenangebotsTitel']
    // - Arbeitgeber:   map['firma']
    // - Ort:           map['stellenlokationen'][0]['adresse']['ort']
    // - Datum:         map['datumErsteVeroeffentlichung']
    // - Beschreibung:  In der Listen-Response nicht enthalten → null
    final items = data['ergebnisliste'] as List<dynamic>? ?? [];

    for (final item in items) {
      try {
        final map = item as Map<String, dynamic>;
        final refnr = (map['referenznummer'] ?? '').toString();
        final locations = map['stellenlokationen'] as List<dynamic>? ?? [];
        final cities = locations.map((loc) {
          final adresse = (loc as Map<String, dynamic>?)?['adresse']
              as Map<String, dynamic>?;
          return adresse?['ort'] as String?;
        }).whereType<String>().toList();

        results.add(JobOffer(
          id: refnr,
          title: (map['stellenangebotsTitel'] ?? 'Unbekannt') as String,
          company: (map['firma'] ?? 'Unbekannt') as String,
          location: cities.isNotEmpty ? cities.join(', ') : null,
          description: null, // Listen-Response enthält keine Beschreibung
          url: _buildJobUrl(refnr),
          salaryRange: _parseSalaryRange(map),
          employmentType: _parseEmploymentType(map),
          publishedAt: _parseDate(map['datumErsteVeroeffentlichung'] as String?),
          source: 'ba',
        ));
      } catch (e) {
        _log.warning('Fehler beim Parsen eines BA-Jobs: $e');
      }
    }

    return results;
  }

  /// Extrahiert die Gehaltsspanne aus `gehaltsspanneVon`/`gehaltsspanneBis`.
  String? _parseSalaryRange(Map<String, dynamic> map) {
    final salaryMin = map['gehaltsspanneVon'];
    final salaryMax = map['gehaltsspanneBis'];
    if (salaryMin == null && salaryMax == null) return null;

    return '${_formatSalary(salaryMin)} € – ${_formatSalary(salaryMax)} €';
  }

  /// Formatiert einen Gehaltswert mit Tausender-Trennzeichen.
  String _formatSalary(dynamic value) {
    if (value is num) {
      return value.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+$)'),
            (m) => '${m[1]}.',
          );
    }
    return value?.toString() ?? '?';
  }

  /// Ermittelt die Beschäftigungsart aus `arbeitszeitVollzeit`.
  EmploymentType? _parseEmploymentType(Map<String, dynamic> map) {
    final isFullTime = map['arbeitszeitVollzeit'] == true;
    final isPartTime = map['arbeitszeitTeilzeit'] == true;
    if (isFullTime && isPartTime) return EmploymentType.both;
    if (isFullTime) return EmploymentType.fullTime;
    if (isPartTime) return EmploymentType.partTime;
    return null;
  }

  String _buildJobUrl(String refnr) {
    return 'https://www.arbeitsagentur.de/jobsuche/job/$refnr';
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr);
  }
}
