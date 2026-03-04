// lib/core/di/injection.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../core/providers/dashboard_provider.dart';
import '../services/api_service.dart';
import '../services/llm_service.dart';
import '../services/tts_service.dart';
import '../services/chat_local_repository.dart';
import '../database/database_helper.dart';
import '../local/local_database_service.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  final sharedPrefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPrefs);

  // sqflite + TFLite not supported on Flutter Web
  if (!kIsWeb) {
    getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());
    getIt.registerLazySingleton<ChatLocalRepository>(
        () => ChatLocalRepository(getIt<DatabaseHelper>(), null));
  } else {
    getIt.registerLazySingleton<ChatLocalRepository>(
        () => ChatLocalRepository(null, getIt<SharedPreferences>()));
  }

  // Keep ApiService registered (used by chat_page history fetch + profile ping)
  getIt.registerLazySingleton<ApiService>(() => ApiService());

  // ── On-device service: replaces every FastAPI call on native platforms ──
  getIt.registerLazySingleton<LocalDatabaseService>(() => LocalDatabaseService());

  // On-device LLM — single instance shared by Chat, Journal, and Home pages
  getIt.registerLazySingleton<LlmService>(() => LlmService());

  // Text-to-Speech
  getIt.registerLazySingleton<TtsService>(
    () => TtsService(getIt<SharedPreferences>()),
  );

  // AuthProvider
  getIt.registerFactory<AuthProvider>(
    () => AuthProvider(
      prefs:      getIt<SharedPreferences>(),
    ),
  );

  // DashboardProvider now uses LocalDatabaseService — fully offline
  getIt.registerFactory<DashboardProvider>(
    () => DashboardProvider(localDb: getIt<LocalDatabaseService>()),
  );
}
