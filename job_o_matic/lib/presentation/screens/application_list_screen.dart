import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../data/repositories/job_repository.dart';
import '../../models/application.dart';

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

class _ApplicationListScreenState
    extends ConsumerState<ApplicationListScreen> {
  final Logger _log = Logger('ApplicationListScreen');

  @override
  void initState() {
    super.initState();
    // Create applications from validated URLs when entering this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(jobRepositoryProvider);
      if (repo.validatedUrls.isNotEmpty) {
        repo.createApplicationsFromUrls();
        _log.info('Applikationen aus URLs erstellt');
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

  void _retryApplication(int id) {
    ref.read(jobRepositoryProvider).updateApplicationStatus(
          id,
          ApplicationStatus.queued,
        );
    _log.info('Applikation $id: Neustart angefordert');
    setState(() {});
  }

  Future<void> _exportAll() async {
    final apps = ref.read(jobRepositoryProvider).applications;
    final completed =
        apps.where((a) => a.status == ApplicationStatus.completed).toList();

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

    // Mark as exported
    for (final app in completed) {
      ref.read(jobRepositoryProvider).updateApplicationStatus(
            app.id,
            ApplicationStatus.exported,
          );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${completed.length} Bewerbung(en) exportiert.'),
        backgroundColor: Colors.green,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(jobRepositoryProvider);
    final applications = repo.applications;
    final total = applications.length;
    final completed =
        applications.where((a) => a.status == ApplicationStatus.completed).length;
    final failed =
        applications.where((a) => a.status == ApplicationStatus.failed).length;
    final inProgress =
        applications.where((a) => a.status == ApplicationStatus.processing).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ergebnisübersicht'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Column(
        children: [
          // Progress bar
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
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
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
                  label: const Text('Alle exportieren'),
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
                        Icon(Icons.folder_open,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant),
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
                      final isFailed =
                          app.status == ApplicationStatus.failed;
                      final isCompleted =
                          app.status == ApplicationStatus.completed;

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
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: Icon(statusIcon, color: statusColor),
                          title: Text(app.jobTitle),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${app.company} · ${app.status.displayName}'),
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