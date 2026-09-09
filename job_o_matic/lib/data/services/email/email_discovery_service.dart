import 'dart:async';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'email_address_utils.dart';

/// Fundstelle einer ermittelten E-Mail-Adresse (Stufe der Kaskade).
enum EmailDiscoverySource {
  /// Stufe 1: Regex in bereits gespeicherten Daten (kein Netzwerkzugriff).
  storedData,

  /// Stufe 2: `mailto:`-Link der Stellenanzeige.
  mailtoLink,

  /// Stufe 3: genau eine verfolgte Kontaktseite.
  contactPage,

  /// Keine Adresse gefunden (→ Stufe 4: manuelle Eingabe im Dialog).
  none,
}

/// Ergebnis der E-Mail-Adress-Ermittlung.
class EmailDiscoveryResult {
  final String? email;
  final EmailDiscoverySource source;

  /// Optionale Begründung, z. B. „CAPTCHA/Blocker – Abbruch (Stufe 4)“.
  final String? note;

  /// Fundstelle (URL), über die die Adresse ermittelt wurde – für Transparenz
  /// und Persistenz (doc/plan/17, DB v8 `email_evidence_url`). Bei
  /// `mailtoLink` die Job-URL, bei `contactPage` die aufgelöste Kontakt-URL,
  /// bei `storedData`/`none` `null`.
  final String? evidenceUrl;

  const EmailDiscoveryResult({
    this.email,
    required this.source,
    this.note,
    this.evidenceUrl,
  });

  bool get found => email != null;
}

/// E-Mail-Adress-Ermittlung als Kaskade (doc/plan/14-Email.md §Kaskade).
///
/// 1. **Stufe 1** – Regex auf bereits erfasste Daten (kein neuer Request)
/// 2. **Stufe 2** – `mailto:`-Link der Stellenanzeige (Seite erneut laden)
/// 3. **Stufe 3** – genau **ein** Kontaktlink (`Kontakt`/`Impressum`/
///    `Karriere`, engl. Pendants) folgen und dort suchen – max. 1 Zusatz-
///    Request mit Timeout
/// 4. **Stufe 4** – manuell (UI, Phase D); hier als `source: none`.
///
/// Rechtlich bewusst zurückhaltend: kein Crawlen über die gesamte Domain,
/// keine Massenabfragen; bei CAPTCHA/Blocker/Timeout → Abbruch der
/// Netzwerk-Kaskade (kein Umgehen von Schutzmechanismen).
class EmailDiscoveryService {
  final Logger _log = Logger('EmailDiscoveryService');
  final http.Client _client;
  final Duration requestTimeout;

  EmailDiscoveryService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  /// Marker, die auf CAPTCHA-/Bot-Schutz oder einen Blocker hindeuten.
  static const List<String> _blockMarkers = [
    'captcha',
    'recaptcha',
    'hcaptcha',
    'cf-challenge',
    'cf_chl',
    'access denied',
    'unusual traffic',
    'verify you are human',
    'are you a human',
    'robot check',
    'blocked',
  ];

  /// Link-Texte/-Pfade, die als Kontaktseite gelten (deutsch + englisch).
  static const List<String> _contactLinkKeywords = [
    'kontakt',
    'contact',
    'impressum',
    'karriere',
    'career',
    'careers',
  ];

  /// Stufe 1 – Adresse aus bereits gespeicherten Daten extrahieren
  /// (kein Netzwerkzugriff). Liefert `null`, wenn keine gefunden.
  String? findEmailInStoredData({
    String? company,
    String? companyAddress,
    String? jobDescription,
  }) {
    final buffer = StringBuffer();
    if (company != null && company.trim().isNotEmpty) {
      buffer.writeln(company);
    }
    if (companyAddress != null && companyAddress.trim().isNotEmpty) {
      buffer.writeln(companyAddress);
    }
    if (jobDescription != null && jobDescription.trim().isNotEmpty) {
      buffer.writeln(jobDescription);
    }
    if (buffer.isEmpty) return null;
    return firstEmailAddressRobust(buffer.toString());
  }

  /// Führt die Kaskade Stufen 1–3 aus und liefert die erste gefundene
  /// Adresse samt Fundstelle. Bei Abbruch (Blocker/Timeout) oder wenn nichts
  /// gefunden wird: `source: none` → UI springt zu Stufe 4 (manuell).
  Future<EmailDiscoveryResult> discover({
    String? company,
    String? companyAddress,
    String? jobDescription,
    required String jobUrl,
  }) async {
    // Stufe 1: gespeicherte Daten – kein Netzwerkzugriff.
    final fromStored = findEmailInStoredData(
      company: company,
      companyAddress: companyAddress,
      jobDescription: jobDescription,
    );
    if (fromStored != null) {
      return EmailDiscoveryResult(
        email: fromStored,
        source: EmailDiscoverySource.storedData,
      );
    }

    // Stufe 2: Stellenanzeige laden, mailto:-Link suchen.
    final page = await _loadDocument(jobUrl);
    if (page == null) {
      return const EmailDiscoveryResult(
        source: EmailDiscoverySource.none,
        note: 'CAPTCHA/Blocker oder Laden fehlgeschlagen – Abbruch (Stufe 4)',
      );
    }
    final fromMailto = _extractMailtoAddress(page);
    if (fromMailto != null) {
      return EmailDiscoveryResult(
        email: fromMailto,
        source: EmailDiscoverySource.mailtoLink,
        evidenceUrl: jobUrl,
      );
    }

    // Stufe 3: genau einen Kontaktlink folgen (max. 1 Zusatz-Request).
    final baseUri = Uri.tryParse(jobUrl);
    if (baseUri != null) {
      final contactUrl = _findContactLink(page, baseUri);
      if (contactUrl != null) {
        final contactPage = await _loadDocument(contactUrl);
        if (contactPage != null) {
          final onContact =
              _extractMailtoAddress(contactPage) ??
              firstEmailAddressRobust(contactPage.documentElement?.text);
          if (onContact != null) {
            return EmailDiscoveryResult(
              email: onContact,
              source: EmailDiscoverySource.contactPage,
              evidenceUrl: contactUrl,
            );
          }
        }
      }
    }

    return const EmailDiscoveryResult(source: EmailDiscoverySource.none);
  }

  /// Lädt [url] und parst das HTML. Liefert `null` bei:
  /// - HTTP-Status ungleich 200 (inkl. 403/429/503),
  /// - CAPTCHA-/Blocker-Markern im Body,
  /// - Timeout oder Netzwerkfehler.
  ///
  /// In diesen Fällen wird die Kaskade abgebrochen (kein Umgehen von
  /// Schutzmechanismen, kein weiterer Request) – Stufe 4 (manuell).
  Future<Document?> _loadDocument(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
          .timeout(requestTimeout);
      if (response.statusCode != 200 || _looksBlocked(response)) {
        _log.warning(
          'Abbruch E-Mail-Ermittlung: HTTP ${response.statusCode} '
          'bzw. Blocker erkannt für $url',
        );
        return null;
      }
      return parser.parse(response.body);
    } on TimeoutException {
      _log.warning('Timeout beim Laden von $url – Abbruch (Stufe 4)');
      return null;
    } catch (e) {
      _log.warning('Fehler beim Laden von $url: $e – Abbruch (Stufe 4)');
      return null;
    }
  }

  /// Erkennt CAPTCHA-/Bot-Schutz und Blocker an Statuscode und Body.
  bool _looksBlocked(http.Response response) {
    if (response.statusCode == 403 ||
        response.statusCode == 429 ||
        response.statusCode == 503) {
      return true;
    }
    final lower = response.body.toLowerCase();
    for (final marker in _blockMarkers) {
      if (lower.contains(marker)) {
        _log.fine('Blocker-Marker im Body gefunden: "$marker"');
        return true;
      }
    }
    return false;
  }

  /// Durchsucht [doc] nach `mailto:`-Links und liefert die erste gültige
  /// Adresse. HTML-Entities in Attributen sind durch den Parser bereits
  /// dekodiert; ein evtl. vorhandenes `?subject=...` wird abgetrennt.
  String? _extractMailtoAddress(Document doc) {
    for (final anchor in doc.querySelectorAll('a[href^="mailto:"]')) {
      final href = anchor.attributes['href'];
      if (href == null) continue;
      final address = _parseMailtoHref(href);
      if (address != null) return address;
    }
    return null;
  }

  /// Parst einen `mailto:`-Href in eine E-Mail-Adresse (ohne Query-Teil).
  String? _parseMailtoHref(String href) {
    final raw = href.substring('mailto:'.length);
    final withoutQuery = raw.split('?').first;
    if (withoutQuery.isEmpty) return null;
    // `+` bleibt erhalten, `%40` → `@`, Komma-Listen werden nicht übernommen.
    final decoded = Uri.decodeFull(withoutQuery);
    final first = decoded.split(',').first.trim();
    return isValidEmail(first) ? first : null;
  }

  /// Sucht im Dokument den ersten Kontakt-Link (Text **oder** Pfad matcht
  /// `Kontakt`/`Impressum`/`Karriere` bzw. engl. Pendants) und löst ihn gegen
  /// [baseUri] auf. `mailto:`- und Nicht-http(s)-Links werden übersprungen.
  String? _findContactLink(Document doc, Uri baseUri) {
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final text = anchor.text.trim().toLowerCase();
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      final hrefLower = href.toLowerCase();
      if (hrefLower.startsWith('mailto:')) continue;
      final matches =
          _contactLinkKeywords.any((k) => text.contains(k)) ||
          _contactLinkKeywords.any((k) => hrefLower.contains('/$k'));
      if (!matches) continue;
      try {
        final resolved = baseUri.resolve(href);
        if (resolved.scheme != 'http' && resolved.scheme != 'https') {
          continue;
        }
        _log.fine('Kontaktseite gefunden: $resolved (Text: "$text")');
        return resolved.toString();
      } catch (_) {
        // Ungültige URL – nächsten Kandidaten versuchen.
      }
    }
    return null;
  }

  void dispose() {
    _client.close();
  }
}
