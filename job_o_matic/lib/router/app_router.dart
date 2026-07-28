import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../presentation/screens/job_input_screen.dart';
import '../presentation/screens/job_search_screen.dart';
import '../presentation/screens/application_list_screen.dart';
import '../presentation/screens/application_detail_screen.dart';
import '../presentation/screens/api_key_settings_screen.dart';
import '../data/repositories/job_repository.dart';

/// Riverpod provider for the GoRouter instance.
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isApplicationsRoute = state.matchedLocation == '/applications' ||
          state.matchedLocation.startsWith('/applications/');
      if (isApplicationsRoute) {
        // Read current repository state dynamically on every navigation
        final repo = ref.read(jobRepositoryProvider);
        if (!repo.hasValidApplications) {
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'jobInput',
        builder: (context, state) => const JobInputScreen(),
      ),
      GoRoute(
        path: '/search',
        name: 'jobSearch',
        builder: (context, state) => const JobSearchScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'apiKeySettings',
        builder: (context, state) => const ApiKeySettingsScreen(),
      ),
      GoRoute(
        path: '/applications',
        name: 'applicationList',
        builder: (context, state) => const ApplicationListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'applicationDetail',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return ApplicationDetailScreen(applicationId: id);
            },
          ),
        ],
      ),
    ],
  );
});