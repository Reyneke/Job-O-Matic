import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/providers/providers.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/services/email/email_address_utils.dart';
import '../../data/services/email/email_discovery_service.dart';
import '../../data/services/email/email_service.dart';
import '../../data/services/email/circuit_breaker.dart';
import '../../data/services/email/mail_queue_service.dart';
import '../../models/application.dart';
import '../../models/sent_email_log_entry.dart';

/// Route-Parameter für `/send` (Phase E: Wiederversand, Sammelversand,
/// „Erstellen & Versenden“).
///
/// - [applicationId]: Bewerbung vorauswählen (Wiederversand aus
///   `/applications` bzw. `/applications/:id`).
/// - [sendAllNew]: alle noch nicht gesendeten versandfähigen Bewerbungen
///   auswählen (Sammelversand).
/// - [autoSend]: die Auswahl sofort in den Bestätigungs-/Versanddialog
///   schicken („Erstellen & Versenden“, Direktversand nach Generierung).
class SendRequest {
  const SendRequest({
    this.applicationId,
    this.sendAllNew = false,
    this.autoSend = false,
  });

  final int? applicationId;
  final bool sendAllNew;
  final bool autoSend;
}

/// Screen 4: E-Mail-Versand (`/send`).
///
/// Versandfähige Bewerbungen (`completed`/`exported` mit PDF) mit editierbaren
/// Empfänger-/CC-/BCC-/Betreff-/Text-Feldern, Adress-Kaskade („Ermitteln“),
/// Dublettenschutz (History-Prüfung + Bestätigungsdialog) und Live-Status von
/// Queue und Circuit Breaker. Siehe doc/plan/14-Email.md Phase D + E.
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key, this.request});

  final SendRequest? request;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

/// Bearbeitbarer Entwurf je Bewerbung (Controller überleben Rebuilds).
class _SendDraft {
  _SendDraft({
    required this.application,
    required String? initialEmail,
    required String initialSubject,
    required String initialBody,
  }) : recipient = TextEditingController(text: initialEmail ?? ''),
       cc = TextEditingController(),
       bcc = TextEditingController(),
       subject = TextEditingController(text: initialSubject),
       body = TextEditingController(text: initialBody);

  final Application application;
  final TextEditingController recipient;
  final TextEditingController cc;
  final TextEditingController bcc;
  final TextEditingController subject;
  final TextEditingController body;

  void dispose() {
    recipient.dispose();
    cc.dispose();
    bcc.dispose();
    subject.dispose();
    body.dispose();
  }
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final Logger _log = Logger('SendScreen');
  Timer? _refreshTimer;

  bool _loadingConfig = true;
  bool _configured = false;
  bool _busy = false;

  final Set<int> _selected = {};
  final Map<int, _SendDraft> _drafts = {};
  final Map<int, bool> _alreadySent = {};
  final Map<int, DateTime?> _lastSentAt = {};

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final configured = await ref.read(mailDispatcherProvider).isConfigured();
    if (!mounted) return;
    setState(() {
      _configured = configured;
      _loadingConfig = false;
    });
    if (configured) {
      await _refreshLogState();
      _handleRequest();
    }
  }

  /// Wertet den Route-Request aus (Phase E): vorauswählen / Sammelversand /
  /// Direktversand – jeweils erst nach erfolgreicher Konfiguration.
  Future<void> _handleRequest() async {
    final request = widget.request;
    if (request == null) return;
    if (!mounted) return;

    if (request.sendAllNew) {
      setState(() => _selected.clear());
      if (request.autoSend) {
        await _sendAllNewInternal();
      } else {
        _selectAllNewInternal();
      }
      return;
    }

    final appId = request.applicationId;
    if (appId == null) return;
    setState(() {
      _selected.clear();
      _selected.add(appId);
    });
    if (request.autoSend) {
      await _requestSend([appId]);
    }
  }

  Future<void> _refreshLogState() async {
    final logRepo = ref.read(sentEmailLogRepositoryProvider);
    final apps = _sendableApplications(
      ref.read(jobRepositoryProvider).applications,
    );
    final hasSent = <int, bool>{};
    final dates = <int, DateTime?>{};
    for (final app in apps) {
      hasSent[app.id] = await logRepo.hasSent(app.id);
      dates[app.id] = await logRepo.latestSentAt(app.id);
    }
    if (!mounted) return;
    setState(() {
      _alreadySent
        ..clear()
        ..addAll(hasSent);
      _lastSentAt
        ..clear()
        ..addAll(dates);
    });
  }

  List<Application> _sendableApplications(List<Application> apps) {
    final result = apps
        .where(
          (a) =>
              (a.status == ApplicationStatus.completed ||
                  a.status == ApplicationStatus.exported) &&
              a.pdfPath != null,
        )
        .toList();
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  _SendDraft _draftFor(Application app) {
    return _drafts.putIfAbsent(app.id, () {
      final template = ref.read(emailTemplateServiceProvider);
      final fullName =
          ref.read(jobRepositoryProvider).cvData?.personalData.fullName ??
          EmailService.defaultSenderName;
      return _SendDraft(
        application: app,
        initialEmail: app.emailAddress,
        initialSubject: template.buildSubject(
          position: app.jobTitle,
          company: app.company,
        ),
        initialBody: template.buildApplicationBody(
          position: app.jobTitle,
          company: app.company,
          fullName: fullName,
        ),
      );
    });
  }

  static String _emailStatusLabel(EmailStatus status) {
    switch (status) {
      case EmailStatus.initial:
        return 'Neu';
      case EmailStatus.queued:
        return 'Eingeplant';
      case EmailStatus.sending:
        return 'Wird gesendet';
      case EmailStatus.sent:
        return 'Gesendet';
      case EmailStatus.failed:
        return 'Fehlgeschlagen';
    }
  }

  static String _breakerLabel(CircuitBreakerState state) {
    switch (state) {
      case CircuitBreakerState.closed:
        return 'OK';
      case CircuitBreakerState.open:
        return 'OFFEN';
      case CircuitBreakerState.halfOpen:
        return 'Test';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(jobRepositoryProvider);
    final sendable = _sendableApplications(repo.applications);

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Mail-Versand'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Zurück',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/applications'),
        ),
        actions: [
          // Debug-Test (Phase E/F): sendet eine ausgewählte bzw. die erste
          // versandfähige Bewerbung testweise an den Absender selbst.
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Test-E-Mail an Absender senden',
            onPressed: (_configured && !_busy && sendable.isNotEmpty)
                ? _sendTestEmail
                : null,
          ),
        ],
      ),
      body: _buildBody(theme, sendable),
      bottomNavigationBar: _configured && sendable.isNotEmpty && !_busy
          ? _buildBottomBar(theme)
          : null,
    );
  }

  Widget _buildBody(ThemeData theme, List<Application> sendable) {
    if (_loadingConfig) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_configured) {
      return _buildNotConfigured(theme);
    }
    if (sendable.isEmpty) {
      return _buildEmpty(theme);
    }
    return Column(
      children: [
        _buildStatsCard(theme),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sendable.length,
            itemBuilder: (context, index) => _buildRow(theme, sendable[index]),
          ),
        ),
        // DSGVO-/Recht-Hinweis (Phase F): Aufbewahrung + zurückhaltendes
        // Scraping (nur die Kontaktseite der Anzeige, max. 1 Zusatz-Request).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Hinweis: E-Mails werden an die in der Anzeige angegebene oder '
            'manuell bestätigte Adresse gesendet. Der Versand-Verlauf wird '
            'für die Nachvollziehbarkeit gespeichert und nach 6 Monaten '
            'automatisch gelöscht (zusätzlich löschbar in den Einstellungen). '
            'Die Adress-Ermittlung beschränkt sich auf die Kontaktseite der '
            'Stellenanzeige (max. 1 Zusatz-Request) – keine Massenabfragen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotConfigured(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            const Text(
              'Kein Brevo-API-Key hinterlegt.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bitte hinterlegen Sie Ihren Brevo-API-Key in den Einstellungen, '
              'bevor Sie E-Mails versenden.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings),
              label: const Text('Zu den Einstellungen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_email_read_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Keine versandfähigen Bewerbungen.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Versandfähig sind Bewerbungen mit Status „Abgeschlossen“ oder '
              '„Exportiert“ inklusive erzeugter PDF.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.go('/applications'),
              icon: const Icon(Icons.list_alt),
              label: const Text('Zur Ergebnisübersicht'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(ThemeData theme) {
    final stats = ref.read(mailDispatcherProvider).stats;
    final breakerOpen = stats.circuitBreakerState == CircuitBreakerState.open;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _StatChip(
              label: 'Pending',
              value: '${stats.pendingCount}',
              color: Colors.orange,
            ),
            _StatChip(
              label: 'Gesendet',
              value: '${stats.sentCount}',
              color: Colors.green,
            ),
            _StatChip(
              label: 'Fehler',
              value: '${stats.failedCount}',
              color: Colors.red,
            ),
            const Spacer(),
            Tooltip(
              message: breakerOpen
                  ? 'Circuit Breaker OFFEN – Versand pausiert (Automatik-Retry)'
                  : 'Circuit Breaker aktiv',
              child: Chip(
                avatar: Icon(
                  breakerOpen ? Icons.power_off : Icons.check_circle,
                  size: 16,
                  color: breakerOpen ? theme.colorScheme.error : Colors.green,
                ),
                label: Text('CB: ${_breakerLabel(stats.circuitBreakerState)}'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _sendAllNew,
                icon: const Icon(Icons.send),
                label: const Text('Alle neuen senden'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: (_selected.isEmpty || _busy)
                    ? null
                    : () => _requestSend(_selected.toList()),
                icon: const Icon(Icons.forward),
                label: Text('Ausgewählte senden (${_selected.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(ThemeData theme, Application app) {
    final draft = _draftFor(app);
    final selected = _selected.contains(app.id);
    final alreadySent = _alreadySent[app.id] ?? false;
    final lastSent = _lastSentAt[app.id];
    final addressOk = isValidEmail(draft.recipient.text.trim());

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: PageStorageKey('send_app_${app.id}'),
        leading: Checkbox(
          value: selected,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  if (value == true) {
                    _selected.add(app.id);
                  } else {
                    _selected.remove(app.id);
                  }
                }),
        ),
        title: Text(
          '${app.jobTitle} · ${app.company}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'E-Mail: ${_emailStatusLabel(app.emailStatus)}'
              '${alreadySent ? ' · bereits gesendet' : ''}',
            ),
            if (lastSent != null)
              Text(
                'Zuletzt gesendet: ${_formatDate(lastSent)}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: draft.recipient,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'Empfänger (E-Mail)',
                    hintText: 'hr@firma.de',
                    isDense: true,
                    errorText:
                        draft.recipient.text.trim().isNotEmpty && !addressOk
                        ? 'Ungültige E-Mail-Adresse'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Adresse ermitteln (Anzeige → Kontakt)',
                onPressed: _busy ? null : () => _discoverAddress(app),
                icon: const Icon(Icons.travel_explore),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.cc,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'CC (optional)',
                    hintText: 'a@x.de, b@y.de',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.bcc,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'BCC (optional)',
                    hintText: 'a@x.de, b@y.de',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.subject,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Betreff',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.body,
            enabled: !_busy,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Text (Vorschau, editierbar)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'PDF: ${app.pdfPath == null ? 'fehlt' : _fileBaseName(app.pdfPath!)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  List<int> _allNewIds() {
    return _sendableApplications(
      ref.read(jobRepositoryProvider).applications,
    ).where((a) => !(_alreadySent[a.id] ?? false)).map((a) => a.id).toList();
  }

  void _selectAllNewInternal() {
    final ids = _allNewIds();
    if (ids.isEmpty) return;
    setState(() => _selected.addAll(ids));
  }

  void _sendAllNew() {
    final ids = _allNewIds();
    if (ids.isEmpty) {
      _showSnack('Alle versandfähigen Bewerbungen wurden bereits gesendet.');
      return;
    }
    setState(() => _selected.addAll(ids));
    _requestSend(ids);
  }

  Future<void> _sendAllNewInternal() async {
    final ids = _allNewIds();
    if (ids.isEmpty) {
      _showSnack('Alle versandfähigen Bewerbungen wurden bereits gesendet.');
      return;
    }
    setState(() => _selected.addAll(ids));
    await _requestSend(ids);
  }

  Future<void> _requestSend(List<int> ids) async {
    final repo = ref.read(jobRepositoryProvider);
    final problems = <String>[];
    final validIds = <int>[];
    var alreadySentCount = 0;
    for (final id in ids) {
      final app = repo.getApplication(id);
      if (app == null) continue;
      final draft = _draftFor(app);
      if (!isValidEmail(draft.recipient.text.trim())) {
        problems.add(
          '${app.company}: Empfänger-Adresse fehlt oder ist ungültig.',
        );
        continue;
      }
      validIds.add(id);
      if (_alreadySent[id] ?? false) alreadySentCount++;
    }

    if (problems.isNotEmpty) {
      _showSnack('Bitte zuerst prüfen:\n${problems.join('\n')}', isError: true);
      return;
    }
    if (validIds.isEmpty) return;

    // Dublettenschutz: History-Prüfung – bei „bereits gesendet“ explizit
    // bestätigen lassen (bewusster Wiederversand, Anforderung 3).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          alreadySentCount > 0
              ? 'Bereits gesendet – erneut senden?'
              : 'Versand bestätigen',
        ),
        content: Text(
          alreadySentCount > 0
              ? '$alreadySentCount der ausgewählten Bewerbungen wurde bereits '
                    'erfolgreich gesendet (siehe Audit-Log). Möchten Sie diese '
                    'wirklich erneut versenden?'
              : '${validIds.length} Bewerbung(en) werden versendet. '
                    'Fortfahren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Senden'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _doSend(validIds);
    }
  }

  Future<void> _doSend(List<int> ids) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(jobRepositoryProvider);
      final dispatcher = ref.read(mailDispatcherProvider);
      final queueService = ref.read(mailQueueServiceProvider);
      final fullName =
          repo.cvData?.personalData.fullName ?? EmailService.defaultSenderName;
      final senderEmail = EmailService.defaultSenderEmail;

      for (final id in ids) {
        final app = repo.getApplication(id);
        if (app == null || app.pdfPath == null) continue;
        final draft = _draftFor(app);
        final cc = _parseAddressList(draft.cc.text);
        final bcc = _parseAddressList(draft.bcc.text);

        repo.updateApplicationEmail(id, emailStatus: EmailStatus.queued);
        await dispatcher.enqueueApplicationEmail(
          to: draft.recipient.text.trim(),
          position: app.jobTitle,
          company: app.company,
          fullName: fullName,
          pdfPath: app.pdfPath,
          applicationId: '$id',
          senderName: fullName,
          senderEmail: senderEmail,
          cc: cc.isEmpty ? null : cc,
          bcc: bcc.isEmpty ? null : bcc,
        );
        _log.info('Bewerbung $id (${app.company}) in Queue gelegt');
      }

      // Sofort einen Verarbeitungsschritt anstoßen. Der Rate-Limiter
      // (Standard 5/min) entscheidet, wie viele sofort rausgehen; der Rest
      // bleibt persistent in der Queue und wird vom Dispatcher-Timer
      // nachgeliefert.
      await dispatcher.processQueue();

      // emailStatus je Bewerbung aus dem Queue-Endzustand ableiten.
      for (final id in ids) {
        MailQueueEntry? newest;
        for (final e in queueService.allEntries) {
          if (e.applicationId == '$id' &&
              (newest == null || e.retryCount > newest.retryCount)) {
            newest = e;
          }
        }
        if (newest == null) continue;
        final status = switch (newest.status) {
          MailStatus.sent => EmailStatus.sent,
          MailStatus.failed => EmailStatus.failed,
          _ => EmailStatus.queued,
        };
        repo.updateApplicationEmail(id, emailStatus: status);
      }

      await _refreshLogState();
      if (!mounted) return;

      // 401-Fallback „Als Entwurf exportieren“ (Absender nicht verifiziert):
      // fehlgeschlagene Einträge mit 401 anbieten, die PDF als Entwurf auf den
      // Desktop exportieren und im Audit-Log als draft_exported festhalten.
      final exportCandidates = <Application>[];
      for (final id in ids) {
        final app = repo.getApplication(id);
        if (app == null) continue;
        MailQueueEntry? newest;
        for (final e in queueService.allEntries) {
          if (e.applicationId == '$id' &&
              (newest == null || e.retryCount > newest.retryCount)) {
            newest = e;
          }
        }
        final isSender401 =
            newest != null &&
            newest.status == MailStatus.failed &&
            (newest.errorMessage?.contains('401') ?? false);
        if (isSender401) exportCandidates.add(app);
      }
      if (exportCandidates.isNotEmpty) {
        await _offerDraftExport(exportCandidates);
        if (!mounted) return;
      }

      final idSet = ids.map((i) => '$i').toSet();
      final sentNow = queueService.allEntries
          .where((e) => idSet.contains(e.applicationId))
          .where((e) => e.status == MailStatus.sent)
          .length;
      final queuedNow = ids.length - sentNow;
      _showSnack(
        sentNow > 0
            ? '$sentNow Bewerbung(en) gesendet.'
            : 'E-Mails eingeplant – Versand läuft automatisch weiter.'
                  '${queuedNow > 0 ? ' ($queuedNow in der Queue)' : ''}',
      );
    } catch (e) {
      _log.severe('Versand fehlgeschlagen: $e');
      if (mounted) {
        _showSnack('Versand fehlgeschlagen: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selected.clear();
        });
      }
    }
  }

  /// Bietet an, fehlgeschlagene Bewerbungen (401 – Absender nicht verifiziert)
  /// als Entwurf auf den Desktop zu exportieren (Fallback-Kanal, Phase E).
  Future<void> _offerDraftExport(List<Application> candidates) async {
    final exportNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Als Entwurf exportieren?'),
        content: Text(
          'Der Versand an ${candidates.length} Bewerbung(en) ist mit HTTP 401 '
          'fehlgeschlagen (Absender nicht verifiziert).\n\n'
          'Die Bewerbungs-PDF kann stattdessen als Entwurf auf den Desktop '
          'exportiert werden (Audit-Log: „Als Entwurf exportiert“).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Überspringen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_alt),
            label: const Text('Exportieren'),
          ),
        ],
      ),
    );
    if (exportNow == true) {
      await _exportDraft(candidates);
    }
  }

  Future<void> _exportDraft(List<Application> apps) async {
    var exported = 0;
    try {
      final logRepo = ref.read(sentEmailLogRepositoryProvider);
      final base =
          Platform.environment['USERPROFILE'] ??
          (Platform.environment['HOME'] ?? '.');
      final exportDir = Directory('$base\\Desktop\\Job-O-Matic_Export');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      for (final app in apps) {
        final sourcePath = app.pdfPath;
        if (sourcePath == null) continue;
        final source = File(sourcePath);
        if (!await source.exists()) continue;
        final target = File(
          '${exportDir.path}\\Bewerbung_${_sanitizeFileName(app.company)}.pdf',
        );
        await source.copy(target.path);
        await logRepo.insert(
          SentEmailLogEntry(
            applicationId: app.id,
            recipientEmail: app.emailAddress ?? '',
            subject: 'Bewerbung ${app.jobTitle} bei ${app.company}',
            status: SentEmailLogStatus.draftExported,
            sentAt: DateTime.now(),
          ),
        );
        exported++;
      }
    } catch (e) {
      _log.severe('Entwurf-Export fehlgeschlagen: $e');
    }
    if (!mounted) return;
    _showSnack(
      exported > 0
          ? '$exported Bewerbung(en) als Entwurf exportiert (Desktop/'
                'Job-O-Matic_Export).'
          : 'Entwurf-Export nicht möglich (PDF fehlt).',
    );
    await _refreshLogState();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(' ', '_');
  }

  Future<void> _sendTestEmail() async {
    final repo = ref.read(jobRepositoryProvider);
    final sendable = _sendableApplications(repo.applications);
    if (sendable.isEmpty) {
      _showSnack(
        'Keine versandfähige Bewerbung fuer den Test vorhanden.',
        isError: true,
      );
      return;
    }
    // Bevorzugt die ausgewählte Bewerbung, sonst die erste versandfähige.
    var app = sendable.firstWhere(
      (a) => _selected.contains(a.id),
      orElse: () => sendable.first,
    );
    if (app.pdfPath == null) {
      app = sendable.firstWhere((a) => a.pdfPath != null, orElse: () => app);
    }

    if (!_configured) {
      _showSnack('Kein Brevo-API-Key hinterlegt.', isError: true);
      return;
    }

    final target = EmailService.defaultSenderEmail;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test-E-Mail senden?'),
        content: Text(
          'Sendet die Bewerbung "${app.jobTitle}" bei ${app.company} '
          'testweise an den Absender selbst:\n\n$target\n\n'
          '(inkl. PDF-Anhang - prüft den kompletten Versand-Pfad.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Test senden'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final dispatcher = ref.read(mailDispatcherProvider);
      final fullName =
          repo.cvData?.personalData.fullName ?? EmailService.defaultSenderName;
      await dispatcher.enqueueApplicationEmail(
        to: target,
        position: app.jobTitle,
        company: app.company,
        fullName: fullName,
        pdfPath: app.pdfPath,
        applicationId: '${app.id}',
        senderName: fullName,
        senderEmail: EmailService.defaultSenderEmail,
        // CC/BCC der gewählten Bewerbung mitschicken, falls gesetzt.
        cc: _selected.contains(app.id)
            ? _parseAddressList(_draftFor(app).cc.text)
            : null,
        bcc: _selected.contains(app.id)
            ? _parseAddressList(_draftFor(app).bcc.text)
            : null,
      );
      await dispatcher.processQueue();
      await _refreshLogState();

      if (!mounted) return;
      final entry = _queueLatestEntry(app.id);
      final status = entry?.status ?? MailStatus.pending;
      if (status == MailStatus.sent) {
        _showSnack('Test-E-Mail an $target gesendet.');
      } else if (status == MailStatus.failed) {
        final error = entry?.errorMessage ?? 'unbekannter Fehler';
        _log.severe('Test-E-Mail fehlgeschlagen: $error');
        _showSnack('Test-E-Mail fehlgeschlagen: $error', isError: true);
      } else {
        _showSnack(
          'Test-E-Mail eingeplant – Versand läuft automatisch weiter.',
        );
      }
    } catch (e) {
      _log.severe('Test-E-Mail fehlgeschlagen: $e');
      if (mounted) {
        _showSnack('Test-E-Mail fehlgeschlagen: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Aktueller neuester Queue-Eintrag eines Versuchs (nach retryCount).
  MailQueueEntry? _queueLatestEntry(int applicationId) {
    MailQueueEntry? newest;
    for (final e in ref.read(mailQueueServiceProvider).allEntries) {
      if (e.applicationId == '$applicationId' &&
          (newest == null || e.retryCount > newest.retryCount)) {
        newest = e;
      }
    }
    return newest;
  }

  Future<void> _discoverAddress(Application app) async {
    setState(() => _busy = true);
    try {
      final service = ref.read(emailDiscoveryServiceProvider);
      final result = await service.discover(
        companyAddress: app.companyAddress,
        jobDescription: app.jobDescription,
        jobUrl: app.jobUrl,
      );
      if (!mounted) return;
      final draft = _draftFor(app);
      if (result.found && result.email != null) {
        final adopt = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Adresse ermittelt'),
            content: Text(
              'Gefunden in Stufe ${_sourceLabel(result.source)}:\n\n'
              '${result.email}\n\nÜbernehmen und speichern?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Verwerfen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Übernehmen'),
              ),
            ],
          ),
        );
        if (adopt == true) {
          draft.recipient.text = result.email!;
          ref
              .read(jobRepositoryProvider)
              .updateApplicationEmail(app.id, emailAddress: result.email);
          setState(() {});
        }
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Keine Adresse gefunden'),
            content: Text(
              'Automatische Ermittlung ohne Ergebnis.\n'
              '${result.note == null ? '' : '${result.note}\n\n'}'
              'Bitte tragen Sie die Adresse manuell ein (Stufe 4).',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _log.warning('Adress-Ermittlung fehlgeschlagen: $e');
      if (mounted) {
        _showSnack('Adress-Ermittlung fehlgeschlagen: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _sourceLabel(EmailDiscoverySource source) {
    switch (source) {
      case EmailDiscoverySource.storedData:
        return '1 (gespeicherte Daten)';
      case EmailDiscoverySource.mailtoLink:
        return '2 (mailto-Link)';
      case EmailDiscoverySource.contactPage:
        return '3 (Kontaktseite)';
      case EmailDiscoverySource.none:
        return '–';
    }
  }

  List<String> _parseAddressList(String text) => text
      .split(RegExp(r'[,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && isValidEmail(e))
      .toList();

  String _fileBaseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year} $hh:$mm';
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }
}

/// Kleine Status-Kachel für die Queue-Statistik im Versand-Screen.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
