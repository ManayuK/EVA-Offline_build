import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/local/local_database_service.dart';

class DashboardProvider extends ChangeNotifier {
  final LocalDatabaseService localDb;

  DashboardProvider({required this.localDb});

  LocalDashboardData? _dashboard;
  List<LocalSuggestionData> _suggestions = [];
  List<LocalHealthRisk> _healthRisks = [];

  bool _isLoading = false;
  bool _isSuggestionsLoading = false;
  bool _isRisksLoading = false;
  bool _isRefreshing = false;
  String? _error;

  LocalDashboardData? get dashboard => _dashboard;
  List<LocalSuggestionData> get suggestions => _suggestions;
  List<LocalHealthRisk> get healthRisks => _healthRisks;
  bool get isLoading => _isLoading;
  bool get isSuggestionsLoading => _isSuggestionsLoading;
  bool get isRisksLoading => _isRisksLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;

  Future<void> loadDashboard() async {
    if (_dashboard != null) {
      _isRefreshing = true;
      notifyListeners();
      try {
        _dashboard = await localDb.getDashboard();
        _error = null;
      } catch (e) {
        _error = e.toString();
      }
      _isRefreshing = false;
      notifyListeners();
      // Refresh suggestions/risks after dashboard updates
      unawaited(loadSuggestions());
      unawaited(loadHealthRisks());
    } else {
      _isLoading = true;
      _error = null;
      notifyListeners();
      try {
        _dashboard = await localDb.getDashboard();
      } catch (e) {
        _error = e.toString();
      }
      _isLoading = false;
      notifyListeners();
      // Load suggestions/risks once dashboard is ready
      unawaited(loadSuggestions());
      unawaited(loadHealthRisks());
    }
  }

  Future<void> loadSuggestions() async {
    _isSuggestionsLoading = true;
    notifyListeners();
    try {
      _suggestions = await localDb.getSuggestions();
    } catch (_) {}
    _isSuggestionsLoading = false;
    notifyListeners();
  }

  Future<void> loadHealthRisks() async {
    _isRisksLoading = true;
    notifyListeners();
    try {
      _healthRisks = await localDb.getHealthRisks();
    } catch (_) {}
    _isRisksLoading = false;
    notifyListeners();
  }

  Future<void> logCycle(String startDate) async {
    try {
      await localDb.logCycleStart(startDate);
      _dashboard = null; // force full reload after cycle log
      await loadDashboard();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void invalidateCache() {
    _dashboard = null;
  }

  void resetState() {
    _dashboard       = null;
    _suggestions     = [];
    _healthRisks     = [];
    _error           = null;
    _isLoading       = false;
    _isRefreshing    = false;
    notifyListeners();
  }
}
