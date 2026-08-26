import '../../../models/application.dart';
import '../../../models/cv_data.dart';

/// Signatur zum Laden eines Anbieter-API-Keys (testbar injizierbar).
typedef AiApiKeyLoader = Future<String?> Function();

/// Abstrakte Schnittstelle für KI-basierte Anschreiben-Generierung.
///
/// Konkrete Anbieter (z. B. Google Gemini, Ollama) implementieren dieses
/// Interface und sind dadurch austauschbar (siehe doc/plan/13-Anschreiben-KI.md).
///
/// Vertrag:
/// - Die Implementierung liefert **nur reinen Fließtext** (kein Markdown,
///   keine Listen, keine Überschriften) – das Layout bleibt vollständig
///   in den PDF-Generatoren.
/// - Es dürfen ausschließlich Fakten aus [cvData] und der Stellenbeschreibung
///   von [application] verwendet werden ("Erfinde keine Fakten").
abstract class CoverLetterAiService {
  /// Menschenlesbarer Name des Anbieters (z. B. "Gemini", "Ollama").
  String get providerName;

  /// Erzeugt ein Stellen-spezifisches Anschreiben als reinen Fließtext.
  ///
  /// Wirft [CoverLetterAiException], wenn keine gültige Antwort erzeugt
  /// werden konnte (Netzwerkfehler, Kontingent erschöpft, leere Antwort).
  /// Der Aufrufer entscheidet dann über den Fallback auf die
  /// Template-basierte Generierung.
  Future<String> generateCoverLetter({
    required CvData cvData,
    required Application application,
  });
}

/// Exception für Fehler bei der KI-gestützten Anschreiben-Generierung.
class CoverLetterAiException implements Exception {
  final String message;
  final Object? cause;

  const CoverLetterAiException(this.message, {this.cause});

  @override
  String toString() =>
      'CoverLetterAiException: $message${cause != null ? ' (Ursache: $cause)' : ''}';
}
