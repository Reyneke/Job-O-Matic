import 'dart:convert';
import 'package:logging/logging.dart';
import 'api_client.dart';
import 'ba_job_details.dart';
import 'job_offer_mapper.dart';
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
  static const _jobDetailsPath = '/jobboerse/jobsuche-service/pc/v4/jobdetails';
  static const _apiKey = 'jobboerse-jobsuche';

  // Beobachtung "externe vs. interne BA-Anzeigen" (Session, doc/plan/16).
  // Bewusst in-memory (keine Persistenz über Neustarts) – für die Beobachtung
  // der Markt-Verteilung reicht eine Session-Statistik.
  int _searchedOffers = 0;
  int _externalOffers = 0;
  int _detailsChecked = 0;
  int _externalDetails = 0;

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
    final jobs = _parseJobOffers(data);
    _logSearchSummary(jobs.length, page);
    return jobs;
  }

  /// Holt die Details einer einzelnen Anzeige über
  /// `/jobboerse/jobsuche-service/pc/v4/jobdetails/{base64(refnr)}`.
  ///
  /// Die Detail-Antwort enthält **kein** strukturiertes Kontakt-/E-Mail-Feld –
  /// dafür die volle Beschreibung (→ E-Mail-Extraktion), bei externen Anzeigen
  /// `externeURL`/`allianzpartnerName` sowie die Arbeitgeber-Website. Siehe
  /// [BaJobDetails] und `doc/plan/16-Jobsuche-BA.md`.
  ///
  /// Wirft [JobApiException] bei HTTP-Fehlern oder ungültigem JSON.
  Future<BaJobDetails> fetchJobDetails(String refnr) async {
    final encoded = base64EncodeRefnr(refnr);
    final uri = Uri.https(_baseUrl, '$_jobDetailsPath/$encoded');

    final response = await _client.get(
      uri,
      extraHeaders: {
        'Accept': 'application/json',
        'X-API-Key': _apiKey,
      },
    );

    if (response.statusCode != 200) {
      throw JobApiException(
        'BA-Details-Fehler',
        statusCode: response.statusCode,
        details: response.body,
      );
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final details = BaJobDetails.fromJson(data);
      _detailsChecked++;
      final external = details.externalUrl != null;
      if (external) _externalDetails++;
      _log.fine('BA-Details ${external ? '(extern)' : '(intern)'}: $refnr');
      return details;
    } catch (e) {
      throw JobApiException(
        'BA-Details-Fehler (ungültige Antwort)',
        statusCode: response.statusCode,
        details: e.toString(),
      );
    }
  }

  /// Kodiert eine Referenznummer als URL-sicheres Base64 (UTF-8), wie es der
  /// `jobdetails`-Endpunkt erwartet. Beispiel: `10001-1002716922-S` →
  /// `MTAwMDEtMTAwMjcxNjkyMi1T`.
  static String base64EncodeRefnr(String refnr) {
    return base64Encode(utf8.encode(refnr));
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
      if (item is! Map<String, dynamic>) continue;
      final map = item;
      // Beobachtung: Gesamtzahl + externe/Allianz-Anzeigen zählen (unabhängig
      // vom nachfolgenden Job-Parsing, damit auch nicht-pflegbare Treffer
      // statistisch erfasst werden).
      _searchedOffers++;
      if (_isExternalOfferItem(map)) _externalOffers++;
      try {
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

  /// Erkennt eine **externe/Allianz-Anzeige** tolerant über die in Such- und
  /// Details-Antworten auftretenden Schreibweisen. Als „extern“ gilt eine
  /// Anzeige, wenn eine externe URL gesetzt ist (`externeUrl`/`externeURL`,
  /// Doku vs. Live-API) oder der verifizierte Allianz-Marker `allianzpartnerName`
  /// vorhanden ist. `arbeitgeberdarstellungUrl` (Arbeitgeber-Website) ist
  /// bewusst NICHT extern.
  static bool _isExternalOfferItem(Map<String, dynamic> map) {
    for (final key in const [
      'externeURL',
      'externeUrl',
      'allianzpartnerName',
    ]) {
      final v = map[key];
      if (v is String && v.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Aktuelle Session-Statistik zu externen vs. internen BA-Anzeigen.
  BaMarketStats get marketStats => BaMarketStats(
        searchedOffers: _searchedOffers,
        externalOffers: _externalOffers,
        detailsChecked: _detailsChecked,
        externalDetails: _externalDetails,
      );

  /// Loggt eine kompakte Zeile zur Markt-Verteilung nach einer Suche.
  void _logSearchSummary(int returned, int page) {
    final internal = _searchedOffers - _externalOffers;
    final pct = _searchedOffers > 0
        ? _externalOffers * 100 / _searchedOffers
        : 0.0;
    _log.info(
      'BA-Suche: $returned Treffer (Seite $page). Session: '
      '$_searchedOffers Anzeigen, davon $_externalOffers extern '
      '(${pct.toStringAsFixed(1)}%) / $internal intern.',
    );
  }

  /// Extrahiert die Gehaltsspanne aus `gehaltsspanneVon`/`gehaltsspanneBis`.
  String? _parseSalaryRange(Map<String, dynamic> map) {
    final salaryMin = map['gehaltsspanneVon'];
    final salaryMax = map['gehaltsspanneBis'];
    if (salaryMin == null && salaryMax == null) return null;

    return '${_formatSalary(salaryMin)} € – ${_formatSalary(salaryMax)} €';
  }

  /// Formatiert einen Gehaltswert mit Tausender-Trennzeichen.
  /// Delegiert an den gemeinsamen [JobOfferMapper] (Jobsuche-Rev, Punkt 8).
  String _formatSalary(dynamic value) {
    if (value is num) {
      return JobOfferMapper.formatSalaryAmount(value);
    }
    return value?.toString() ?? '?';
  }

  /// Ermittelt die Beschäftigungsart aus `arbeitszeitVollzeit`/`Teilzeit`.
  EmploymentType? _parseEmploymentType(Map<String, dynamic> map) {
    return JobOfferMapper.employmentTypeFromBooleans(
      isFullTime: map['arbeitszeitVollzeit'] == true,
      isPartTime: map['arbeitszeitTeilzeit'] == true,
    );
  }

  String _buildJobUrl(String refnr) {
    return 'https://www.arbeitsagentur.de/jobsuche/job/$refnr';
  }

  DateTime? _parseDate(String? dateStr) => JobOfferMapper.parseDate(dateStr);
}

/// Beobachtete Verteilung **externer vs. interner** BA-Anzeigen (Session).
///
/// Wird ohne zusätzliche Requests direkt aus den Such- und Details-Antworten
/// erfasst (doc/plan/16-Jobsuche-BA.md, „Beobachten“). Werte sind kumulativ
/// seit Instanzerstellung (App-Start) – bewusst NICHT über Neustarts
/// persistiert.
class BaMarketStats {
  /// Anzeigen, die in Such-Antworten gesehen wurden (Gesamtzahl).
  final int searchedOffers;

  /// Davon mit externer URL bzw. Allianz-Marker.
  final int externalOffers;

  /// Aufgerufene `jobdetails`-Abrufe (Details-Ebene, sekundär).
  final int detailsChecked;

  /// Davon extern (`externalUrl` gesetzt).
  final int externalDetails;

  const BaMarketStats({
    required this.searchedOffers,
    required this.externalOffers,
    required this.detailsChecked,
    required this.externalDetails,
  });

  /// Interne (nicht extern verlinkte) Anzeigen aus Such-Antworten.
  int get internalOffers => searchedOffers - externalOffers;

  /// Interne Details-Abrufe.
  int get internalDetails => detailsChecked - externalDetails;

  /// Anteil externer Anzeigen an allen Such-Treffern (0.0 wenn leer).
  double get externalShare =>
      searchedOffers > 0 ? externalOffers / searchedOffers : 0.0;

  /// Anteil externer Anzeigen an den Details-Abrufen (0.0 wenn leer).
  double get externalShareOfDetails =>
      detailsChecked > 0 ? externalDetails / detailsChecked : 0.0;
}
