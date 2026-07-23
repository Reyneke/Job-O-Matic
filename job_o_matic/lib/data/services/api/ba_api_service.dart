import 'dart:convert';
import 'package:logging/logging.dart';
import 'api_client.dart';
import 'api_key_service.dart';
import '../../models/job_offer.dart';

/// Service für die Bundesagentur für Arbeit (JOBBÖRSE-API).
///
/// Dokumentation: https://jobsuche.api.bund.dev/
class BaApiService {
  final Logger _log = Logger('BaApiService');
  final ApiClient _client;

  static const _baseUrl = 'rest.arbeitsagentur.de';
  static const _searchPath = '/jobsearch/v1/jobsearch';

  BaApiService({required ApiClient client}) : _client = client;

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
      'fulltext': query,
      'page': page.toString(),
      'size': size.toString(),
    };

    if (location != null && location.isNotEmpty) {
      params['ort'] = location;
      params['umkreis'] = radius.toString();
    }

    if (employmentType == EmploymentType.fullTime) {
      params['arbeitszeit'] = 'vollzeit';
    } else if (employmentType == EmploymentType.partTime) {
      params['arbeitszeit'] = 'teilzeit';
    }

    final uri = Uri.https(_baseUrl, _searchPath, params);

    final response = await _client.get(
      uri,
      apiKeyName: ApiKeyService.baApiKey,
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