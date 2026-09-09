import 'package:flutter_test/flutter_test.dart';
import 'package:job_o_matic/data/services/email/contact_person_utils.dart';

/// Ansprechpartner-Extraktion (doc/plan/17 + offener Punkt in 16). Best
/// effort – erwartet werden die typischen deutschen Formulierungen.
void main() {
  group('firstContactPersonIn', () {
    test('Ansprechpartner mit Doppelpunkt', () {
      expect(
        firstContactPersonIn('Ansprechpartner: Frau Muster'),
        'Frau Muster',
      );
    });

    test('Ansprechpartnerin + „ist“', () {
      expect(
        firstContactPersonIn('Ihr Ansprechpartnerin ist Herr Max Mustermann.'),
        'Herr Max Mustermann',
      );
    });

    test('Kontakt mit zweiteiligem Namen', () {
      expect(
        firstContactPersonIn('Kontakt: Herr Meier-Schmidt'),
        'Herr Meier-Schmidt',
      );
    });

    test('wenden Sie sich an', () {
      expect(
        firstContactPersonIn('Bei Fragen wenden Sie sich an Frau Schmidt.'),
        'Frau Schmidt',
      );
    });

    test('Herrn wird auf Herr normalisiert (Akkusativ nach „an“)', () {
      expect(
        firstContactPersonIn('Bitte melden Sie sich bei Herrn Mustermann.'),
        'Herr Mustermann',
      );
    });

    test('überzähliges Komma/Tel. wird abgeschnitten', () {
      expect(
        firstContactPersonIn('Ansprechpartner: Herr Mustermann, Tel.: 0123'),
        'Herr Mustermann',
      );
    });

    test('null/leer -> null', () {
      expect(firstContactPersonIn(null), isNull);
      expect(firstContactPersonIn('   '), isNull);
      expect(firstContactPersonIn(''), isNull);
    });

    test('kein Ansprechpartner -> null (kein falscher Name)', () {
      expect(
        firstContactPersonIn('Bewerbung bitte an hr@firma.de.'),
        isNull,
      );
    });
  });
}
