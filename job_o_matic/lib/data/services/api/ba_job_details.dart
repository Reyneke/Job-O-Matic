/// Details einer BA-Stellenanzeige (Antwort von `/jobdetails/{base64(refnr)}`).
///
/// Verifizierte Felder (Stand 2026-09-07): Die `jobdetails`-Antwort enthält
/// KEIN strukturiertes Kontakt-/E-Mail-Feld. Enthalten sind u. a.
/// `stellenangebotsBeschreibung`, `firma`, `stellenlokationen`,
/// `externeURL`/`allianzpartnerName` (für externe Anzeigen) und
/// `arbeitgeberKundennummerHash` (Logo). Kontaktdaten stehen – wenn überhaupt –
/// im Fließtext der Beschreibung oder auf der externen Anzeige/Arbeitgeber-
/// Website. Siehe `doc/plan/16-Jobsuche-BA.md`.
class BaJobDetails {
  final String? title;
  final String? description;
  final String? company;

  /// URL der externen Anzeige (nur bei externen/Allianz-Anzeigen gesetzt).
  final String? externalUrl;
  final String? allianzPartnerName;

  /// Arbeitgeber-Logo-Hash (für `/ct/v1/arbeitgeberlogo/{hash}`).
  final String? employerLogoHash;

  /// Arbeitgeber-Website, sofern die BA sie mitliefert.
  final String? website;

  /// Formatierte Anschriften (z. B. „Jüdenstr. 31, 13597 Berlin“).
  final List<String> addresses;

  const BaJobDetails({
    this.title,
    this.description,
    this.company,
    this.externalUrl,
    this.allianzPartnerName,
    this.employerLogoHash,
    this.website,
    this.addresses = const [],
  });

  /// Erste Adresse als einzeiliger Text oder `null`.
  String? get primaryAddress => addresses.isNotEmpty ? addresses.first : null;

  /// Tolerantes Parsen: fehlende Felder führen nicht zu einem Fehler.
  factory BaJobDetails.fromJson(Map<String, dynamic> json) {
    final locations = json['stellenlokationen'] as List<dynamic>? ?? const [];
    final addresses = <String>[];
    for (final loc in locations) {
      final map = loc as Map<String, dynamic>?;
      final adresse = map?['adresse'] as Map<String, dynamic>?;
      if (adresse == null) continue;
      final text = _formatAddress(adresse);
      if (text != null && text.isNotEmpty) {
        addresses.add(text);
      }
    }

    return BaJobDetails(
      title: json['stellenangebotsTitel'] as String?,
      description: json['stellenangebotsBeschreibung'] as String?,
      company: json['firma'] as String?,
      externalUrl: _cleanUrl(json['externeURL'] as String?),
      allianzPartnerName: json['allianzpartnerName'] as String?,
      employerLogoHash: json['arbeitgeberKundennummerHash'] as String?,
      website: _cleanUrl(json['arbeitgeberdarstellungUrl'] as String?),
      addresses: addresses,
    );
  }

  /// Baut „Straße, PLZ Ort“ – einzelne Teile nur, wenn sie vorhanden sind.
  static String? _formatAddress(Map<String, dynamic> adresse) {
    final parts = <String>[];
    final street = adresse['strasseHausnummer'] as String?;
    if (street != null && street.trim().isNotEmpty) {
      parts.add(street.trim());
    }
    final cityParts = <String>[];
    final plz = adresse['plz'] as String?;
    final ort = adresse['ort'] as String?;
    if (plz != null && plz.trim().isNotEmpty) {
      cityParts.add(plz.trim());
    }
    if (ort != null && ort.trim().isNotEmpty) {
      cityParts.add(ort.trim());
    }
    if (cityParts.isNotEmpty) {
      parts.add(cityParts.join(' '));
    }
    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  /// Entfernt Leerraum und akzeptiert nur http(s)-URLs; sonst `null`.
  static String? _cleanUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return trimmed;
  }
}
