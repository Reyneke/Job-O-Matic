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
    // Die tatsächliche Response-Struktur kann abweichen – nach Test mit curl prüfen.
    final items = data['stellenangebote'] as List<dynamic>? ?? [];

    for (final item in items) {
      try {
        final map = item as Map<String, dynamic>;
        results.add(JobOffer(
          id: (map['refnr'] ?? '').toString(),
          title: (map['titel'] ?? 'Unbekannt') as String,
          company: (map['arbeitgeber'] ?? 'Unbekannt') as String,
          location: map['ort'] as String?,
          description: map['kurzbeschreibung'] as String?,
          url: _buildJobUrl(map['refnr']?.toString() ?? ''),
          publishedAt: _parseDate(map['aktuelleVeroeffentlichungsdatum'] as String?),
          source: 'ba',
        ));
      } catch (e) {
        _log.warning('Fehler beim Parsen eines BA-Jobs: $e');
      }
    }

    return results;
  }

  String _buildJobUrl(String refnr) {
    return 'https://www.arbeitsagentur.de/jobsuche/job/$refnr';
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr);
  }
}
