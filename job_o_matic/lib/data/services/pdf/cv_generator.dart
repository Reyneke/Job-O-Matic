import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'pdf_utils.dart';
import '../../../models/cv_data.dart';

/// Generator für den Lebenslauf (CV) im PDF-Format.
class CvGenerator {
  static const _labelWidth = 100.0;
  static const _fontSizeLabel = 10.0;
  static const _fontSizeValue = 10.0;
  static const _fontSizeSection = 14.0;
  static const _fontSizeTitle = 22.0;
  static const _fontSizePosition = 11.0;
  static const _fontSizeDate = 9.0;
  static const _fontSizeCompany = 10.0;

  pw.MultiPage build({required CvData cvData}) {
    return pw.MultiPage(
      pageFormat: PdfUtils.pageFormat,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => [
        // Überschrift
        pw.Header(
          level: 0,
          child: pw.Text(
            'Lebenslauf',
            style: pw.TextStyle(
              fontSize: _fontSizeTitle,
              fontWeight: pw.FontWeight.bold,
              color: PdfUtils.primaryColor,
            ),
          ),
        ),
        pw.SizedBox(height: 8),

        // Persönliche Daten
        pw.Header(
          level: 1,
          child: pw.Text('Persönliche Daten',
              style: pw.TextStyle(
                  fontSize: _fontSizeSection,
                  fontWeight: pw.FontWeight.bold)),
        ),
        _buildInfoRow('Name', cvData.personalData.fullName),
        if (cvData.personalData.email != null)
          _buildInfoRow('E-Mail', cvData.personalData.email!),
        if (cvData.personalData.phone != null)
          _buildInfoRow('Telefon', cvData.personalData.phone!),
        pw.SizedBox(height: 12),

        // Berufserfahrung
        if (cvData.workExperience.isNotEmpty) ...[
          pw.Header(
            level: 1,
            child: pw.Text('Berufserfahrung',
                style: pw.TextStyle(
                    fontSize: _fontSizeSection,
                    fontWeight: pw.FontWeight.bold)),
          ),
          ...cvData.workExperience.map(_buildExperienceEntry),
          pw.SizedBox(height: 12),
        ],

        // Ausbildung
        if (cvData.education.isNotEmpty) ...[
          pw.Header(
            level: 1,
            child: pw.Text('Ausbildung',
                style: pw.TextStyle(
                    fontSize: _fontSizeSection,
                    fontWeight: pw.FontWeight.bold)),
          ),
          ...cvData.education.map(_buildEducationEntry),
          pw.SizedBox(height: 12),
        ],

        // Kenntnisse
        if (cvData.skills.isNotEmpty) ...[
          pw.Header(
            level: 1,
            child: pw.Text('Kenntnisse',
                style: pw.TextStyle(
                    fontSize: _fontSizeSection,
                    fontWeight: pw.FontWeight.bold)),
          ),
          ...cvData.skills.map(_buildSkillEntry),
        ],
      ],
    );
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: _labelWidth,
          child: pw.Text('$label:',
              style: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: _fontSizeLabel,
                  color: PdfColors.grey700)),
        ),
        pw.Expanded(
          child: pw.Text(value,
              style: const pw.TextStyle(fontSize: _fontSizeValue)),
        ),
      ],
    );
  }

  pw.Widget _buildExperienceEntry(WorkExperience exp) {
    final dateStr =
        '${_formatDate(exp.startDate)} – ${exp.isCurrent ? 'heute' : _formatDate(exp.endDate!)}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(exp.position,
                style: const pw.TextStyle(
                    fontSize: _fontSizePosition,
                    fontWeight: pw.FontWeight.bold)),
            pw.Text(dateStr,
                style: const pw.TextStyle(
                    fontSize: _fontSizeDate, color: PdfColors.grey600)),
          ],
        ),
        pw.Text(exp.company,
            style: const pw.TextStyle(
                fontSize: _fontSizeCompany, color: PdfColors.grey700)),
        if (exp.description != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(exp.description!,
                style: const pw.TextStyle(fontSize: _fontSizeValue)),
          ),
      ],
    );
  }

  pw.Widget _buildEducationEntry(Education edu) {
    final dateStr =
        '${_formatDate(edu.startDate)} – ${edu.endDate != null ? _formatDate(edu.endDate!) : 'laufend'}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(edu.degree,
                style: const pw.TextStyle(
                    fontSize: _fontSizePosition,
                    fontWeight: pw.FontWeight.bold)),
            pw.Text(dateStr,
                style: const pw.TextStyle(
                    fontSize: _fontSizeDate, color: PdfColors.grey600)),
          ],
        ),
        pw.Text(edu.institution,
            style: const pw.TextStyle(
                fontSize: _fontSizeCompany, color: PdfColors.grey700)),
        if (edu.field != null)
          pw.Text(edu.field!,
              style: const pw.TextStyle(
                  fontSize: _fontSizeValue, color: PdfColors.grey600)),
      ],
    );
  }

  pw.Widget _buildSkillEntry(Skill skill) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(skill.name,
                style: const pw.TextStyle(fontSize: _fontSizeValue)),
          ),
          pw.Expanded(
            child: pw.Container(
              height: 12,
              decoration: pw.BoxDecoration(
                color: PdfColors.grey300,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: (skill.proficiency * 100).clamp(0, 100) *
                        1.5, // 150 * proficiency
                    height: 12,
                    decoration: pw.BoxDecoration(
                      color: _skillColor(skill.proficiency),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text('${(skill.proficiency * 100).round()}%',
              style: const pw.TextStyle(
                  fontSize: _fontSizeDate, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  PdfColor _skillColor(double proficiency) {
    if (proficiency >= 0.7) return PdfColors.green600;
    if (proficiency >= 0.4) return PdfColors.orange600;
    return PdfColors.red600;
  }

  String _formatDate(DateTime date) {
    return DateFormat('MM/yyyy').format(date);
  }
}