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
/// HTML-Entities, die in gespeicherten Job-/Kontakttexten vorkommen und
/// eine E-Mail-Adresse verbergen koennen (numerisch + gaengige benannte).
final RegExp _htmlEntityRegex = RegExp(
  r'&#(\d{1,5});|&#[xX]([0-9a-fA-F]{1,4});|&commat;|&period;|&dot;',
);

/// Anti-Spam-Konstrukte fuer das '@' (z.B. 'name (at) firma.de', 'name[at]..').
final RegExp _obfuscatedAt = RegExp(
  r'\s*[\[({]\s*(?:at)\s*[\])}]\s*',
  caseSensitive: false,
);

/// Anti-Spam-Konstrukte fuer den Domain-Punkt (z.B. 'firma (dot) de').
final RegExp _obfuscatedDot = RegExp(
  r'\s*[\[({]\s*(?:dot|punkt)\s*[\])}]\s*',
  caseSensitive: false,
);

/// Leerzeichen/Zeilenumbrueche direkt um das '@' (z.B. Umbruch 'hr@\nfirma.de').
final RegExp _spaceAdjacentToAt = RegExp(r'\s*@\s*');

String _decodeHtmlEntities(String text) {
  return text.replaceAllMapped(_htmlEntityRegex, (m) {
    if (m.group(1) != null) {
      return String.fromCharCode(int.tryParse(m.group(1)!) ?? 0);
    }
    if (m.group(2) != null) {
      return String.fromCharCode(int.tryParse(m.group(2)!, radix: 16) ?? 0);
    }
    switch (m.group(0)!) {
      case '&commat;':
        return '@';
      case '&period;':
      case '&dot;':
        return '.';
      default:
        return m.group(0)!;
    }
  });
}

/// Normalisiert gaengige verdeckte/umgebrochene E-Mail-Schreibweisen, damit
/// [emailAddressRegex] sie finden kann. Liefert den (ggf. unveraenderten)
/// Text zurueck – bewusst ohne Semantik-/Volltextveraenderung, da nur auf
/// Kandidaten-Strings nach [isValidEmail] geprueft wird.
String normalizeObfuscatedEmailText(String text) {
  var t = _decodeHtmlEntities(text);
  t = t.replaceAll(_obfuscatedDot, '.');
  t = t.replaceAll(_obfuscatedAt, '@');
  t = t.replaceAll(_spaceAdjacentToAt, '@');
  return t;
}

/// Wie [firstEmailAddressIn], versucht aber zusaetzlich gaengige verdeckte
/// Schreibweisen aufzuloesen: HTML-Entities (`hr&#64;firma.de`),
/// Anti-Spam-Konstrukte (`bewerbung [at] firma.de`, `firma (dot) de`),
/// sowie Leerzeichen/Zeilenumbrueche rund um das '@'.
/// Offline/ohne Netzwerk – fuer die lokale Stufe der Adress-Kaskade.
String? firstEmailAddressRobust(String? text) {
  if (text == null || text.isEmpty) return null;
  final direct = firstEmailAddressIn(text);
  if (direct != null) return direct;
  final normalized = normalizeObfuscatedEmailText(text);
  if (normalized == text) return null;
  return firstEmailAddressIn(normalized);
}