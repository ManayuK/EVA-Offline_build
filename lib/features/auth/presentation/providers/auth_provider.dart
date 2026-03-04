import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../../../core/local/eva_database.dart';
import '../../../../core/database/database_helper.dart';

class AuthProvider extends ChangeNotifier {
  final SharedPreferences prefs;

  AuthProvider({required this.prefs});

  // ── State ──────────────────────────────────────────────────────────────────
  bool         _isLoading       = true;
  bool         _isAuthenticated = false;
  String?      _error;
  UserProfile? _currentUser;

  bool         get isLoading        => _isLoading;
  bool         get isAuthenticated  => _isAuthenticated;
  String?      get error            => _error;
  UserProfile? get currentUser      => _currentUser;
  bool get onboardingCompleted      => _currentUser?.onboardingCompleted ?? false;

  static const _kProfile = 'local_profile';

  // ── Initialise — always auto-authenticate ──────────────────────────────────
  Future<void> initialize() async {
    final stored = prefs.getString(_kProfile);
    if (stored != null) {
      try {
        _currentUser = UserProfile.fromJson(
            jsonDecode(stored) as Map<String, dynamic>);
      } catch (_) {
        _currentUser = _defaultProfile();
        await _saveProfile();
      }
    } else {
      _currentUser = _defaultProfile();
      await _saveProfile();
    }
    _isAuthenticated = true;
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> ensureToken() async => true;

  // ── Update display name ────────────────────────────────────────────────────
  Future<void> updateName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _currentUser = UserProfile(
      name:                trimmed,
      localEmail:          _currentUser?.localEmail ?? '',
      cycleLength:         _currentUser?.cycleLength ?? 28,
      periodLength:        _currentUser?.periodLength ?? 5,
      onboardingCompleted: _currentUser?.onboardingCompleted ?? false,
    );
    await _saveProfile();
    notifyListeners();
  }

  // ── Profile updates ────────────────────────────────────────────────────────
  Future<void> updateProfile({
    String? name,
    int?    cycleLength,
    int?    periodLength,
    bool?   onboardingCompleted,
  }) async {
    _currentUser = UserProfile(
      name:                name                ?? _currentUser?.name                ?? 'Me',
      localEmail:          _currentUser?.localEmail ?? '',
      cycleLength:         cycleLength         ?? _currentUser?.cycleLength         ?? 28,
      periodLength:        periodLength        ?? _currentUser?.periodLength        ?? 5,
      onboardingCompleted: onboardingCompleted ?? _currentUser?.onboardingCompleted ?? false,
    );
    await _saveProfile();
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    await updateProfile(onboardingCompleted: true);
  }

  Future<void> resetAppData() async {
    // 1. Clear all SharedPreferences
    await prefs.clear();

    // 2. Close DB handles FIRST — singletons hold open file handles.
    //    Nulling _db means the next access calls openDatabase() fresh.
    await EvaDatabase.closeAndReset();
    await DatabaseHelper.closeAndReset();

    // 3. Delete the files now that handles are closed.
    //    The downloaded Ollama model (app files dir) is NOT touched.
    try {
      final dbPath = await getDatabasesPath();
      for (final name in ['eva_v3.db', 'eva_wellness.db']) {
        try { await deleteDatabase(p.join(dbPath, name)); } catch (_) {}
      }
    } catch (_) {}

    _currentUser     = _defaultProfile();
    _isAuthenticated = true;
    _error           = null;
    _isLoading       = false;
    notifyListeners();
  }

  void clearError() { _error = null; notifyListeners(); }

  UserProfile _defaultProfile() => const UserProfile(
        name: 'Me', localEmail: '', cycleLength: 28,
        periodLength: 5, onboardingCompleted: false);

  Future<void> _saveProfile() async =>
      prefs.setString(_kProfile, jsonEncode(_currentUser!.toJson()));
}

// ── UserProfile ───────────────────────────────────────────────────────────────
class UserProfile {
  final String name;
  final String localEmail;
  final int    cycleLength;
  final int    periodLength;
  final bool   onboardingCompleted;

  String get email => localEmail;
  int?   get id    => null;

  const UserProfile({
    required this.name,
    required this.localEmail,
    this.cycleLength         = 28,
    this.periodLength        = 5,
    this.onboardingCompleted = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name:                j['name']                 as String? ?? 'Me',
        localEmail:          j['local_email']          as String? ?? '',
        cycleLength:         (j['cycle_length']  as num?)?.toInt() ?? 28,
        periodLength:        (j['period_length'] as num?)?.toInt() ?? 5,
        onboardingCompleted: j['onboarding_completed'] == true,
      );

  Map<String, dynamic> toJson() => {
        'name':                 name,
        'local_email':          localEmail,
        'cycle_length':         cycleLength,
        'period_length':        periodLength,
        'onboarding_completed': onboardingCompleted,
      };
}
