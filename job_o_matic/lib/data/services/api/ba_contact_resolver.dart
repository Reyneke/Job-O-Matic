import 'package:logging/logging.dart';

import 'ba_api_service.dart';
import 'ba_job_details.dart';
import '../email/email_address_utils.dart';
import '../email/email_discovery_service.dart';

/// Fundstelle der ermittelten Kontakt-E-Mail (legitim, kein Captcha-Umgehen).
enum BaContactSource {
  /// Keine E-Mail gefunden -> manueller Fallback in der UI.
  none,

  /// E-Mail direkt aus der `stellenangebotsBeschreibung` extrahiert (offline).
  description,

  /// E-Mail über die externe Anzeige (`externeURL`) ermittelt.
  externalJobPage,

  /// E-Mail über die Arbeitgeber-Website ermittelt (Impressum/Karriere/Kontakt).
  employerWebsite,
}

/// Ergebnis der Kontakt-Ermittlung zu einer BA-Stellenanzeige.
class BaContactResolution {
  final String? email;
  final BaContactSource source;

  /// Erklärung/Hinweis für die UI (z. B. „keine E-Mail – bitte manuell ergänzen“).
  final String? note;

  /// Externe Anzeige (zum Öffnen/Bewerben), sofern vorhanden.
  final String? externalUrl;

  /// Arbeitgeber-Website, sofern vorhanden.
  final String? website;

  /// Erste Anschrift aus der Anzeige, sofern vorhanden.
  final String? address;

  const BaContactResolution({
    this.email,
    required this.source,
    this.note,
    this.externalUrl,
    this.website,
    this.address,
  });

  bool get found => email != null;
}

/// Ermittelt legitime Kontaktdaten zu einer BA-Anzeige
/// (doc/plan/16-Jobsuche-BA.md).
///
/// Kaskade – **bewusst ohne Captcha-Umgehung / ohne Scraping der BA-HTML-Seite**
/// (arbeitsagentur.de ist captcha-/logingeschützt und nie Teil dieser Logik):
/// 1. `jobdetails` über die dokumentierte REST-API laden.
/// 2. E-Mail aus dem Beschreibungstext extrahieren (offline, robust gegen
///    Anti-Spam-/HTML-verdeckte Schreibweisen).
/// 3. Sonst externe Anzeige (`externeURL`, nicht BA-Host) über den
///    [EmailDiscoveryService] durchsuchen (mailto:/Kontaktseite).
/// 4. Sonst Arbeitgeber-Website (nicht BA-Host) durchsuchen.
/// 5. Sonst `source: none` – die UI bietet einen manuellen Fallback.
class BaContactResolver {
  final Logger _log = Logger('BaContactResolver');
  final BaApiService _baService;
  final EmailDiscoveryService _discovery;

  BaContactResolver({
    required BaApiService baService,
    required EmailDiscoveryService discovery,
  })  : _baService = baService,
        _discovery = discovery;

  /// Hosts, deren HTML-Seiten bewusst NIE gescraped werden (Captcha/AGB).
  static const List<String> _blockedHosts = ['arbeitsagentur.de'];

  /// Ermittelt Kontaktdaten zu einer [refnr].
  ///
  /// Wirft Fehler von [BaApiService.fetchJobDetails] (z. B. [JobApiException])
  /// unverändert weiter, damit der Aufrufer entscheiden kann, ob die
  /// BA-Verbindung als Ganzes fehlgeschlagen ist.
  Future<BaContactResolution> resolve({required String refnr}) async {
    final details = await _baService.fetchJobDetails(refnr);

    final infoParts = <String>[];
    if (details.externalUrl != null) {
      infoParts.add('externe Anzeige: ${details.externalUrl}');
    }
    if (details.website != null) {
      infoParts.add('Arbeitgeber-Website: ${details.website}');
    }

    // Stufe 2: E-Mail offline aus der Beschreibung extrahieren.
    final descriptionEmail = firstEmailAddressRobust(details.description);
    if (descriptionEmail != null) {
      _log.fine('Kontakt-E-Mail aus Beschreibung: $descriptionEmail');
      return _resolution(
        details,
        email: descriptionEmail,
        source: BaContactSource.description,
      );
    }

    // Stufe 3: externe Anzeige (außer BA-Host).
    final externalUrl = details.externalUrl;
    if (externalUrl != null && !_isBlockedHost(externalUrl)) {
      final found = await _discoverOn(
        details,
        source: BaContactSource.externalJobPage,
        url: externalUrl,
      );
      if (found != null) return found;
    }

    // Stufe 4: Arbeitgeber-Website (außer BA-Host).
    final website = details.website;
    if (website != null && !_isBlockedHost(website)) {
      final found = await _discoverOn(
        details,
        source: BaContactSource.employerWebsite,
        url: website,
      );
      if (found != null) return found;
    }

    // Stufe 5: manueller Fallback.
    final infoSuffix =
        infoParts.isNotEmpty ? ' ${infoParts.join(' · ')}' : '';
    return BaContactResolution(
      source: BaContactSource.none,
      note: 'Keine E-Mail automatisch ermittelt – bitte manuell ergänzen.$infoSuffix',
      externalUrl: details.externalUrl,
      website: details.website,
      address: details.primaryAddress,
    );
  }


  /// Führt die Netzwerk-Kaskade des [EmailDiscoveryService] für [url] aus und
  /// liefert bei einem Treffer ein [BaContactResolution], sonst `null`.
  Future<BaContactResolution?> _discoverOn(
    BaJobDetails details, {
    required BaContactSource source,
    required String url,
  }) async {
    final result = await _discovery.discover(
      jobUrl: url,
      company: details.company,
      companyAddress: details.primaryAddress,
      jobDescription: details.description,
    );
    if (!result.found) {
      _log.fine('Keine E-Mail über ${source.name} bei $url.');
      return null;
    }
    _log.fine('Kontakt-E-Mail über ${source.name} ($url): ${result.email}');
    return _resolution(
      details,
      email: result.email,
      source: source,
      note: result.note,
    );
  }

  /// Baut ein [BaContactResolution] aus den Anzeigen-Details und überschreibt
  /// die Netzwerk-Fundstelle (`source`).
  BaContactResolution _resolution(
    BaJobDetails details, {
    required String? email,
    required BaContactSource source,
    String? note,
  }) {
    return BaContactResolution(
      email: email,
      source: source,
      note: note,
      externalUrl: details.externalUrl,
      website: details.website,
      address: details.primaryAddress,
    );
  }

  /// True, wenn [url] auf eine gesperrte (captcha-/logingeschützte) Domain
  /// zeigt – diese wird nie über die HTML-Seite angesprochen.
  bool _isBlockedHost(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return _blockedHosts.any((b) => host == b || host.endsWith('.$b'));
  }
}

/// True, wenn [url] auf die (captcha-/logingeschützte) HTML-Jobsuche der BA
/// zeigt (`arbeitsagentur.de`). Solche URLs werden **nie** über die HTML-Seite
/// angesprochen – Kontaktdaten liefert die REST-Kaskade ([BaContactResolver]).
bool isBaJobUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host == 'arbeitsagentur.de' || host.endsWith('.arbeitsagentur.de');
}

/// Extrahiert die BA-Referenznummer (`refnr`) aus einer BA-Jobsuche-URL
/// (`https://www.arbeitsagentur.de/jobsuche/job/{refnr}`, wie sie
/// `BaApiService._buildJobUrl` erzeugt). Liefert `null` für Nicht-BA-URLs oder
/// wenn kein `.../job/{refnr}`-Segment enthalten ist.
///
/// Diese Detektion ist bewusst URL-basiert (kein `source`-Feld nötig): Eine
/// übernommene BA-Bewerbung behält diese URL über App-Neustarts hinweg, sodass
/// der Versand-Screen die refnr auch nach erneutem Laden aus der DB ermitteln
/// kann.
String? baRefnrFromJobUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'arbeitsagentur.de' && !host.endsWith('.arbeitsagentur.de')) {
    return null;
  }
  final segments = uri.pathSegments;
  final jobIndex = segments.indexOf('job');
  if (jobIndex < 0 || jobIndex + 1 >= segments.length) return null;
  final refnr = segments[jobIndex + 1];
  return refnr.isEmpty ? null : refnr;
}
