import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../core/providers/providers.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/services/autosave_service.dart';
import '../../data/services/api/job_scraper_service.dart';

/// Screen 1: Input mask for job URLs.
///
/// Allows the user to enter one or more job URLs in a textarea.
/// URLs are validated and persisted before navigating to the application list.
/// Also shows already adopted jobs from the search screen.
/// Features Autosave with 5-second debounce for the URL textarea.
class JobInputScreen extends ConsumerStatefulWidget {
  const JobInputScreen({super.key});

  @override
  ConsumerState<JobInputScreen> createState() => _JobInputScreenState();
}

class _JobInputScreenState extends ConsumerState<JobInputScreen> {
  final Logger _log = Logger('JobInputScreen');
  final TextEditingController _urlController = TextEditingController();
  AutosaveService? _autosaveService;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    // Initialize repository from database when entering the input screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(jobRepositoryProvider).initialize();
      _initAutosave();
    });
  }

  void _initAutosave() {
    _autosaveService = ref.read(autosaveServiceProvider);
    final repo = ref.read(jobRepositoryProvider);

    // Restore last saved URLs
    final lastInput = repo.autoSavedInput;
    if (lastInput != null && lastInput.isNotEmpty) {
      _urlController.text = lastInput;
      _log.fine('Autosave: Wiederhergestellte Eingabe');
    }

    _autosaveService!.start(() async {
      final urlText = _urlController.text;
      if (urlText.isNotEmpty) {
        repo.saveAutoSavedInput(urlText);
        _log.fine('Autosave: Eingabe gespeichert (${urlText.length} Zeichen)');
      }
    });
  }

  @override
  void dispose() {
    _autosaveService?.stop();
    _urlController.dispose();
    super.dispose();
  }

  /// Validate the entered URLs.
  List<String> _validateUrls() {
    final lines = _urlController.text
        .split(RegExp(r'[\n,;]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final validUrls = <String>[];
    final invalidUrls = <String>[];

    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        String normalized = uri.toString();
        if (normalized.endsWith('/')) {
          normalized = normalized.substring(0, normalized.length - 1);
        }
        if (!validUrls.contains(normalized)) {
          validUrls.add(normalized);
        }
      } else {
        invalidUrls.add(line);
      }
    }

    _log.info(
        'URL-Validierung: ${validUrls.length} gültig, ${invalidUrls.length} ungültig');
    return validUrls;
  }

  Future<void> _onContinue() async {
    final urls = _validateUrls();

    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte geben Sie mindestens eine gültige URL ein.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isValidating = true);

    // Store in repository
    final repo = ref.read(jobRepositoryProvider);
    repo.addValidatedUrls(urls);

    // Job-Details per Scraping extrahieren (Titel, Firma, Ort)
    try {
      final scraper = ref.read(jobScraperServiceProvider);
      final scrapedJobs = await scraper.extractJobs(urls);
      if (scrapedJobs.isNotEmpty) {
        final results = <String, JobScrapeResult>{
          for (final job in scrapedJobs)
            job.url: JobScrapeResult(
              title: job.title,
              company: job.company,
              location: job.location,
              description: job.description,
            ),
        };
        repo.saveScrapeResults(results);
        _log.info('Job-Details extrahiert: ${scrapedJobs.length} von ${urls.length} URLs');
      }
    } catch (e) {
      _log.warning('Scraping fehlgeschlagen – fahre ohne Job-Details fort: $e');
    }

    if (!mounted) return;
    setState(() => _isValidating = false);

    // Navigate to application list
    context.go('/applications');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(jobRepositoryProvider);
    final validatedUrls = repo.validatedUrls;
    final selectedJobIds = repo.selectedJobIds;
    final hasAdoptedItems =
        validatedUrls.isNotEmpty || selectedJobIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job-O-Matic'),
        centerTitle: true,
        actions: [
          // Zur Ergebnisübersicht (Debug-freundlich)
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Ergebnisübersicht',
            onPressed: () => context.go('/applications'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'API-Key Verwaltung',
            onPressed: () => context.go('/settings'),
          ),
          // Debug-Test-Runner – per Long-Press erreichbar
          Builder(builder: (context) {
            return IconButton(
              icon: const Icon(Icons.bug_report_outlined, size: 20),
              tooltip: 'Debug Test Runner (Long-Press)',
              onPressed: () {},
              onLongPress: () => context.go('/debug'),
            );
          }),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              'Stellenangebote eingeben',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Geben Sie die URLs der Stellenangebote ein (eine URL pro Zeile).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // URL Textarea
            Expanded(
              flex: 2,
              child: TextField(
                controller: _urlController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText:
                      'https://example.com/job/123\nhttps://example.com/job/456',
                  border: OutlineInputBorder(),
                  labelText: 'Stellen-URLs',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(height: 16),

            // Already added items list
            if (hasAdoptedItems) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Übernommene Stellen:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (validatedUrls.isNotEmpty) ...[
                      ...validatedUrls.map(
                        (url) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.link, size: 16),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  url,
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (selectedJobIds.isNotEmpty) ...[
                      if (validatedUrls.isNotEmpty)
                        const Divider(height: 8),
                      ...selectedJobIds.map(
                        (id) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.search, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'Job-ID: $id',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${validatedUrls.length + selectedJobIds.length} Stelle(n) bereit zur Verarbeitung',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/search'),
                    icon: const Icon(Icons.search),
                    label: const Text('Jobsuche'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isValidating || !hasAdoptedItems)
                        ? null
                        : () => context.go('/applications'),
                    icon: _isValidating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: Text(hasAdoptedItems ? 'Zur Verarbeitung' : 'Weiter'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Continue button for manual URL entry
            FilledButton.tonalIcon(
              onPressed: _isValidating ? null : _onContinue,
              icon: _isValidating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_link),
              label: const Text('URLs hinzufügen & weiter'),
            ),
          ],
        ),
      ),
    );
  }
}