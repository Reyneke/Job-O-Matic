import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../data/repositories/job_repository.dart';
import '../../core/providers/providers.dart';

/// Screen 2: Job search interface.
///
/// Allows searching for jobs via keywords, location, and radius.
/// Results can be transferred to the application list.
class JobSearchScreen extends ConsumerStatefulWidget {
  const JobSearchScreen({super.key});

  @override
  ConsumerState<JobSearchScreen> createState() => _JobSearchScreenState();
}

class _JobSearchScreenState extends ConsumerState<JobSearchScreen> {
  final Logger _log = Logger('JobSearchScreen');
  final TextEditingController _jobController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  double _radius = 25;
  bool _isSearching = false;
  String? _searchError;

  final List<Map<String, String>> _searchResults = [];
  int _adoptedJobCount = 0;

  @override
  void dispose() {
    _jobController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final jobDesc = _jobController.text.trim();
    final location = _locationController.text.trim();

    if (jobDesc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte geben Sie eine Jobbeschreibung ein.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    _log.info(
        'Jobsuche gestartet: "$jobDesc", Ort: "$location", Umkreis: ${_radius}km');

    try {
      final searchService = ref.read(jobSearchServiceProvider);
      final result = await searchService.searchJobs(
        query: jobDesc,
        location: location.isNotEmpty ? location : null,
        radius: _radius.round(),
      );

      if (!context.mounted) return;

      setState(() {
        _searchResults.clear();
        _searchResults.addAll(result.jobs.map((job) => {
              'title': job.title,
              'company': job.company,
              'location': job.location ?? (location.isNotEmpty ? location : 'Unbekannt'),
              'id': job.id,
            }));
        _searchError = result.errorMessage;
        _isSearching = false;
      });
      _log.info('Jobsuche abgeschlossen: ${result.jobs.length} Ergebnisse');

      if (_searchError != null && _searchResults.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API-Fehler: $_searchError'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      _log.severe('Jobsuche fehlgeschlagen: $e');
      if (!context.mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Unbekannter Fehler: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler bei der Jobsuche: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _adoptResults(List<Map<String, String>> jobs,
      {bool navigateToApplications = false}) {
    final repo = ref.read(jobRepositoryProvider);
    for (final job in jobs) {
      repo.addApplication(
        jobTitle: job['title'] ?? 'Unbekannte Stelle',
        company: job['company'] ?? 'Unbekanntes Unternehmen',
        jobUrl: '',
      );
    }
    setState(() => _adoptedJobCount += jobs.length);
    _log.info('Jobs übernommen: ${jobs.length}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${jobs.length} Job(s) übernommen.'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    if (navigateToApplications) {
      context.go('/applications');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobsuche'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search header
            Text('Stellen suchen', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),

            // Job description
            TextField(
              controller: _jobController,
              decoration: const InputDecoration(
                labelText: 'Jobbeschreibung',
                hintText: 'z. B. Flutter Developer, Softwareentwickler',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.work),
              ),
            ),
            const SizedBox(height: 12),

            // Location
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Ort',
                hintText: 'z. B. Berlin, Hamburg, München',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 12),

            // Radius slider
            Row(
              children: [
                const Icon(Icons.radio_button_checked),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Umkreis: ${_radius.round()} km'),
                      Slider(
                        value: _radius,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        label: '${_radius.round()} km',
                        onChanged: (value) => setState(() => _radius = value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search button
            FilledButton.icon(
              onPressed: _isSearching ? null : _performSearch,
              icon: _isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isSearching ? 'Suche läuft...' : 'Suchen'),
            ),
            const SizedBox(height: 24),

            // Error message banner
            if (_searchError != null && _searchResults.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: theme.colorScheme.onErrorContainer, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'API-Fehler: $_searchError\n\n'
                        'Hinweis: Die BA-Jobsuche benötigt einen kostenlosen API-Key. '
                        'Registrieren Sie sich unter https://jobsuche.api.bund.dev/ '
                        'und speichern Sie den Key als "ba_jobboerse" in den '
                        'App-Einstellungen (flutter_secure_storage).',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Results
            if (_searchResults.isNotEmpty) ...[
              Text(
                'Suchergebnisse (${_searchResults.length})',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ..._searchResults.map((result) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.business_center),
                      title: Text(result['title']!),
                      subtitle:
                          Text('${result['company']} – ${result['location']}'),
                      trailing: FilledButton.tonalIcon(
                        onPressed: () => _adoptResults([result]),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Übernehmen'),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _adoptResults(
                    _searchResults,
                    navigateToApplications: true),
                icon: const Icon(Icons.download_done),
                label: const Text('Alle übernehmen & weiter'),
              ),
              // Weiter-Button, wenn bereits Jobs übernommen wurden
              if (_adoptedJobCount > 0) ...[
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: () => context.go('/applications'),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Weiter zur Verarbeitung'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              ],
            ],

            // Empty state
            if (_searchResults.isEmpty && !_isSearching && _searchError == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        'Geben Sie Suchkriterien ein,\num passende Stellen zu finden.',
                        textAlign: TextAlign.center,
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
    );
  }
}