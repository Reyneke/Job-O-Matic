import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/repositories/job_repository.dart';
import '../../models/application.dart';

/// Screen 3a: Detail view of a single application.
///
/// Shows PDF preview, metadata,
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
                onPressed: () => context.pop(),
                child: const Text('Zurück zur Übersicht'),
              ),
            ],
          ),
        ),
      );
    }

    final hasPdf = application.pdfPath != null &&
        application.status == ApplicationStatus.completed;

    return Scaffold(
      appBar: AppBar(
        title: Text(application.jobTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
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
                    if (application.pdfPath != null)
                      Text(
                        'PDF: ${application.pdfPath!.split('/').last}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
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

            // PDF Preview
            if (hasPdf)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('PDF-Vorschau',
                              style: theme.textTheme.titleMedium),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.share),
                            tooltip: 'PDF teilen',
                            onPressed: () => _sharePdf(application.pdfPath!),
                          ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new),
                            tooltip: 'Dateiordner öffnen',
                            onPressed: () => _openFile(application.pdfPath!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 500,
                        child: PdfPreview(
                          build: (format) async {
                            final file = File(application.pdfPath!);
                            return file.readAsBytes();
                          },
                          allowPrinting: true,
                          allowSharing: true,
                          pdfFileName: 'Bewerbung_${application.company}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Fallback wenn kein PDF
            if (!hasPdf && application.status == ApplicationStatus.completed)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.picture_as_pdf,
                          size: 48, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      const Text('PDF-Datei nicht gefunden'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          repo.updateApplicationStatus(
                            applicationId,
                            ApplicationStatus.queued,
                            pdfPath: null,
                          );
                        },
                        child: const Text('Erneut generieren'),
                      ),
                    ],
                  ),
                ),
              ),

            if (application.status == ApplicationStatus.queued ||
                application.status == ApplicationStatus.processing)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          application.status == ApplicationStatus.processing
                              ? 'PDF wird generiert...'
                              : 'Wartet auf Generierung...',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                if (hasPdf)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _sharePdf(application.pdfPath!),
                      icon: const Icon(Icons.share),
                      label: const Text('PDF teilen'),
                    ),
                  ),
                if (hasPdf) const SizedBox(width: 12),
                if (hasPdf)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Erneut generieren'),
                            content: const Text(
                              'Möchten Sie diese Bewerbung wirklich erneut generieren?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Erneut generieren'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          try {
                            await repo.generatePdf(applicationId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('PDF erfolgreich generiert.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Fehler: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut generieren'),
                    ),
                  ),
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
                          context.pop();
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

  Future<void> _sharePdf(String pdfPath) async {
    final file = File(pdfPath);
    if (await file.exists()) {
      await Share.shareXFiles(
        [XFile(pdfPath)],
        text: 'Bewerbungsunterlagen',
      );
    }
  }

  void _openFile(String pdfPath) {
    try {
      final file = File(pdfPath);
      final folder = file.parent.absolute.path;
      // Öffne den übergeordneten Ordner im Explorer
      Process.start('explorer', [folder]);
    } catch (e) {
      // Ignore on platforms without explorer
    }
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