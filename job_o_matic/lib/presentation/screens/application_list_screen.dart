import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../data/repositories/job_repository.dart';
import '../../models/application.dart';
import 'send_screen.dart';

/// Screen 3: Overview of all generated applications.
///
/// Displays a list of applications with their current status.
/// Supports batch export, retry for failed apps, and navigation to detail view.
class ApplicationListScreen extends ConsumerStatefulWidget {
  const ApplicationListScreen({super.key});

  @override
  ConsumerState<ApplicationListScreen> createState() =>
      _ApplicationListScreenState();
}

class _ApplicationListScreenState extends ConsumerState<ApplicationListScreen> {
  final Logger _log = Logger('ApplicationListScreen');

  /// Opt-in „Erstellen & Versenden“ (Phase E): Nach erfolgreicher Generierung
  /// automatisch zum Versand-Screen (Sammelversand der neuen Bewerbungen).
  bool _sendAfterGenerate = false;

  @override
  void initState() {
    super.initState();
    // Create applications from validated URLs + selected jobs when entering this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(jobRepositoryProvider);
      bool created = false;

      // 1. Aus validierten URLs
      if (repo.validatedUrls.isNotEmpty) {
        repo.createApplicationsFromUrls();
        created = true;
        _log.info('Applikationen aus URLs erstellt');
      }

      // 2. Aus übernommenen Job-IDs (Jobsuche)
      if (repo.selectedJobIds.isNotEmpty) {
        repo.createApplicationsFromSelectedJobs();
        created = true;
        _log.info('Applikationen aus Jobsuche erstellt');
      }

      if (created) {
        setState(() {});
      }
    });
  }

  void _deleteApplication(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bewerbung löschen'),
        content: const Text('Möchten Sie diese Bewerbung wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(jobRepositoryProvider).removeApplication(id);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAll() async {
    final repo = ref.read(jobRepositoryProvider);
    final queued = repo.applications
        .where((a) => a.status == ApplicationStatus.queued)
        .toList();

    if (queued.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine wartenden Bewerbungen zum Generieren.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _log.info('Generierung gestartet: ${queued.length} Bewerbungen');

    for (final app in queued) {
      try {
        await repo.generatePdf(app.id);
        _log.info('Generierung abgeschlossen: ${app.jobTitle}');
      } catch (e) {
        _log.severe('Generierung fehlgeschlagen: ${app.jobTitle} – $e');
      }
    }

    if (!context.mounted) return;
    final completed = repo.applications
        .where((a) => a.status == ApplicationStatus.completed)
        .length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$completed Bewerbung(en) erfolgreich generiert.'),
        backgroundColor: Colors.green,
      ),
    );

    // Opt-in „Erstellen & Versenden“ (Phase E): nach erfolgreicher
    // Generierung direkt den Sammelversand-Dialog der neuen Bewerbungen
    // öffnen (inkl. Dublettenschutz-Bestätigung).
    if (_sendAfterGenerate && completed > 0 && context.mounted) {
      context.push(
        '/send',
        extra: const SendRequest(sendAllNew: true, autoSend: true),
      );
    }
  }

  void _retryApplication(int id) {
    ref
        .read(jobRepositoryProvider)
        .updateApplicationStatus(id, ApplicationStatus.queued);
    _log.info('Applikation $id: Neustart angefordert');
    setState(() {});
  }

  /// Debug helper: pick individual applications and reset them to "queued".
  void _requeueSingle() {
    final repo = ref.read(jobRepositoryProvider);
    final candidates = repo.applications
        .where((a) => a.status != ApplicationStatus.queued)
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alle Bewerbungen sind bereits auf "wartend".'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = <int>{};
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Einzelne auf "wartend"'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final app = candidates[index];
                return CheckboxListTile(
                  dense: true,
                  value: selected.contains(app.id),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selected.add(app.id);
                    } else {
                      selected.remove(app.id);
                    }
                  }),
                  secondary: Text(
                    app.status.displayName,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  title: Text(
                    app.jobTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${app.company} · ID ${app.id}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      ref.read(jobRepositoryProvider).resetToQueued(selected);
                      Navigator.pop(ctx);
                    },
              icon: const Icon(Icons.replay),
              label: Text('Zurücksetzen (${selected.length})'),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {}); // Liste aktualisieren
    });
  }

  Future<void> _exportAll() async {
    final app = ref.read(jobRepositoryProvider);
    final completed = app.applications
        .where((a) => a.status == ApplicationStatus.completed)
        .toList();

    if (completed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine abgeschlossenen Bewerbungen zum Exportieren.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _log.info('Batch-Export: ${completed.length} Bewerbungen');

    // Kopiere Dateien auf den Desktop des Benutzers
    final desktopPath = Directory(
      '${Platform.environment['USERPROFILE']}\\Desktop\\Job-O-Matic_Export',
    );
    final exportDir = Directory(desktopPath.path);
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    int copiedCount = 0;
    for (final application in completed) {
      if (application.pdfPath != null) {
        final sourceFile = File(application.pdfPath!);
        if (await sourceFile.exists()) {
          final targetPath =
              '${exportDir.path}\\Bewerbung_${_sanitizeFileName(application.company)}.pdf';
          await sourceFile.copy(targetPath);
          copiedCount++;

          app.updateApplicationStatus(
            application.id,
            ApplicationStatus.exported,
          );
        }
      }
    }

    if (!context.mounted) return;
    if (copiedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine PDF-Dateien zum Exportieren gefunden.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$copiedCount Bewerbung(en) exportiert nach:\n${exportDir.path}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Ordner öffnen',
          onPressed: () => _openFolder(exportDir.path),
        ),
      ),
    );

    setState(() {});
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll(' ', '_');
  }

  void _openFolder(String path) {
    try {
      Process.start('explorer', [path]);
    } catch (e) {
      _log.warning('Konnte Ordner nicht öffnen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(jobRepositoryProvider);
    final applications = repo.applications;
    final total = applications.length;
    final completed = applications
        .where((a) => a.status == ApplicationStatus.completed)
        .length;
    final failed = applications
        .where((a) => a.status == ApplicationStatus.failed)
        .length;
    final inProgress = applications
        .where((a) => a.status == ApplicationStatus.processing)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ergebnisübersicht'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.send_outlined),
            tooltip: 'E-Mail-Versand',
            onPressed: () => context.push('/send'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.developer_mode),
            tooltip: 'Debug-Optionen',
            onSelected: (value) async {
              if (value == 'reset') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('DB zurücksetzen?'),
                    content: const Text(
                      'Löscht alle Daten (Applications, URLs, Filter, CV-Daten).'
                      '\nDie Datenbank wird komplett neu erstellt.'
                      '\n\nNur für Debug-Zwecke!',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Zurücksetzen'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(jobRepositoryProvider).resetAllData();
                  if (context.mounted)
                    context.go('/'); // zurück zur Stelleneingabe
                }
              } else if (value == 'requeue') {
                ref.read(jobRepositoryProvider).resetAllToQueued();
                setState(() {});
              } else if (value == 'requeueSingle') {
                _requeueSingle();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'requeue',
                child: ListTile(
                  leading: Icon(Icons.replay),
                  title: Text('Alle auf "wartend"'),
                  subtitle: Text('Zuletzt hinzugefügte bleiben'),
                ),
              ),
              const PopupMenuItem(
                value: 'requeueSingle',
                child: ListTile(
                  leading: Icon(Icons.replay_circle_filled),
                  title: Text('Einzelne auf "wartend"'),
                  subtitle: Text(
                    'Auswahl einzelner Bewerbungen',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  leading: Icon(
                    Icons.delete_forever,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'DB zurücksetzen',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text(
                    'Kompletter Reset',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fortschritt: $completed / $total fertig',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: total > 0 ? completed / total : 0,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${failed > 0 ? "$failed fehlgeschlagen" : ""}${inProgress > 0 ? " · $inProgress in Bearbeitung" : ""}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: failed > 0
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: completed > 0 ? _exportAll : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Exportieren'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: total > 0 && completed < total
                      ? _generateAll
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    completed > 0 && completed < total
                        ? 'Restliche generieren'
                        : 'Alle generieren',
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _sendAfterGenerate,
                  onChanged: (value) =>
                      setState(() => _sendAfterGenerate = value ?? false),
                  title: const Text('Erstellen & Versenden'),
                  subtitle: const Text(
                    'Nach der Generierung direkt zum E-Mail-Versand '
                    '(Sammelversand der neuen Bewerbungen).',
                  ),
                ),
              ],
            ),
          ),

          // Application list
          Expanded(
            child: applications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Keine Bewerbungen vorhanden.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () => context.go('/'),
                          child: const Text('Zur Stelleneingabe'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: applications.length,
                    itemBuilder: (context, index) {
                      final app = applications[index];
                      final isFailed = app.status == ApplicationStatus.failed;
                      final isCompleted =
                          app.status == ApplicationStatus.completed;
                      final isSendable =
                          (app.status == ApplicationStatus.completed ||
                              app.status == ApplicationStatus.exported) &&
                          app.pdfPath != null;

                      IconData statusIcon;
                      Color statusColor;
                      switch (app.status) {
                        case ApplicationStatus.queued:
                          statusIcon = Icons.hourglass_empty;
                          statusColor = Colors.grey;
                        case ApplicationStatus.processing:
                          statusIcon = Icons.sync;
                          statusColor = Colors.blue;
                        case ApplicationStatus.completed:
                          statusIcon = Icons.check_circle;
                          statusColor = Colors.green;
                        case ApplicationStatus.failed:
                          statusIcon = Icons.error;
                          statusColor = theme.colorScheme.error;
                        case ApplicationStatus.exported:
                          statusIcon = Icons.cloud_done;
                          statusColor = Colors.teal;
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Icon(statusIcon, color: statusColor),
                          title: Text(app.jobTitle),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${app.company} · ${app.status.displayName}',
                              ),
                              if (isFailed && app.errorMessage != null)
                                Text(
                                  app.errorMessage!,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSendable)
                                IconButton(
                                  icon: const Icon(Icons.send_outlined),
                                  tooltip: 'Per E-Mail senden',
                                  onPressed: () => context.push(
                                    '/send',
                                    extra: SendRequest(applicationId: app.id),
                                  ),
                                ),
                              if (isFailed)
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  tooltip: 'Neu starten',
                                  onPressed: () => _retryApplication(app.id),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Löschen',
                                onPressed: () => _deleteApplication(app.id),
                              ),
                              if (isCompleted || isFailed)
                                const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () {
                            if (isCompleted || isFailed) {
                              context.go('/applications/${app.id}');
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
