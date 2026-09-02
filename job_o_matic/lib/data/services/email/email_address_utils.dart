/// E-Mail-Adress-Helfer: RFC-5322-nahe Validierung + Extraktion.
///
/// Bewusst KEINE vollständige RFC-5322-Parser-Implementierung (dafür wäre ein
/// richtiger E-Mail-Parser nötig), sondern eine praxisnahe Prüfung, die die
/// gängigen Bewerbungs-/Kontakt-Adressen akzeptiert und offensichtlich
/// ungültige ablehnt. Wird von `EmailDiscoveryService` (Stufe 1–3) und vom
/// Versand-Screen (manuelle Eingabe, Phase D) verwendet.
library;

/// Findet E-Mail-Adressen in Rohtext/HTML (Local-Part mit `+`, Domains mit
/// mindestens einem Punkt – keine `localhost`-Treffer).
final RegExp emailAddressRegex = RegExp(
  r"[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+"
  r"@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
  r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+",
);

/// Prüft, ob [input] eine gültige E-Mail-Adresse ist (RFC-5322-nah).
///
/// Der gesamte String muss eine Adresse sein (keine umgebenden Zeichen);
/// Groß-/Kleinschreibung ist im Local-Part erlaubt, wird hier aber nicht
/// bewertet. Leerstring und >254 Zeichen sind ungültig.
bool isValidEmail(String input) {
  final value = input.trim();
  if (value.isEmpty || value.length > 254) return false;
  final match = emailAddressRegex.firstMatch(value);
  if (match == null) return false;
  return match.start == 0 && match.end == value.length;
}

/// Liefert die erste gültig aussehende E-Mail-Adresse in [text] oder `null`.
///
/// Nutzt [emailAddressRegex] und verhindert, dass Trailing-Zeichen wie
/// schließende Klammern oder Satzzeichen (`)`, `,`, `;`) Teil des Treffers
/// werden – die Regex-Struktur (Domain-Endet mit Buchstaben-Label) schneidet
/// diese bereits ab.
String? firstEmailAddressIn(String? text) {
  if (text == null || text.isEmpty) return null;
  final match = emailAddressRegex.firstMatch(text);
  if (match == null) return null;
  final candidate = match.group(0)!.trim();
  return isValidEmail(candidate) ? candidate : null;
}
