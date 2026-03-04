
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';

// ── Domain model ──────────────────────────────────────────────────────────────

class LocalChatMessage {
  final int?     id;
  final String   userKey;
  final String   session;
  final String   role;
  final String   content;
  final DateTime ts;

  const LocalChatMessage({
    this.id,
    required this.userKey,
    required this.session,
    required this.role,
    required this.content,
    required this.ts,
  });

  factory LocalChatMessage.fromMap(Map<String, dynamic> m) => LocalChatMessage(
        id      : m['id']       as int?,
        userKey : m['user_key'] as String,
        session : m['session']  as String,
        role    : m['role']     as String,
        content : m['content']  as String,
        ts      : DateTime.parse(m['ts'] as String),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_key': userKey,
        'session' : session,
        'role'    : role,
        'content' : content,
        'ts'      : ts.toIso8601String(),
      };

  Map<String, dynamic> toApiJson() => {'role': role, 'content': content};
}

// ── Session descriptor ────────────────────────────────────────────────────────

class ChatSession {
  final String   session;
  final String   preview;
  final int      messageCount;
  final DateTime lastTs;

  const ChatSession({
    required this.session,
    required this.preview,
    required this.messageCount,
    required this.lastTs,
  });

  String get label {
    try {
      // Session key is either 'yyyy-MM-dd' (today session) or
      // 'yyyy-MM-dd_HH-mm-ss' (new unique session). Normalise both.
      final normalised = session.replaceFirst(
          RegExp(r'_\d{2}-\d{2}-\d{2}$'), '');
      final d = DateTime.parse(normalised);
      return DateFormat('EEE, d MMM yyyy').format(d);
    } catch (_) {
      return session; // fallback: show the raw key rather than crash
    }
  }
}

// ── Repository ────────────────────────────────────────────────────────────────

class ChatLocalRepository {
  final DatabaseHelper?      _db;    // non-null on mobile/desktop
  final SharedPreferences?   _prefs; // non-null on web

  ChatLocalRepository(this._db, this._prefs);

  // ── shared_preferences key helpers ───────────────────────────────────────
  // All web data lives under keys like "chat:<userKey>:<session>"
  // Each key stores a JSON-encoded List of message maps.

  String _prefKey(String userKey, String session) =>
      'chat:$userKey:$session';

  String _sessionsIndexKey(String userKey) => 'chat_sessions:$userKey';

  // ── Read all session keys for a user (web) ───────────────────────────────
  List<String> _webSessionKeys(String userKey) {
    final raw = _prefs!.getString(_sessionsIndexKey(userKey));
    if (raw == null || raw.isEmpty) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  Future<void> _webAddSessionToIndex(String userKey, String session) async {
    final keys = _webSessionKeys(userKey);
    if (!keys.contains(session)) {
      keys.add(session);
      await _prefs!.setString(_sessionsIndexKey(userKey), jsonEncode(keys));
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> saveMessage(LocalChatMessage msg) async {
    if (kIsWeb || _db == null) {
      // Load existing messages for this session
      final key      = _prefKey(msg.userKey, msg.session);
      final existing = _webLoadMessages(msg.userKey, msg.session);
      existing.add(msg.toMap());
      await _prefs!.setString(key, jsonEncode(existing));
      await _webAddSessionToIndex(msg.userKey, msg.session);
      return;
    }
    await _db!.insert('chat_messages', msg.toMap());
  }

  Future<void> saveMessages(List<LocalChatMessage> msgs) async {
    for (final m in msgs) {
      await saveMessage(m);
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _webLoadMessages(
      String userKey, String session) {
    final raw = _prefs!.getString(_prefKey(userKey, session));
    if (raw == null || raw.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<List<LocalChatMessage>> getMessages(
      String userKey, String session) async {
    if (kIsWeb || _db == null) {
      final rows = _webLoadMessages(userKey, session);
      final msgs = rows.map(LocalChatMessage.fromMap).toList();
      msgs.sort((a, b) => a.ts.compareTo(b.ts));
      return msgs;
    }
    final rows = await _db!.query(
      'chat_messages',
      where    : 'user_key = ? AND session = ?',
      whereArgs: [userKey, session],
      orderBy  : 'ts ASC',
    );
    return rows.map(LocalChatMessage.fromMap).toList();
  }

  Future<List<ChatSession>> getSessions(String userKey) async {
    if (kIsWeb || _db == null) {
      final sessionKeys = _webSessionKeys(userKey);
      final sessions    = <ChatSession>[];
      for (final s in sessionKeys) {
        final msgs = _webLoadMessages(userKey, s)
            .map(LocalChatMessage.fromMap)
            .toList()
          ..sort((a, b) => a.ts.compareTo(b.ts));
        if (msgs.isEmpty) continue;
        final preview = msgs.firstWhere(
          (m) => m.role == 'user',
          orElse: () => msgs.first,
        ).content;
        sessions.add(ChatSession(
          session     : s,
          preview     : preview.length > 60 ? '${preview.substring(0, 60)}…' : preview,
          messageCount: msgs.length,
          lastTs      : msgs.last.ts,
        ));
      }
      sessions.sort((a, b) => b.lastTs.compareTo(a.lastTs));
      return sessions;
    }

    final db   = await _db!.database;
    final rows = await db.rawQuery(
      '''
      SELECT session,
             COUNT(*)                                      AS cnt,
             MAX(ts)                                       AS last_ts,
             MIN(CASE WHEN role = "user" THEN content END) AS preview
      FROM   chat_messages
      WHERE  user_key = ?
      GROUP  BY session
      ORDER  BY last_ts DESC
      ''',
      [userKey],
    );
    return rows.map((r) {
      final preview = (r['preview'] as String?)?.trim() ?? '';
      return ChatSession(
        session     : r['session'] as String,
        preview     : preview.length > 60 ? '${preview.substring(0, 60)}…' : preview,
        messageCount: (r['cnt'] as int?) ?? 0,
        lastTs      : DateTime.tryParse(r['last_ts'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> deleteSession(String userKey, String session) async {
    if (kIsWeb || _db == null) {
      await _prefs!.remove(_prefKey(userKey, session));
      final keys = _webSessionKeys(userKey)..remove(session);
      await _prefs!.setString(_sessionsIndexKey(userKey), jsonEncode(keys));
      return;
    }
    await _db!.delete('chat_messages',
        where: 'user_key = ? AND session = ?', whereArgs: [userKey, session]);
  }

  Future<void> deleteAllForUser(String userKey) async {
    if (kIsWeb || _db == null) {
      final keys = _webSessionKeys(userKey);
      for (final s in keys) {
        await _prefs!.remove(_prefKey(userKey, s));
      }
      await _prefs!.remove(_sessionsIndexKey(userKey));
      return;
    }
    await _db!.delete('chat_messages',
        where: 'user_key = ?', whereArgs: [userKey]);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String todaySession() =>
      DateFormat('yyyy-MM-dd').format(DateTime.now());
}
