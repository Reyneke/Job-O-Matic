import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/api/ba_contact_resolver.dart';
import 'package:job_o_matic/data/services/api/ba_api_service.dart';
import 'package:job_o_matic/data/services/email/email_discovery_service.dart';

/// Kontakt-Ermittlung zu BA-Anzeigen (doc/plan/16-Jobsuche-BA.md, „Kaskade“).
///
/// Bewusst KEIN Captcha-Umgehen / KEIN Scraping der BA-HTML-Seite: getestet
/// werden (1) E-Mail aus der Beschreibung, (2) die externe Anzeige als
/// Netzwerk-Quelle und (3) die Sperre arbeitsagentur.de. Alle Requests laufen
/// gegen MockClients (kein echtes HTTP).
void main() {
  group('BaContactResolver', () {
    /// Erstellt einen [BaApiService], dessen `jobdetails`-Antwort [detailsJson]
    /// liefert.
    BaApiService baService(Map<String, dynamic> detailsJson) {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(detailsJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        logger: Logger('Test'),
        keyService: ApiKeyService(),
        client: client,
      );
      return BaApiService(client: apiClient);
    }

    /// Erstellt einen [EmailDiscoveryService], der [html] für jede Anfrage
    /// zurückgibt.
    EmailDiscoveryService discovery(String html) {
      final client = MockClient((request) async => http.Response(html, 200));
      return EmailDiscoveryService(client: client);
    }

    /// Ein Discovery-Service, der jeden Netzwerkzugriff als Fehler meldet –
    /// zum Nachweis, dass bei Beschreibungs-Treffern bzw. gesperrten Hosts
    /// KEIN Request abgesetzt wird.
    EmailDiscoveryService discoveryThatFails() {
      final client = MockClient((request) async {
        throw StateError('Unerwarteter Netzwerkzugriff auf ${request.url}');
      });
      return EmailDiscoveryService(client: client);
    }

    test('E-Mail aus Beschreibung: kein Netzwerkzugriff', () async {
      final resolver = BaContactResolver(
        baService: baService(_details(
          description: 'Bewerbung bitte an bewerbung (at) firma (dot) de.',
        )),
        discovery: discoveryThatFails(),
      );

      final result = await resolver.resolve(refnr: '12265-487930_JB5205113-S');

      expect(result.found, isTrue);
      expect(result.email, 'bewerbung@firma.de');
      expect(result.source, BaContactSource.description);
    });

    test('externe Anzeige: Discovery läuft gegen externeURL', () async {
      const externalUrl = 'https://www.get-in-it.de/jobsuche/p201881';
      final resolver = BaContactResolver(
        baService: baService(_details(
          description: 'Wir freuen uns auf Ihre Bewerbung.',
          externalUrl: externalUrl,
        )),
        discovery: discovery(
          '<html><body><a href="mailto:jobs@firma.de">Bewerben</a></body></html>',
        ),
      );

      final result = await resolver.resolve(refnr: '13644-201881-S');

      expect(result.found, isTrue);
      expect(result.email, 'jobs@firma.de');
      expect(result.source, BaContactSource.externalJobPage);
      expect(result.externalUrl, externalUrl);
    });

    test('Arbeitgeber-Website als Fallback-Quelle', () async {
      const website = 'https://www.firma.de';
      final resolver = BaContactResolver(
        baService: baService(_details(
          description: 'Ohne Kontaktangabe.',
          website: website,
        )),
        discovery: discovery(
          '<html><body><a href="mailto:bewerbung@firma.de">Jetzt bewerben</a></body></html>',
        ),
      );

      final result = await resolver.resolve(refnr: '13334-00005f66d7a001-S');

      expect(result.found, isTrue);
      expect(result.source, BaContactSource.employerWebsite);
    });

    test('arbeitsagentur.de wird nie über die HTML-Seite angefragt', () async {
      final resolver = BaContactResolver(
        baService: baService(_details(
          description: 'Details ohne E-Mail.',
          externalUrl: 'https://www.arbeitsagentur.de/jobsuche/job/x',
        )),
        discovery: discoveryThatFails(),
      );

      final result = await resolver.resolve(refnr: '12265-487930_JB5205113-S');

      expect(result.found, isFalse);
      expect(result.source, BaContactSource.none);
      expect(result.externalUrl,
          'https://www.arbeitsagentur.de/jobsuche/job/x');
    });

    test('kein Treffer: manueller Fallback mit Adresse', () async {
      final resolver = BaContactResolver(
        baService: baService(_details(description: 'Keine Kontaktdaten.')),
        discovery: discoveryThatFails(),
      );

      final result = await resolver.resolve(refnr: '12265-487930_JB5205113-S');

      expect(result.found, isFalse);
      expect(result.source, BaContactSource.none);
      expect(result.note, contains('manuell'));
      expect(result.address, 'Jüdenstr. 31, 13597 Berlin');
    });
  });

  group('baRefnrFromJobUrl / isBaJobUrl', () {
    test('erkennt BA-Jobsuche-URL und extrahiert die refnr', () {
      const url =
          'https://www.arbeitsagentur.de/jobsuche/job/'
          '12265-487930_JB5205113-S';
      expect(isBaJobUrl(url), isTrue);
      expect(baRefnrFromJobUrl(url), '12265-487930_JB5205113-S');
    });

    test('fremder Host (z. B. externe Anzeige) -> null / false', () {
      expect(baRefnrFromJobUrl('https://www.get-in-it.de/jobsuche/p201881'),
          isNull);
      expect(isBaJobUrl('https://www.get-in-it.de/jobsuche/p201881'), isFalse);
    });

    test('arbeitsagentur.de ohne /job/-Segment -> null', () {
      expect(baRefnrFromJobUrl('https://www.arbeitsagentur.de/startseite'),
          isNull);
      expect(baRefnrFromJobUrl('https://www.arbeitsagentur.de'), isNull);
      expect(isBaJobUrl('https://www.arbeitsagentur.de/startseite'), isTrue);
    });

    test('ungültige URL -> null', () {
      expect(baRefnrFromJobUrl('not a url'), isNull);
    });
  });
}

/// Baut eine realistische (gekürzte) `jobdetails`-Antwort der BA.
Map<String, dynamic> _details({
  required String description,
  String? externalUrl,
  String? website,
}) {
  final map = <String, dynamic>{
    'stellenangebotsart': 'ARBEIT',
    'stellenangebotsTitel': 'Flutter-Entwickler (m/w/d)',
    'stellenangebotsBeschreibung': description,
    'firma': 'Beispiel GmbH',
    'referenznummer': '12265-487930_JB5205113-S',
    'stellenlokationen': [
      {
        'adresse': {
          'strasseHausnummer': 'Jüdenstr. 31',
          'plz': '13597',
          'ort': 'Berlin',
          'region': 'Berlin',
          'land': 'Deutschland',
        }
      }
    ],
  };
  if (externalUrl != null) {
    map['externeURL'] = externalUrl;
    map['allianzpartnerName'] = 'get in GmbH';
  }
  if (website != null) {
    map['arbeitgeberdarstellungUrl'] = website;
  }
  return map;
}
