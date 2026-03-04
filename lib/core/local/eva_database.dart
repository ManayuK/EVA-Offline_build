
library eva_database;

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class EvaDatabase {
  static final EvaDatabase _instance = EvaDatabase._();
  static Database? _db;

  EvaDatabase._();
  factory EvaDatabase() => _instance;

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  static Future<void> closeAndReset() async {
    try {
      if (_db != null && _db!.isOpen) await _db!.close();
    } catch (_) {}
    _db = null;
  }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'eva_v3.db');
    return openDatabase(path, version: 3, onCreate: _create, onUpgrade: _upgrade);
  }

  // ── Schema ──────────────────────────────────────────────────────────────────

  Future<void> _create(Database db, int version) async {
    await _createAll(db);
  }

  Future<void> _upgrade(Database db, int old, int next) async {
    // Simplest safe upgrade: recreate everything missing.
    await _createAll(db);
  }

  Future<void> _createAll(Database db) async {
    final batch = db.batch();

    // ── users ──────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        email           TEXT UNIQUE NOT NULL DEFAULT '',
        username        TEXT,
        date_of_birth   TEXT,
        avg_cycle_length  INTEGER DEFAULT 28,
        avg_period_length INTEGER DEFAULT 5,
        height_cm       REAL,
        weight_kg       REAL,
        fitness_level   TEXT DEFAULT 'moderate',
        health_goals    TEXT,     -- JSON list
        avg_sleep_hours REAL DEFAULT 7.0,
        avg_stress_level INTEGER DEFAULT 5,
        dietary_preference TEXT DEFAULT 'omnivore',
        onboarding_completed INTEGER DEFAULT 0,
        created_at      TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // ── cycles ─────────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS cycles (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id               INTEGER NOT NULL DEFAULT 1,
        start_date            TEXT NOT NULL,
        end_date              TEXT,
        predicted_end_date    TEXT,
        cycle_length          INTEGER,
        period_length         INTEGER,
        flow_intensity        TEXT,
        ovulation_date        TEXT,
        ovulation_predicted   INTEGER DEFAULT 0,
        fertile_window_start  TEXT,
        fertile_window_end    TEXT,
        is_regular            INTEGER DEFAULT 1,
        notes                 TEXT,
        created_at            TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_cycles_date ON cycles(start_date)');

    // ── mood_logs ──────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS mood_logs (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id          INTEGER NOT NULL DEFAULT 1,
        date             TEXT NOT NULL,
        primary_mood     TEXT NOT NULL,
        secondary_moods  TEXT,  -- JSON list
        intensity        REAL,
        emotion_scores   TEXT,  -- JSON
        stress_level     REAL,
        sleep_hours      REAL,
        energy_level     INTEGER,
        social_activity  INTEGER,
        exercise         INTEGER,
        notes            TEXT,
        created_at       TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_moods_date ON mood_logs(date)');

    // ── symptoms ───────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS symptoms (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id      INTEGER NOT NULL DEFAULT 1,
        cycle_id     INTEGER,
        date         TEXT NOT NULL,
        symptom_type TEXT NOT NULL,
        severity     INTEGER,
        triggers     TEXT,   -- JSON list
        relief_methods TEXT, -- JSON list
        notes        TEXT,
        created_at   TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_symptoms_date ON symptoms(date)');

    // ── journal_entries ────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id                        INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id                   INTEGER NOT NULL DEFAULT 1,
        date                      TEXT NOT NULL,
        entry_text                TEXT NOT NULL,
        emotion_analysis          TEXT,  -- JSON
        sentiment_score           REAL,
        primary_emotion           TEXT,
        keywords                  TEXT,  -- JSON list
        topics                    TEXT,  -- JSON list
        mental_health_concern     INTEGER DEFAULT 0,
        crisis_detected           INTEGER DEFAULT 0,
        support_recommended       INTEGER DEFAULT 0,
        word_count                INTEGER,
        model_version             TEXT,
        created_at                TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_journal_date ON journal_entries(date)');

    // ── sleep_logs ─────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sleep_logs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     INTEGER NOT NULL DEFAULT 1,
        date        TEXT NOT NULL,
        hours_slept REAL,
        quality     INTEGER,
        wake_time   TEXT,
        bed_time    TEXT,
        had_dreams  INTEGER,
        dream_notes TEXT,
        notes       TEXT,
        created_at  TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_sleep_date ON sleep_logs(date)');

    // ── weight_logs ────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS weight_logs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id    INTEGER NOT NULL DEFAULT 1,
        date       TEXT NOT NULL,
        weight_kg  REAL NOT NULL,
        bmi        REAL,
        waist_cm   REAL,
        hips_cm    REAL,
        bust_cm    REAL,
        notes      TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_weight_date ON weight_logs(date)');

    // ── ovulation_logs ─────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS ovulation_logs (
        id                       INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id                  INTEGER NOT NULL DEFAULT 1,
        cycle_id                 INTEGER,
        date                     TEXT NOT NULL,
        discharge_type           TEXT,
        basal_temp               REAL,
        had_cramps               INTEGER,
        lh_surge                 INTEGER,
        other_signs              TEXT,   -- JSON list
        predicted_ovulation_date TEXT,
        days_off_prediction      INTEGER,
        notes                    TEXT,
        created_at               TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // ── pms_feedback ───────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS pms_feedback (
        id                        INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id                   INTEGER NOT NULL DEFAULT 1,
        cycle_id                  INTEGER,
        predicted_pms_date        TEXT,
        pms_arrived_as_predicted  INTEGER,
        actual_pms_start          TEXT,
        pms_severity              INTEGER,
        notes                     TEXT,
        created_at                TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // ── user_kalman_states ─────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS user_kalman_states (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id           INTEGER NOT NULL UNIQUE,
        kalman_mean       REAL DEFAULT 28.5,
        kalman_variance   REAL DEFAULT 25.0,
        n_observations    INTEGER DEFAULT 0,
        cycle_history     TEXT DEFAULT '[]',    -- JSON list
        sentiment_history TEXT DEFAULT '[]',    -- JSON list
        updated_at        TEXT NOT NULL DEFAULT (datetime('now')),
        created_at        TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // ── predictions ────────────────────────────────────────────────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS predictions (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id          INTEGER NOT NULL DEFAULT 1,
        prediction_type  TEXT,
        created_at       TEXT NOT NULL DEFAULT (datetime('now')),
        prediction_date  TEXT,
        predicted_value  TEXT,  -- JSON
        confidence_score REAL,
        model_version    TEXT,
        actual_value     TEXT,  -- JSON
        accuracy         REAL
      )
    ''');

    // ── chat_messages (shared with existing DatabaseHelper) ───────────────
    batch.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        user_key  TEXT    NOT NULL,
        session   TEXT    NOT NULL,
        role      TEXT    NOT NULL,
        content   TEXT    NOT NULL,
        ts        TEXT    NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX IF NOT EXISTS idx_chat_user_session ON chat_messages(user_key, session)');

    await batch.commit(noResult: true);
  }

  // ── Convenience helpers ───────────────────────────────────────────────────

  Future<int> insert(String table, Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset);
  }

  Future<int> update(String table, Map<String, dynamic> row,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    return db.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table,
      {String? where, List<dynamic>? whereArgs}) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> rawQuery(String sql,
      [List<dynamic>? args]) async {
    final db = await database;
    return db.rawQuery(sql, args);
  }

  Future<void> rawInsert(String sql, [List<dynamic>? args]) async {
    final db = await database;
    await db.rawInsert(sql, args);
  }

  // ── JSON helpers ──────────────────────────────────────────────────────────

  static String encodeList(List<dynamic> list) => jsonEncode(list);
  static List<dynamic> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final d = jsonDecode(raw);
      return d is List ? d : [];
    } catch (_) {
      return [];
    }
  }

  static String encodeMap(Map<String, dynamic> m) => jsonEncode(m);
  static Map<String, dynamic> decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }
}
