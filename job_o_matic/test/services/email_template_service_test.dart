import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/email/email_template_service.dart';

/// Phase-Erweiterung: HTML-Entities (&#x2F; etc.) in gescrapten/API-Titeln
/// duerfen nicht im E-Mail-Betreff/-Body landen.
void main() {
  group('EmailTemplateService - Entity-Bereinigung', () {
    final service = EmailTemplateService();

    test('Betreff dekodiert &#x2F; und &amp;', () {
      final subject = service.buildSubject(
        position:
            'Senior Flutter Developer &#x2F; Client Engineer (m&#x2F;f&#x2F;d)',
        company: 'Bliq &amp; Co',
      );
      expect(
        subject,
        'Bewerbung als Senior Flutter Developer / '
        'Client Engineer (m/f/d)',
      );
      expect(subject.contains('&#x2F;'), isFalse);
      expect(subject.contains('&amp;'), isFalse);
    });

    test('Body verwendet bereinigten Jobtitel', () {
      final body = service.buildApplicationBody(
        position: 'Flutter &#x2F; Rust Developer',
        company: 'Acme GmbH',
        fullName: 'Max Mustermann',
      );
      expect(body.contains('&#x2F;'), isFalse);
      expect(body, contains('Flutter / Rust Developer'));
    });

    test('lässt Titel ohne Entities unverändert', () {
      const position = 'Flutter Developer (m/w/d)';
      final subject = service.buildSubject(position: position, company: 'Acme');
      expect(subject, contains(position));
    });
  });
}
