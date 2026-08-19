import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:logging/logging.dart';
import '../../models/job_offer.dart';
import 'job_title_cleaner.dart';

/// Ergebnis einer Job-Extraktion aus einer Stellen-URL.
class JobScrapeResult {
  final String title;
  final String? company;
  final String? companyAddress;
  final String? location;
  final String? description;

  const JobScrapeResult({
    required this.title,
    this.company,
    this.companyAddress,
    this.location,
    this.description,
  });
}

/// Service zum Extrahieren von Job-Daten aus HTML-Seiten (Scraping).
///
/// Wird als Fallback verwendet, wenn keine strukturierte API verfügbar ist.
/// Extrahiert Titel, Firma, Beschreibung und Ort aus Stellen-URLs.
///
/// **Rechtlicher Hinweis:**
/// Scraping unterliegt rechtlichen Einschränkungen (AGB, Urheberrecht).
/// Nur als Fallback einsetzen, wenn keine API verfügbar ist.
class JobScraperService {
  final Logger _log = Logger('JobScraperService');
  final http.Client _client;
  String? _lastCompanyAddress;

  JobScraperService({http.Client? client})
      : _client = client ?? http.Client();

  /// Extrahiert Job-Informationen aus einer Liste von URLs.
  Future<List<JobOffer>> extractJobs(List<String> urls) async {
    final results = <JobOffer>[];
    for (final url in urls) {
      try {
        final job = await _extractFromUrl(url);
        if (job != null) {
          results.add(job);
        }
      } catch (e) {
        _log.warning('Scraping fehlgeschlagen für $url: $e');
      }
    }
    return results;
  }

  /// Extrahiert Job-Informationen aus einer einzelnen URL.
  Future<JobOffer?> _extractFromUrl(String url) async {
    _log.fine('Extrahiere Job-Daten von: $url');

    final response = await _client.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (response.statusCode != 200) {
      _log.warning('HTTP ${response.statusCode} für $url');
      return null;
    }

    final document = parser.parse(response.body);
    final title = _tryExtract(document, [
      'meta[property="og:title"]',
      'h1.job-title',
      'h1[class*=title]',
      'h1[class*=position]',
      'title',
    ]);

    final company = _tryExtract(document, [
      'meta[property="og:site_name"]',
      '[class*=company]',
      '[class*=employer]',
      '[class*=arbeitgeber]',
      '[class*=unternehmen]',
      '[class*=firma]',
      '[itemprop*=name]',
    ]);

    final description = _tryExtract(document, [
      'meta[property="og:description"]',
      '[class*=description]',
      '[class*=job-text]',
      '[class*=stellenbeschreibung]',
      '[itemprop*=description]',
    ]);

    final location = _tryExtract(document, [
      '[class*=location]',
      '[class*=ort]',
      '[class*=standort]',
      '[itemprop*=location]',
      '[class*=address]',
    ]);

    // Firmenadresse extrahieren (falls vorhanden)
    _lastCompanyAddress = _tryExtract(document, [
      '[class*=company-address]',
      '[class*=address]',
      '[itemprop*=address]',
      '[class*=kontakt]',
      '[class*=contact]',
    ]);

    if (title == null) {
      _log.warning('Konnte keinen Job-Titel extrahieren von: $url');
      return null;
    }

    // Jobtitel bereinigen (Webseiten-Suffixe wie "| Jobs at X" entfernen).
    final cleanedTitle = JobTitleCleaner.cleanJobTitle(title);

    // Fallback für Firma: URL-Domain ableiten, falls keine Firma gefunden.
    var finalCompany = company;
    if (finalCompany == null || finalCompany == 'Unbekannt') {
      finalCompany = _deriveCompanyFromUrl(url);
    }

    final jobId = _generateId(url, title);

    _log.info('Job extrahiert: $cleanedTitle bei $finalCompany');
    return JobOffer(
      id: jobId,
      title: cleanedTitle,
      company: finalCompany ?? 'Unbekannt',
      location: location,
      description: description,
      url: url,
      source: 'scrape',
    );
  }

  /// Extrahiert Job-Informationen als JobScrapeResult (für Repository).
  Future<JobScrapeResult?> extractJobResult(String url) async {
    final job = await _extractFromUrl(url);
    if (job == null) return null;
    return JobScrapeResult(
      title: job.title,
      company: job.company,
      companyAddress: _lastCompanyAddress,
      location: job.location,
      description: job.description,
    );
  }

  /// Leitet einen Firmennamen aus der URL-Domain ab.
  ///
  /// Beispiel: `https://jobs.bliq.com/...` -> "Bliq"
  String? _deriveCompanyFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      // Domains wie "www.bliq.de", "jobs.bliq.com", "bliq.com" -> erste Domain
      final parts = host.split('.');
      if (parts.length >= 2) {
        // Entferne typische Subdomains
        final knownSubdomains = {'www', 'jobs', 'careers', 'karriere', 'apply', 'recruiting', 'hr', 'talent', 'talents', 'stack', 'boards', 'job', 'stellen'};
        var domainPart = parts[0];
        while (knownSubdomains.contains(domainPart) && parts.length > 2) {
          parts.removeAt(0);
          domainPart = parts[0];
        }
        // Erstes Zeichen großschreiben
        final company = domainPart[0].toUpperCase() + domainPart.substring(1);
        if (company.isNotEmpty) return company;
      }
    } catch (_) {
      // Nicht-URL-String – ignorieren
    }
    return null;
  }

  /// Versucht, einen Wert über mehrere CSS-Selektoren zu extrahieren.
  String? _tryExtract(Document doc, List<String> selectors) {
    for (final selector in selectors) {
      if (selector.startsWith('meta')) {
        // Meta-Tag: content-Attribut lesen
        final element = doc.querySelector(selector);
        if (element != null) {
          final content = element.attributes['content'];
          if (content != null && content.isNotEmpty) {
            return content.trim();
          }
        }
      } else {
        // Normales Element: Text lesen
        final element = doc.querySelector(selector);
        if (element != null) {
          final text = element.text.trim();
          if (text.isNotEmpty) {
            return text;
          }
        }
      }
    }
    return null;
  }

  /// Generiert eine eindeutige ID für einen gescrapten Job.
  String _generateId(String url, String title) {
    // Kombiniere URL-Hash und Titel für eindeutige ID
    final hash = url.hashCode ^ title.hashCode;
    return 'scrape_${hash.abs()}';
  }

  void dispose() {
    _client.close();
  }
}