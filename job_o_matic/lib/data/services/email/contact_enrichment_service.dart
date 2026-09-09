import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';

import '../../../models/application.dart';
import '../api/ba_contact_resolver.dart';
import 'contact_person_utils.dart';
import 'email_discovery_service.dart';

/// Ergebnis der Batch-Kontakt-Anreicherung für **eine** Bewerbung
/// (doc/plan/17, „Batch-`ContactEnrichmentService`“).
class ContactEnrichmentOutcome {
  final int applicationId;
  final String jobTitle;
  final String company;

  /// Ermittelte E-Mail-Adresse (null, wenn keine gefunden/abgebrochen).
  final String? email;

  /// Persistierter Quell-Wert (`emailSource`, DB v8): einer der
  /// `EmailDiscoverySource`/`BaContactSource`-Namen oder `null`.
  final String? emailSource;

  /// Fundstelle (Beleg-URL) der ermittelten Adresse.
  final String? evidenceUrl;

  /// Best-effort-extrahierten Ansprechpartner (siehe [firstContactPersonIn]).
  final String? contactPerson;

  /// Begründung/Hinweis für die UI (Blocker, BA-Fehler, „ohne Ergebnis“ …).
  final String? note;

  const ContactEnrichmentOutcome({
    required this.applicationId,
    required this.jobTitle,
    required this.company,
    this.email,
    this.emailSource,
    this.evidenceUrl,
    this.contactPerson,
    this.note,
  });

  bool get found => email != null;
}

/// Session-Statistik der Trefferquote je Quelle (analog `BaMarketStats`,
/// doc/plan/17 „Live-Verifikation“). Bewusst in-memory seit App-Start.
class ContactEnrichmentStats {
  final int attempted;
  final int found;
  final int skipped;
  final int blocked;
  final int failed;
  final Map<String, int> bySource;

  const ContactEnrichmentStats({
    required this.attempted,
    required this.found,
    required this.skipped,
    required this.blocked,
    required this.failed,
    required this.bySource,
  });

  int get notFound => attempted - found - blocked - failed;
}

/// Batch-Kontakt-Anreicherung über die **vorhandene** Kaskade – kein neuer
/// generischer Crawler (doc/plan/17).
///
/// Nimmt eine Liste von [Application] und lässt pro Bewerbung den
/// `BaContactResolver` (BA-Jobs, URL-basiert) bzw. den `EmailDiscoveryService`
/// (generisch) laufen. Das Ergebnis wird **nicht** hier persistiert, sondern
/// als [ContactEnrichmentOutcome]-Liste zurückgegeben – die UI lässt den Nutzer
/// bestätigen und schreibt dann über `JobRepository.updateApplicationEmail`.
///
/// Höflichkeit: serielle Abarbeitung, Mindestabstand pro Host ([minDelayPerHost],
/// optional mit Jitter). Bewerbungen mit bereits gesetzter Adresse werden
/// übersprungen (außer [force]). Fehler je Bewerbung werden geloggt und der
/// Batch verarbeitet weitere Jobs (kein Abbruch als Ganzes).
class ContactEnrichmentService {
  final Logger _log = Logger('ContactEnrichmentService');
  final BaContactResolver _baResolver;
  final EmailDiscoveryService _discovery;

  /// Mindestabstand zwischen zwei Anfragen an denselben Host.
  final Duration minDelayPerHost;

  /// Zusätzliche kleine zufällige Verzögerung (0–250 ms), um Mustern zu brechen.
  final bool enableJitter;

  final Random _rand = Random();
  final Map<String, DateTime> _lastHitByHost = {};

  // Session-Statistik (in-memory, seit App-Start).
  int _attempted = 0;
  int _found = 0;
  int _skipped = 0;
  int _blocked = 0;
  int _failed = 0;
  final Map<String, int> _bySource = {};

  ContactEnrichmentService({
    required BaContactResolver baResolver,
    required EmailDiscoveryService discovery,
    this.minDelayPerHost = const Duration(milliseconds: 1200),
    this.enableJitter = true,
  })  : _baResolver = baResolver,
        _discovery = discovery;

  /// Aktuelle Session-Trefferquote.
  ContactEnrichmentStats get stats => ContactEnrichmentStats(
        attempted: _attempted,
        found: _found,
        skipped: _skipped,
        blocked: _blocked,
        failed: _failed,
        bySource: Map.unmodifiable(_bySource),
      );

  /// Führt die Batch-Anreicherung für [applications] aus (seriell).
  ///
  /// Liefert ein Outcome je **verarbeiteter** (versuchter) Bewerbung.
  /// Bewerbungen mit vorhandener Adresse werden nur mit [force] = true
  /// erneut angefragt und sonst als `skipped` gezählt (kein Outcome).
  Future<List<ContactEnrichmentOutcome>> enrich(
    List<Application> applications, {
    bool force = false,
  }) async {
    final outcomes = <ContactEnrichmentOutcome>[];
    for (final app in applications) {
      if (!force && (app.emailAddress?.trim().isNotEmpty ?? false)) {
        _skipped++;
        _log.fine('Übersprungen (Adresse vorhanden): ${app.jobTitle}');
        continue;
      }
      _attempted++;
      final outcome = await _enrichOne(app);
      outcomes.add(outcome);
      if (outcome.found) {
        _found++;
        final key = outcome.emailSource ?? 'none';
        _bySource[key] = (_bySource[key] ?? 0) + 1;
      } else if (_isBlockerAbort(outcome)) {
        _blocked++;
      }
    }
    _log.info(
      'Batch-Kontakt-Anreicherung: ${outcomes.length} verarbeitet, '
      '$_found gefunden.',
    );
    return outcomes;
  }

  Future<ContactEnrichmentOutcome> _enrichOne(Application app) async {
    final contactPerson = firstContactPersonIn(app.jobDescription);
    final refnr = baRefnrFromJobUrl(app.jobUrl);
    if (refnr != null) {
      return _enrichBa(app, refnr, contactPerson: contactPerson);
    }
    return _enrichGeneric(app, contactPerson: contactPerson);
  }

  Future<ContactEnrichmentOutcome> _enrichBa(
    Application app,
    String refnr, {
    required String? contactPerson,
  }) async {
    // Höflichkeit: die BA-Details laufen über rest.arbeitsagentur.de (REST,
    // kein HTML) – trotzdem gedrosselt, um die REST-API nicht zu überlasten.
    await _pace('rest.arbeitsagentur.de');
    try {
      final result = await _baResolver.resolve(refnr: refnr);
      if (result.email == null || !result.found) {
        return ContactEnrichmentOutcome(
          applicationId: app.id,
          jobTitle: app.jobTitle,
          company: app.company,
          contactPerson: contactPerson,
          note: result.note,
        );
      }
      return ContactEnrichmentOutcome(
        applicationId: app.id,
        jobTitle: app.jobTitle,
        company: app.company,
        email: result.email,
        emailSource: result.source.name,
        evidenceUrl: _baEvidence(result),
        contactPerson: contactPerson,
        note: result.note,
      );
    } catch (e) {
      _failed++;
      _log.warning('BA-Anreicherung fehlgeschlagen für ${app.jobTitle}: $e');
      return ContactEnrichmentOutcome(
        applicationId: app.id,
        jobTitle: app.jobTitle,
        company: app.company,
        contactPerson: contactPerson,
        note: 'BA-Fehler: $e',
      );
    }
  }

  /// Fundstellen-URL eines BA-Ergebnisses (abhängig von der Quelle).
  String? _baEvidence(BaContactResolution result) {
    switch (result.source) {
      case BaContactSource.description:
        return null; // offline aus der Beschreibung – keine spezifische URL.
      case BaContactSource.externalJobPage:
        return result.externalUrl;
      case BaContactSource.employerWebsite:
        return result.website;
      case BaContactSource.none:
        return null;
    }
  }

  Future<ContactEnrichmentOutcome> _enrichGeneric(
    Application app, {
    required String? contactPerson,
  }) async {
    final host = Uri.tryParse(app.jobUrl)?.host.toLowerCase();
    if (host != null) await _pace(host);
    try {
      final result = await _discovery.discover(
        jobUrl: app.jobUrl,
        company: app.company,
        companyAddress: app.companyAddress,
        jobDescription: app.jobDescription,
      );
      if (!result.found || result.email == null) {
        return ContactEnrichmentOutcome(
          applicationId: app.id,
          jobTitle: app.jobTitle,
          company: app.company,
          contactPerson: contactPerson,
          note: result.note,
        );
      }
      return ContactEnrichmentOutcome(
        applicationId: app.id,
        jobTitle: app.jobTitle,
        company: app.company,
        email: result.email,
        emailSource: result.source.name,
        evidenceUrl: result.evidenceUrl,
        contactPerson: contactPerson,
        note: result.note,
      );
    } catch (e) {
      _failed++;
      _log.warning('Kontakt-Ermittlung fehlgeschlagen für ${app.jobTitle}: $e');
      return ContactEnrichmentOutcome(
        applicationId: app.id,
        jobTitle: app.jobTitle,
        company: app.company,
        contactPerson: contactPerson,
        note: 'Fehler: $e',
      );
    }
  }

  /// Minimaler Abstand zwischen zwei Requests an denselben Host (seriell).
  Future<void> _pace(String host) async {
    final last = _lastHitByHost[host];
    if (last != null) {
      var wait = minDelayPerHost - DateTime.now().difference(last);
      if (wait > Duration.zero) {
        if (enableJitter) {
          wait += Duration(milliseconds: _rand.nextInt(251));
        }
        await Future<void>.delayed(wait);
      }
    }
    _lastHitByHost[host] = DateTime.now();
  }

  /// True, wenn ein abgebrochener Versuch auf einen Blocker/Timeout
  /// (nicht umgangen) hindeutet – fließt in die Statistik `blocked` ein.
  bool _isBlockerAbort(ContactEnrichmentOutcome outcome) {
    final note = outcome.note;
    if (note == null) return false;
    final lower = note.toLowerCase();
    return lower.contains('blocker') ||
        lower.contains('captcha') ||
        lower.contains('timeout');
  }
}


