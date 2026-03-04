import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'core/di/injection.dart';
import 'core/services/api_service.dart';
import 'core/services/llm_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'core/providers/dashboard_provider.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/journal/presentation/pages/journal_page.dart';
import 'features/insights/presentation/pages/insights_page.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/cycles/presentation/pages/log_cycle_page.dart';
import 'features/cycles/presentation/pages/cycles_history_page.dart';
import 'features/onboarding/presentation/pages/onboarding_page.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/health/presentation/pages/sleep_log_page.dart';
import 'features/health/presentation/pages/weight_tracker_page.dart';
import 'features/calendar/presentation/pages/calendar_page.dart';
import 'core/navigation/shell_page.dart';
import 'core/ml/onnx_cycle_predictor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init ONNX model in the background — falls back to statistical baseline
  // automatically if the asset is missing or the runtime fails to load.
  unawaited(OnnxCyclePredictorService.instance.init());

  // Load persisted backend URL (user sets their PC's LAN IP in Profile)
  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('backend_url');
  if (savedUrl != null && savedUrl.isNotEmpty) {
    ApiService.setBaseUrl(savedUrl);
  }

  await LlmService.initBackend();
  await setupDependencies();

  // Auto-load LLM model if already cached from a previous session
  final llm = getIt<LlmService>();
  final cached = await llm.isModelCached();
  if (cached) unawaited(llm.downloadAndLoad());

  runApp(const EVAApp());
}

class EVAApp extends StatefulWidget {
  const EVAApp({super.key});

  @override
  State<EVAApp> createState() => _EVAAppState();
}

class _EVAAppState extends State<EVAApp> {
  late final AuthProvider _auth;
  late final GoRouter     _router;

  @override
  void initState() {
    super.initState();
    _auth = getIt<AuthProvider>()..initialize();

    _router = GoRouter(
      // ── Start directly at home (or onboarding if not yet done) ─────────────
      initialLocation: '/home',
      refreshListenable: _auth,
      redirect: (context, state) {
        // Wait until local profile has been loaded from prefs
        if (_auth.isLoading) return null;

        final loc          = state.matchedLocation;
        final isOnboarding = loc == '/onboarding';

        // If onboarding not finished yet, redirect there (except when already there)
        if (!_auth.onboardingCompleted && !isOnboarding) {
          // Allow sub-routes like /log-cycle, /sleep, /weight to pass through
          const bypassRoutes = ['/log-cycle', '/cycles', '/sleep', '/weight'];
          if (!bypassRoutes.contains(loc)) return '/onboarding';
        }

        // Onboarding done but still on onboarding screen → go home
        if (_auth.onboardingCompleted && isOnboarding) return '/home';

        return null;
      },
      routes: [
        GoRoute(path: '/log-cycle',  builder: (_, __) => const LogCyclePage()),
        GoRoute(path: '/cycles',     builder: (_, __) => const CyclesHistoryPage()),
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
        GoRoute(path: '/sleep',      builder: (_, __) => const SleepLogPage()),
        GoRoute(path: '/weight',     builder: (_, __) => const WeightTrackerPage()),
        ShellRoute(
          builder: (context, state, child) => ShellPage(child: child),
          routes: [
            GoRoute(path: '/home',     builder: (_, __) => const HomePage()),
            GoRoute(path: '/journal',  builder: (_, __) => const JournalPage()),
            GoRoute(path: '/chat',     builder: (_, __) => const ChatPage()),
            GoRoute(path: '/insights', builder: (_, __) => const InsightsPage()),
            GoRoute(path: '/calendar', builder: (_, __) => const CalendarPage()),
            GoRoute(path: '/profile',  builder: (_, __) => const ProfilePage()),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => getIt<DashboardProvider>(),
        ),
      ],
      child: MaterialApp.router(
        title: 'EVA - Wellness Assistant',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        routerConfig: _router,
      ),
    );
  }
}
