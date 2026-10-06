import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local FCM token staging cache.
///
/// The employee APK must not keep pushing token writes while the user is working.
/// Token refresh events are staged locally and flushed on a later app launch.
class FcmRuntimeTokenCache {
  const FcmRuntimeTokenCache();

  static const String _dbName = 'employee_fcm_runtime_cache.db';
  static const String _table = 'fcm_runtime_tokens';
  static Database? _database;

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        uid TEXT PRIMARY KEY,
        active_token TEXT,
        active_permission TEXT,
        pending_token TEXT,
        pending_permission TEXT,
        last_server_sync_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final dbPath = p.join(root, _dbName);
    final opened = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createTables(db);
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE $_table ADD COLUMN last_server_sync_at TEXT');
          } catch (_) {}
        }
      },
    );
    _database = opened;
    return opened;
  }

  Future<Map<String, Object?>?> _row(String uid) async {
    try {
      final db = await _db;
      final rows = await db.query(_table, where: 'uid = ?', whereArgs: <Object?>[uid], limit: 1);
      return rows.isEmpty ? null : rows.first;
    } catch (_) {
      return null;
    }
  }

  Future<String?> readActiveToken(String uid) async {
    final row = await _row(uid);
    final value = row?['active_token']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> markActiveToken({
    required String uid,
    required String token,
    required String permissionStatus,
  }) async {
    if (uid.trim().isEmpty || token.trim().isEmpty) return;
    try {
      final db = await _db;
      final row = await _row(uid);
      await db.insert(
        _table,
        <String, Object?>{
          'uid': uid,
          'active_token': token,
          'active_permission': permissionStatus,
          'pending_token': null,
          'pending_permission': null,
          'last_server_sync_at': row?['last_server_sync_at'],
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<Map<String, String>?> readPendingToken(String uid) async {
    final row = await _row(uid);
    final token = row?['pending_token']?.toString().trim();
    if (token == null || token.isEmpty) return null;
    final permission = row?['pending_permission']?.toString().trim();
    return <String, String>{
      'token': token,
      'permissionStatus': permission == null || permission.isEmpty ? 'unknown' : permission,
    };
  }

  Future<void> stagePendingToken({
    required String uid,
    required String token,
    required String permissionStatus,
  }) async {
    if (uid.trim().isEmpty || token.trim().isEmpty) return;
    try {
      final db = await _db;
      final row = await _row(uid);
      await db.insert(
        _table,
        <String, Object?>{
          'uid': uid,
          'active_token': row?['active_token'],
          'active_permission': row?['active_permission'],
          'pending_token': token,
          'pending_permission': permissionStatus,
          'last_server_sync_at': row?['last_server_sync_at'],
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<bool> canSyncWithServer(String uid, Duration minInterval) async {
    final row = await _row(uid);
    final raw = row?['last_server_sync_at']?.toString().trim();
    if (raw == null || raw.isEmpty) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().difference(last) >= minInterval;
  }

  Future<void> markServerSynced(String uid) async {
    try {
      final db = await _db;
      final row = await _row(uid);
      if (row == null) {
        await db.insert(
          _table,
          <String, Object?>{
            'uid': uid,
            'active_token': null,
            'active_permission': null,
            'pending_token': null,
            'pending_permission': null,
            'last_server_sync_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      }
      await db.update(
        _table,
        <String, Object?>{
          'last_server_sync_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'uid = ?',
        whereArgs: <Object?>[uid],
      );
    } catch (_) {}
  }

  Future<void> clearPendingToken(String uid) async {
    try {
      final db = await _db;
      final row = await _row(uid);
      if (row == null) return;
      await db.update(
        _table,
        <String, Object?>{
          'pending_token': null,
          'pending_permission': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'uid = ?',
        whereArgs: <Object?>[uid],
      );
    } catch (_) {}
  }
}
