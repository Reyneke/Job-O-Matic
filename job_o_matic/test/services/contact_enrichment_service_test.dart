import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:job_o_matic/data/services/api/api_client.dart';
import 'package:job_o_matic/data/services/api/api_key_service.dart';
import 'package:job_o_matic/data/services/api/ba_api_service.dart';
import 'package:job_o_matic/data/services/api/ba_contact_resolver.dart';
import 'package:job_o_matic/data/services/email/contact_enrichment_service.dart';
import 'package:job_o_matic/data/services/email/email_discovery_service.dart';
import 'package:job_o_matic/models/application.dart';

/// Batch-Kontakt-Anreicherung über die vorhandene Kaskade (doc/plan/17).
/// Alle Requests laufen gegen MockClients (kein echtes HTTP). Bewusst
/// `enableJitter: false` + `minDelayPerHost: Duration.zero`, damit die
/// Höflichkeits-Verzögerung die Tests nicht verlangsamt.
void main() {
  const baUrl = 'https://www.arbeitsagentur.de/jobsuche/job/'
      '12265-487930_JB5205113-S';

  Application app({
    int id = 1,
    required String url,
    String? description,
    String? emailAddress,
  }) =>
      Application(
        id: id,
        jobTitle: 'Job $id',
        company: 'Firma GmbH',
        jobUrl: url,
        jobDescription: description,
        createdAt: DateTime(2026, 1, 1),
        emailAddress: emailAddress,
      );

  BaContactResolver resolverWith(Map<String, dynamic> detailsJson,
      {EmailDiscoveryService? discovery}) {
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
    return BaContactResolver(
      baService: BaApiService(client: apiClient),
      discovery: discovery ??
          EmailDiscoveryService(
            client: MockClient((request) async => http.Response('', 200)),
          ),
    );
  }

  EmailDiscoveryService discoveryWith(String html) => EmailDiscoveryService(
        client: MockClient((request) async => http.Response(html, 200)),
      );

  /// Ein Discovery, das jede Netzwerk-Anfrage als Fehler meldet – zum
  /// Nachweis, dass im BA-Beschreibungs-Fall kein Request abgesetzt wird.
  EmailDiscoveryService discoveryThatFails() => EmailDiscoveryService(
        client: MockClient((request) async {
          throw StateError('Unerwarteter Netzwerkzugriff auf ${request.url}');
        }),
      );

  ContactEnrichmentService makeService({
    required BaContactResolver baResolver,
    required EmailDiscoveryService discovery,
  }) =>
      ContactEnrichmentService(
        baResolver: baResolver,
        discovery: discovery,
        minDelayPerHost: Duration.zero,
        enableJitter: false,
      );

  Map<String, dynamic> baDetails({
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
    };
    if (externalUrl != null) {
      map['externeURL'] = externalUrl;
      map['allianzpartnerName'] = 'get in GmbH';
    }
    if (website != null) map['arbeitgeberdarstellungUrl'] = website;
    return map;
  }

  group('ContactEnrichmentService', () {
    test('BA-Job: E-Mail aus Beschreibung, kein Netzwerkzugriff', () async {
      final service = makeService(
        baResolver: resolverWith(
          baDetails(description: 'Bewerbung bitte an hr@firma.de senden.'),
        ),
        discovery: discoveryThatFails(),
      );

      final outcomes = await service.enrich([
        app(url: baUrl, description: 'Ihr Ansprechpartner: Frau Muster'),
      ]);

      expect(outcomes, hasLength(1));
      final o = outcomes.single;
      expect(o.found, isTrue);
      expect(o.email, 'hr@firma.de');
      expect(o.emailSource, 'description');
      expect(o.evidenceUrl, isNull);
      expect(o.contactPerson, 'Frau Muster');
    });

    test('BA-Job: externe Anzeige -> Quelle + Beleg-URL', () async {
      const external = 'https://www.get-in-it.de/jobsuche/p201881';
      final service = makeService(
        baResolver: resolverWith(
          baDetails(
            description: 'Wir freuen uns auf Ihre Bewerbung.',
            externalUrl: external,
          ),
          discovery: EmailDiscoveryService(
            client: MockClient((request) async => http.Response(
                '<html><a href="mailto:jobs@firma.de">Bewerben</a></html>',
                200)),
          ),
        ),
        discovery: discoveryThatFails(),
      );

      final o = (await service.enrich([app(url: baUrl)])).single;

      expect(o.found, isTrue);
      expect(o.email, 'jobs@firma.de');
      expect(o.emailSource, 'externalJobPage');
      expect(o.evidenceUrl, external);
    });

    test('generischer Job: mailto -> Quelle mailtoLink + Beleg = Job-URL',
        () async {
      const url = 'https://jobs.firma.de/position/1';
      final service = makeService(
        baResolver: resolverWith(baDetails(description: 'unbenutzt')),
        discovery: discoveryWith(
          '<html><a href="mailto:bewerbung@firma.de">Jetzt bewerben</a></html>',
        ),
      );

      final o = (await service.enrich([app(id: 7, url: url)])).single;

      expect(o.found, isTrue);
      expect(o.email, 'bewerbung@firma.de');
      expect(o.emailSource, 'mailtoLink');
      expect(o.evidenceUrl, url);
    });

    test('überspringt Bewerbungen mit vorhandener Adresse (force=false)',
        () async {
      final service = makeService(
        baResolver: resolverWith(baDetails(description: 'unbenutzt')),
        discovery: discoveryThatFails(),
      );

      final outcomes = await service.enrich([
        app(id: 1, url: baUrl, emailAddress: 'schon@da.de'),
        app(id: 2, url: baUrl),
      ]);

      expect(outcomes, hasLength(1));
      expect(service.stats.skipped, 1);
      expect(service.stats.attempted, 1);
    });

    test('Blocker-Abbruch (HTTP 403) zählt als blocked, kein Treffer',
        () async {
      const url = 'https://gesperrt.de/job';
      final service = makeService(
        baResolver: resolverWith(baDetails(description: 'unbenutzt')),
        discovery: EmailDiscoveryService(
          client: MockClient((request) async => http.Response('denied', 403)),
        ),
      );

      final o = (await service.enrich([app(url: url)])).single;

      expect(o.found, isFalse);
      expect(o.note, contains('Blocker'));
      expect(service.stats.blocked, 1);
      expect(service.stats.found, 0);
    });

    test('Statistik zählt Treffer je Quelle (Session)', () async {
      final service = makeService(
        baResolver: resolverWith(
          baDetails(description: 'Bewerbung an a@firma.de bitte hier.'),
        ),
        discovery: discoveryWith(
          '<html><a href="mailto:b@firma.de">Bewerben</a></html>',
        ),
      );

      // Zwei BA-Treffer aus der Beschreibung.
      await service.enrich([app(id: 1, url: baUrl), app(id: 2, url: baUrl)]);
      // Ein generischer mailto-Treffer.
      await service.enrich([app(id: 3, url: 'https://x.de/job')]);

      final stats = service.stats;
      expect(stats.attempted, 3);
      expect(stats.found, 3);
      expect(stats.bySource['description'], 2);
      expect(stats.bySource['mailtoLink'], 1);
    });
  });
}
