import 'package:logging/logging.dart';

import 'cover_letter_ai_service.dart';
import '../../../models/application.dart';
import '../../../models/cv_data.dart';

/// Probiert mehrere KI-Anbieter der Reihe nach aus (Fallback-Kette).
///
/// Reihenfolge laut doc/plan/13-Anschreiben-KI.md:
/// **Gemini → Mistral → Groq**. Schlägt einer fehl (Kontingent erschöpft,
/// API-Ausfall, kein Key konfiguriert), wird automatisch der nächste
/// probiert.
///
/// Wirft eine [CoverLetterAiException], wenn ALLE Anbieter fehlschlagen –
/// der Aufrufer fällt dann auf die Template-Generierung zurück.
class FallbackCoverLetterAiService implements CoverLetterAiService {
  final Logger _log = Logger('FallbackCoverLetterAiService');

  final List<CoverLetterAiService> _services;

  FallbackCoverLetterAiService(List<CoverLetterAiService> services)
      : _services = List.unmodifiable(services);

  /// Die Kette in Versuch-Reihenfolge.
  List<CoverLetterAiService> get services => _services;

  @override
  String get providerName =>
      'Fallback-Kette (${_services.map((s) => s.providerName).join(' → ')})';

  @override
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  }) async {
    if (_services.isEmpty) {
      throw const CoverLetterAiException(
        'Fallback-Kette enthält keinen Anbieter.',
      );
    }

    final errors = <String>[];
    for (final service in _services) {
      try {
        return await service.generateCoverLetter(
          cvData: cvData,
          application: application,
        );
      } on CoverLetterAiException catch (e) {
        _log.warning('${service.providerName} fehlgeschlagen: ${e.message}');
        errors.add('${service.providerName}: ${e.message}');
      }
      // Andere Exceptions (Programmfehler) werden bewusst NICHT abgefangen
      // und propagieren – sie sind keine erwartbaren Anbieter-Ausfälle.
    }

    throw CoverLetterAiException(
      'Alle KI-Anbieter fehlgeschlagen:\n${errors.join('\n')}',
    );
  }
}

