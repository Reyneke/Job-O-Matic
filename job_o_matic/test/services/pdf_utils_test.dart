import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:job_o_matic/data/services/pdf/pdf_utils.dart';

void main() {
  group('PdfUtils - DIN 5008 Konformität', () {
    test('dateFormatFull formatiert als TT.MM.JJJJ', () {
      final date = DateTime(2026, 8, 21);
      expect(PdfUtils.dateFormatFull.format(date), '21.08.2026');
    });

    test('dateFormatMonthYear formatiert als MM.JJJJ', () {
      final date = DateTime(2026, 8, 21);
      expect(PdfUtils.dateFormatMonthYear.format(date), '08.2026');
    });

    test('Seitenränder entsprechen DIN 5008', () {
      // 1 mm = 2.8346 pt
      // Links: 25mm ≈ 71pt, Rechts: 20mm ≈ 57pt, Oben/Unten: 20mm ≈ 57pt
      expect(PdfUtils.marginLeft, closeTo(71, 1));
      expect(PdfUtils.marginRight, closeTo(57, 1));
      expect(PdfUtils.marginTop, closeTo(57, 1));
      expect(PdfUtils.marginBottom, closeTo(57, 1));
    });

    test('pageFormat verwendet A4 mit DIN-5008-Rändern', () {
      final format = PdfUtils.pageFormat;
      expect(format.width, 595);
      expect(format.height, 842);
      expect(format.marginLeft, PdfUtils.marginLeft);
      expect(format.marginRight, PdfUtils.marginRight);
      expect(format.marginTop, PdfUtils.marginTop);
      expect(format.marginBottom, PdfUtils.marginBottom);
    });

    test('buildFooter zeigt nichts auf Seite 1', () {
      final context = _MockContext(pageNumber: 1, pagesCount: 3);
      final widget = PdfUtils.buildFooter(context);
      expect(widget, isA<pw.SizedBox>());
    });

    test('buildFooter zeigt "Seite X von Y" ab Seite 2', () {
      final context = _MockContext(pageNumber: 2, pagesCount: 3);
      final widget = PdfUtils.buildFooter(context);
      expect(widget, isA<pw.Align>());
    });
  });
}

/// Mock für pw.Context, da die echte Klasse schwer zu instanziieren ist.
class _MockContext implements pw.Context {
  _MockContext({required this.pageNumber, required this.pagesCount});

  @override
  final int pageNumber;

  @override
  final int pagesCount;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}