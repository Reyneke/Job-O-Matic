import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import '../../data/repositories/job_repository.dart';

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

  final List<Map<String, String>> _searchResults = [];

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

    setState(() => _isSearching = true);
    _log.info('Jobsuche gestartet: "$jobDesc", Ort: "$location", Umkreis: ${_radius}km');

    // Simulate API search (placeholder for real API integration)
    await Future.delayed(const Duration(seconds: 2));

    // Mock results (will be replaced by actual API calls later)
    final mockResults = [
      {'title': 'Softwareentwickler (m/w/d)', 'company': 'Tech GmbH', 'location': location.isNotEmpty ? location : 'Berlin', 'id': 'job_001'},
      {'title': 'Flutter Developer (m/w/d)', 'company': 'App Factory', 'location': location.isNotEmpty ? location : 'Berlin', 'id': 'job_002'},
      {'title': 'Full Stack Developer (m/w/d)', 'company': 'Web Solutions AG', 'location': location.isNotEmpty ? location : 'Berlin', 'id': 'job_003'},
    ];

    setState(() {
      _searchResults.clear();
      _searchResults.addAll(mockResults);
      _isSearching = false;
    });
    _log.info('Jobsuche abgeschlossen: ${mockResults.length} Ergebnisse');
  }

  void _adoptResults(List<String> selectedIds) {
    ref.read(jobRepositoryProvider).addJobsFromSearch(selectedIds);
    _log.info('Jobs übernommen: ${selectedIds.length}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selectedIds.length} Job(s) übernommen.'),
        backgroundColor: Colors.green,
      ),
    );
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
                      subtitle: Text('${result['company']} – ${result['location']}'),
                      trailing: FilledButton.tonalIcon(
                        onPressed: () => _adoptResults([result['id']!]),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Übernehmen'),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _adoptResults(
                    _searchResults.map((r) => r['id']!).toList()),
                icon: const Icon(Icons.download_done),
                label: const Text('Alle übernehmen & weiter'),
              ),
            ],

            // Empty state
            if (_searchResults.isEmpty && !_isSearching)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 64, color: theme.colorScheme.onSurfaceVariant),
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