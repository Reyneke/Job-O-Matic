import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/services/ai/cover_letter_ai_service.dart';
import '../../models/application.dart';
import 'send_screen.dart';

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

            // Anschreiben-Text (KI-generiert / manuell bearbeitet) – Phase 3
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Anschreiben',
                            style: theme.textTheme.titleMedium),
                        const Spacer(),
                        // KI-Neugenerierung erzwingen – auch wenn bereits ein Text
                        // persistiert ist (doc/plan/11-Probleme.md „Anfrage KI-generierung").
                        if (repo.kiAnschreibenEnabled)

                          TextButton.icon(
                            onPressed: () =>
                                _regenerateWithAi(context, repo, applicationId),
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Mit KI neu generieren'),
                          ),
                        TextButton.icon(
                          onPressed: () => _editCoverLetter(
                            context,
                            repo,
                            applicationId,
                            application.coverLetterText ?? '',
                          ),
                          icon: const Icon(Icons.edit, size: 18),
                          label: Text(
                            application.coverLetterText?.isNotEmpty == true
                                ? 'Bearbeiten'
                                : 'Hinzufügen',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (application.coverLetterText?.isNotEmpty == true)
                      InkWell(
                        onTap: () => _editCoverLetter(
                          context,
                          repo,
                          applicationId,
                          application.coverLetterText!,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            application.coverLetterText!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 12,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    else
                      Text(
                        repo.kiAnschreibenEnabled
                            ? 'Noch kein Anschreiben-Text gespeichert. Bei der nächsten '
                                'Generierung wird die KI versucht; schlägt sie fehl, wird '
                                'automatisch die Vorlage verwendet. Du kannst den Text hier '
                                'auch manuell hinzufügen oder mit „Mit KI neu generieren" '
                                'sofort von der KI erstellen lassen.'
                            : 'Noch kein Anschreiben-Text gespeichert. Er wird bei der '
                                'nächsten Generierung aus der Vorlage erzeugt – oder hier '
                                'manuell hinzufügen.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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

            // Wiederversand / Versand einzelner Bewerbung (Phase E)
            if (application.pdfPath != null &&
                (application.status == ApplicationStatus.completed ||
                    application.status == ApplicationStatus.exported))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton.icon(
                  onPressed: () => context.push(
                    '/send',
                    extra: SendRequest(applicationId: application.id),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('Per E-Mail senden'),
                ),
              ),

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

  /// Erzwingt eine sofortige KI-Neugenerierung des Anschreiben-Textes und
  /// zeigt das Ergebnis als Snackbar an.
  ///
  /// Nutzt [JobRepository.regenerateCoverLetterWithAi]. Der neue Text wird
  /// in der DB gespeichert; die PDF muss anschließend erneut generiert
  /// werden, damit die Änderung in der Datei landet.
  Future<void> _regenerateWithAi(
    BuildContext context,
    JobRepository repo,
    int applicationId,
  ) async {
    try {
      await repo.regenerateCoverLetterWithAi(applicationId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Anschreiben wurde neu von der KI generiert. '
              'Bitte danach die PDF erneut generieren.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on CoverLetterAiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('KI-Generierung fehlgeschlagen: ${e.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Öffnet den Dialog zum Bearbeiten des Anschreiben-Texts und
  /// speichert Änderungen über das Repository zurück in die DB.
  ///
  /// Kleine manuelle Korrekturen erfordern so keine KI-Neugenerierung
  /// (siehe doc/plan/13-Anschreiben-KI.md, Phase 3).
  Future<void> _editCoverLetter(
    BuildContext context,
    JobRepository repo,
    int applicationId,
    String initialText,
  ) async {
    final controller = TextEditingController(text: initialText);
    final theme = Theme.of(context);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anschreiben bearbeiten'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 14,
            autofocus: initialText.isEmpty,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Anschreiben-Text (Absätze durch Leerzeilen trennen)...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );

    final newText = controller.text.trim();
    controller.dispose();

    if (saved != true || newText == initialText.trim()) return;

    try {
      await repo.saveCoverLetterText(applicationId, newText);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anschreiben gespeichert.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    }
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