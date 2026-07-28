import 'dart:convert';
import 'package:logging/logging.dart';
import 'api_client.dart';
import 'api_key_service.dart';
import '../../models/job_offer.dart';

/// Service für die Adzuna-API.
///
/// API-Dokumentation: https://developer.adzuna.com/
///
/// **Authentifizierung:**
/// - App-ID und API-Key erforderlich (kostenlose Registrierung)
/// - Rate-Limit: 50 API-Calls/Tag im Free-Tier
///
/// **Endpunkt:**
/// - Jobsuche: `https://api.adzuna.com/v1/api/jobs/{country}/search/{page}`
class AdzunaApiService {
  final Logger _log = Logger('AdzunaApiService');
  final ApiClient _client;
  final ApiKeyService _keyService;

  static const _baseUrl = 'api.adzuna.com';
  static const _country = 'de';

  AdzunaApiService({
    required ApiClient client,
    required ApiKeyService keyService,
  })  : _client = client,
        _keyService = keyService;

  /// Sucht Stellen über die Adzuna-API.
  Future<List<JobOffer>> search({
    required String query,
    String? location,
    int radius = 25,
    EmploymentType? employmentType,
    int page = 1,
    int size = 20,
  }) async {
    final appId = await _keyService.loadKey(ApiKeyService.adzunaAppId);
    final apiKey = await _keyService.loadKey(ApiKeyService.adzunaApiKey);

    if (appId == null || apiKey == null) {
      throw JobApiException(
        'Adzuna API-Keys nicht konfiguriert. '
        'Bitte App-ID und API-Key in den Einstellungen hinterlegen.',
      );
    }

    final params = <String, String>{
      'app_id': appId,
      'app_key': apiKey,
      'what': query,
      'results_per_page': size.toString(),
      'content-type': 'application/json',
    };

    if (location != null && location.isNotEmpty) {
      params['where'] = location;
      params['distance'] = radius.toString();
    }

    if (employmentType == EmploymentType.fullTime) {
      params['full_time'] = '1';
    } else if (employmentType == EmploymentType.partTime) {
      params['part_time'] = '1';
    }

    final uri = Uri.https(
      _baseUrl,
      '/v1/api/jobs/$_country/search/$page',
      params,
    );

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw JobApiException(
        'Adzuna-API-Fehler',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseJobOffers(data);
  }

  List<JobOffer> _parseJobOffers(Map<String, dynamic> data) {
    final results = <JobOffer>[];
    final items = data['results'] as List<dynamic>? ?? [];

    for (final item in items) {
      try {
        final map = item as Map<String, dynamic>;
        final company = map['company'] as Map<String, dynamic>?;
        final location = map['location'] as Map<String, dynamic>?;
        final area = location?['area'] as List<dynamic>?;

        results.add(JobOffer(
          id: (map['id'] ?? '').toString(),
          title: (map['title'] ?? 'Unbekannt') as String,
          company: (company?['display_name'] ?? 'Unbekannt') as String,
          location: area?.isNotEmpty == true ? area!.first.toString() : null,
          description: map['description'] as String?,
          url: (map['redirect_url'] ?? '') as String,
          salaryRange: _parseSalary(map),
          employmentType: _parseEmploymentType(map),
          publishedAt: _parseDate(map['created'] as String?),
          source: 'adzuna',
        ));
      } catch (e) {
        _log.warning('Fehler beim Parsen eines Adzuna-Jobs: $e');
      }
    }

    return results;
  }

  String? _parseSalary(Map<String, dynamic> map) {
    final salaryMin = map['salary_min'];
    final salaryMax = map['salary_max'];
    if (salaryMin == null && salaryMax == null) return null;
    return '${salaryMin?.toStringAsFixed(0) ?? '?'} - '
        '${salaryMax?.toStringAsFixed(0) ?? '?'} '
        '${map['salary_currency'] ?? 'EUR'}';
  }

  EmploymentType? _parseEmploymentType(Map<String, dynamic> map) {
    const contractTypes = {
      'permanent': EmploymentType.fullTime,
      'contract': EmploymentType.fullTime,
      'part_time': EmploymentType.partTime,
      'full_time': EmploymentType.fullTime,
    };
    final contract = map['contract_type'] as String?;
    if (contract != null) {
      return contractTypes[contract.toLowerCase()];
    }
    return null;
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr);
  }
}