import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/job_repository.dart';
import '../../models/application.dart';

/// Screen 3a: Detail view of a single application.
///
/// Shows PDF preview (placeholder), metadata,
/// and allows download, regeneration, or deletion.
class ApplicationDetailScreen extends ConsumerWidget {
  final int applicationId;

  const ApplicationDetailScreen({
    super.key,
    required this.applicationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(jobRepositoryProvider);
    final application = repo.getApplication(applicationId);

    if (application == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Detailansicht'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Bewerbung nicht gefunden.',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => context.go('/applications'),
                child: const Text('Zurück zur Übersicht'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(application.jobTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/applications'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(application.jobTitle,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.business, size: 18),
                        const SizedBox(width: 8),
                        Text(application.company,
                            style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.link, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            application.jobUrl,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _statusIcon(application.status),
                        const SizedBox(width: 8),
                        Text(
                          application.status.displayName,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Erstellt: ${_formatDate(application.createdAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (application.completedAt != null)
                      Text(
                        'Abgeschlossen: ${_formatDate(application.completedAt!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (application.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          application.errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // PDF Preview placeholder
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PDF-Vorschau',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),
                    Container(
                      height: 400,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf,
                                size: 64,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text(
                              application.status == ApplicationStatus.completed
                                  ? 'PDF-Vorschau wird hier angezeigt'
                                  : 'PDF wird noch generiert...',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                if (application.status == ApplicationStatus.completed ||
                    application.status == ApplicationStatus.exported)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PDF wird heruntergeladen...'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Als PDF speichern'),
                    ),
                  ),
                if (application.status == ApplicationStatus.completed ||
                    application.status == ApplicationStatus.exported) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Erneut generieren'),
                            content: const Text(
                              'Möchten Sie diese Bewerbung wirklich erneut generieren?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  repo.updateApplicationStatus(
                                    applicationId,
                                    ApplicationStatus.queued,
                                    pdfPath: null,
                                  );
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Neugenerierung gestartet.'),
                                    ),
                                  );
                                },
                                child: const Text('Erneut generieren'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut generieren'),
                    ),
                  ),
                ],
              ],
            ),
            if (application.status == ApplicationStatus.failed) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  repo.updateApplicationStatus(
                    applicationId,
                    ApplicationStatus.queued,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Generierung wird neu gestartet...'),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Neu starten'),
              ),
            ],
            const SizedBox(height: 12),

            // Delete button
            OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Bewerbung löschen'),
                    content: const Text(
                      'Möchten Sie diese Bewerbung wirklich löschen?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Abbrechen'),
                      ),
                      FilledButton(
                        onPressed: () {
                          repo.removeApplication(applicationId);
                          Navigator.pop(ctx);
                          context.go('/applications');
                        },
                        child: const Text('Löschen'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Löschen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(ApplicationStatus status) {
    switch (status) {
      case ApplicationStatus.queued:
        return const Icon(Icons.hourglass_empty, color: Colors.grey);
      case ApplicationStatus.processing:
        return const Icon(Icons.sync, color: Colors.blue);
      case ApplicationStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ApplicationStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case ApplicationStatus.exported:
        return const Icon(Icons.cloud_done, color: Colors.teal);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}