import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:job_o_matic/data/services/email/email_address_utils.dart';
import 'package:job_o_matic/data/services/email/email_discovery_service.dart';

/// Phase C - E-Mail-Adress-Ermittlung (Kaskade Stufen 1-3) + RFC-5322-nahe
/// Validierung. Alle Netzwerk-Tests laufen gegen MockClient (kein echtes HTTP).
void main() {
  group('email_address_utils', () {
    test('isValidEmail akzeptiert gueltige Adressen', () {
      expect(isValidEmail('hr@firma.de'), isTrue);
      expect(isValidEmail('max.mustermann+job@example.co.uk'), isTrue);
      expect(isValidEmail('name_tag@sub.domain.example'), isTrue);
    });

    test('isValidEmail lehnt ungueltige Adressen ab', () {
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('keine-adresse'), isFalse);
      expect(isValidEmail('hr@firma'), isFalse); // keine TLD
      expect(isValidEmail('@firma.de'), isFalse);
      expect(isValidEmail('hr@'), isFalse);
      expect(isValidEmail('hr@firma..de'), isFalse);
      expect(isValidEmail('  hr@firma.de  '), isTrue); // getrimmt
    });

    test('firstEmailAddressIn extrahiert Adresse aus Fliesstext', () {
      expect(
        firstEmailAddressIn('Kontakt: hr@firma.de. Vielen Dank!'),
        'hr@firma.de',
      );
      expect(firstEmailAddressIn('Bewerbung an jobs(at)firma.de'), isNull);
      expect(firstEmailAddressIn(null), isNull);
    });
  });

  group('EmailDiscoveryService - Stufe 1 (lokale Daten)', () {
    test('findet Adresse in companyAddress/jobDescription ohne HTTP', () async {
      var requests = 0;
      final service = EmailDiscoveryService(
        client: MockClient((_) async {
          requests++;
          return http.Response('nicht erreichbar', 500);
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(
        companyAddress: 'Musterweg 1, 10115 Berlin',
        jobDescription: 'Bewerbungen bitte an jobs@musterfirma.de senden.',
        jobUrl: 'https://example.com/stelle/1',
      );

      expect(result.found, isTrue);
      expect(result.email, 'jobs@musterfirma.de');
      expect(result.source, EmailDiscoverySource.storedData);
      expect(requests, 0); // Stufe 1 macht keinen Netzwerkzugriff
    });

    test('liefert null, wenn keine Adresse in den Daten steckt', () {
      final service = EmailDiscoveryService(
        client: MockClient((_) async {
          return http.Response('', 500);
        }),
      );
      expect(
        service.findEmailInStoredData(
          companyAddress: 'Musterweg 1',
          jobDescription: 'Keine Kontaktdaten vorhanden.',
        ),
        isNull,
      );
    });
  });

  group('EmailDiscoveryService - Stufe 2 (mailto-Link der Anzeige)', () {
    test('findet mailto-Adresse auf der Stellenanzeige', () async {
      final service = EmailDiscoveryService(
        client: MockClient((request) async {
          return http.Response(
            '<html><body>'
            '<h1>Flutter-Entwickler</h1>'
            '<a href="mailto:hr@firma.de">Jetzt bewerben</a>'
            '</body></html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(jobUrl: 'https://firma.de/jobs/1');

      expect(result.found, isTrue);
      expect(result.email, 'hr@firma.de');
      expect(result.source, EmailDiscoverySource.mailtoLink);
    });

    test('dekodiert HTML-Entities und schneidet ?subject ab', () async {
      final service = EmailDiscoveryService(
        client: MockClient((_) async {
          return http.Response(
            '<html><body>'
            '<a href="mailto:info&#64;firma.de?subject=Bewerbung">Mail</a>'
            '</body></html>',
            200,
          );
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(jobUrl: 'https://firma.de/jobs/1');
      expect(result.email, 'info@firma.de');
      expect(result.source, EmailDiscoverySource.mailtoLink);
    });
  });

  group('EmailDiscoveryService - Stufe 3 (eine Kontaktseite)', () {
    test('folgt genau einem Kontaktlink und findet dort die Adresse', () async {
      final requestedPaths = <String>[];
      final service = EmailDiscoveryService(
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path == '/jobs/1') {
            return http.Response(
              '<html><body>'
              '<a href="/kontakt">Kontakt</a>'
              '</body></html>',
              200,
            );
          }
          if (request.url.path == '/kontakt') {
            return http.Response(
              '<html><body>'
              '<a href="mailto:bewerbung@firma.de">E-Mail</a>'
              '</body></html>',
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(jobUrl: 'https://firma.de/jobs/1');

      expect(result.found, isTrue);
      expect(result.email, 'bewerbung@firma.de');
      expect(result.source, EmailDiscoverySource.contactPage);
      expect(requestedPaths, ['/jobs/1', '/kontakt']); // max. 1 Zusatz-Request
    });

    test('keine Adresse und kein Kontaktlink -> none', () async {
      final service = EmailDiscoveryService(
        client: MockClient((_) async {
          return http.Response(
            '<html><body><h1>Keine Kontaktdaten</h1></body></html>',
            200,
          );
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(jobUrl: 'https://firma.de/jobs/1');
      expect(result.found, isFalse);
      expect(result.source, EmailDiscoverySource.none);
    });
  });
  group('EmailDiscoveryService - Abbruch bei CAPTCHA/Blocker/Timeout', () {
    test(
      'CAPTCHA-Marker im Body bricht die Kaskade ab (kein Kontakt-Follow)',
      () async {
        final requestedPaths = <String>[];
        final service = EmailDiscoveryService(
          client: MockClient((request) async {
            requestedPaths.add(request.url.path);
            return http.Response(
              '<html><body>'
              '<div class="g-recaptcha">Bitte Captcha loesen</div>'
              '<a href="/kontakt">Kontakt</a>'
              '</body></html>',
              200,
            );
          }),
        );
        addTearDown(service.dispose);

        final result = await service.discover(
          jobUrl: 'https://firma.de/jobs/1',
        );

        expect(result.found, isFalse);
        expect(result.source, EmailDiscoverySource.none);
        // Abbruch nach dem ersten Request - kein Kontakt-Follow, kein Umgehen.
        expect(requestedPaths, ['/jobs/1']);
      },
    );

    test('HTTP 403 (Blocker) -> none ohne weiteren Request', () async {
      var requests = 0;
      final service = EmailDiscoveryService(
        client: MockClient((_) async {
          requests++;
          return http.Response('Forbidden', 403);
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(jobUrl: 'https://firma.de/jobs/1');
      expect(result.found, isFalse);
      expect(result.source, EmailDiscoverySource.none);
      expect(requests, 1);
    });

    test('Timeout -> none (kein stilles Haengen)', () async {
      final service = EmailDiscoveryService(
        requestTimeout: const Duration(milliseconds: 50),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.Response('<html></html>', 200);
        }),
      );
      addTearDown(service.dispose);

      final result = await service.discover(jobUrl: 'https://firma.de/jobs/1');
      expect(result.found, isFalse);
      expect(result.source, EmailDiscoverySource.none);
    });
  });
}
