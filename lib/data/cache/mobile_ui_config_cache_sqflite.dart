import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/mobile_ui_config.dart';
import '../models/mobile_ui_design.dart';

/// SQLite cache for server-driven mobile UI config.
///
/// The employee app reads this first, so the UI opens immediately from local
/// storage. Firestore is still listened to in the background; when the config
/// version or payload changes, this cache is replaced and only then does the UI
/// rebuild.
class MobileUiConfigCache {
  const MobileUiConfigCache();

  static const String _dbName = 'employee_mobile_ui_cache.db';
  static const String _configTable = 'mobile_ui_configs';
  static const String _designTable = 'mobile_ui_designs';
  static const String _pendingConfigTable = 'mobile_ui_config_pending';
  static const String _pendingDesignTable = 'mobile_ui_design_pending';
  static Database? _database;

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_configTable (
        company_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_designTable (
        company_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_pendingConfigTable (
        company_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_pendingDesignTable (
        company_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
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
      version: 3,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createTables(db);
      },
    );
    _database = opened;
    return opened;
  }

  Future<MobileUiConfig?> read(String companyId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        _configTable,
        where: 'company_id = ?',
        whereArgs: <Object?>[companyId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final payload = rows.first['payload'] as String?;
      if (payload == null || payload.trim().isEmpty) return null;
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      return MobileUiConfig.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String companyId,
    required MobileUiConfig config,
  }) async {
    try {
      final db = await _db;
      final map = config.toMap(updatedBy: config.updatedBy);
      await db.insert(
        _configTable,
        <String, Object?>{
          'company_id': companyId,
          'payload': jsonEncode(map),
          'version': config.version,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Cache failure should never break the actual app UI.
    }
  }


  Future<MobileUiDesign?> readDesign(String companyId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        _designTable,
        where: 'company_id = ?',
        whereArgs: <Object?>[companyId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final payload = rows.first['payload'] as String?;
      if (payload == null || payload.trim().isEmpty) return null;
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      return MobileUiDesign.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDesign({
    required String companyId,
    required MobileUiDesign design,
  }) async {
    try {
      final db = await _db;
      final map = design.toMap(updatedBy: design.updatedBy);
      await db.insert(
        _designTable,
        <String, Object?>{
          'company_id': companyId,
          'payload': jsonEncode(map),
          'version': design.version,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // Cache failure should never break the actual app UI.
    }
  }


  Future<bool> promotePendingForNextLaunch(String companyId) async {
    try {
      final db = await _db;
      var promoted = false;
      await db.transaction((tx) async {
        final pendingConfigs = await tx.query(
          _pendingConfigTable,
          where: 'company_id = ?',
          whereArgs: <Object?>[companyId],
          limit: 1,
        );
        if (pendingConfigs.isNotEmpty) {
          final row = pendingConfigs.first;
          await tx.insert(
            _configTable,
            <String, Object?>{
              'company_id': companyId,
              'payload': row['payload'],
              'version': row['version'] ?? 1,
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await tx.delete(_pendingConfigTable, where: 'company_id = ?', whereArgs: <Object?>[companyId]);
          promoted = true;
        }

        final pendingDesigns = await tx.query(
          _pendingDesignTable,
          where: 'company_id = ?',
          whereArgs: <Object?>[companyId],
          limit: 1,
        );
        if (pendingDesigns.isNotEmpty) {
          final row = pendingDesigns.first;
          await tx.insert(
            _designTable,
            <String, Object?>{
              'company_id': companyId,
              'payload': row['payload'],
              'version': row['version'] ?? 1,
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await tx.delete(_pendingDesignTable, where: 'company_id = ?', whereArgs: <Object?>[companyId]);
          promoted = true;
        }
      });
      return promoted;
    } catch (_) {
      return false;
    }
  }

  Future<void> writePending({
    required String companyId,
    required MobileUiConfig config,
  }) async {
    try {
      final db = await _db;
      final map = config.toMap(updatedBy: config.updatedBy);
      await db.insert(
        _pendingConfigTable,
        <String, Object?>{
          'company_id': companyId,
          'payload': jsonEncode(map),
          'version': config.version,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> writePendingDesign({
    required String companyId,
    required MobileUiDesign design,
  }) async {
    try {
      final db = await _db;
      final map = design.toMap(updatedBy: design.updatedBy);
      await db.insert(
        _pendingDesignTable,
        <String, Object?>{
          'company_id': companyId,
          'payload': jsonEncode(map),
          'version': design.version,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<bool> hasPending(String companyId) async {
    try {
      final db = await _db;
      final configs = await db.query(_pendingConfigTable, where: 'company_id = ?', whereArgs: <Object?>[companyId], limit: 1);
      final designs = await db.query(_pendingDesignTable, where: 'company_id = ?', whereArgs: <Object?>[companyId], limit: 1);
      return configs.isNotEmpty || designs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear(String companyId) async {
    try {
      final db = await _db;
      await db.delete(_configTable, where: 'company_id = ?', whereArgs: <Object?>[companyId]);
      await db.delete(_designTable, where: 'company_id = ?', whereArgs: <Object?>[companyId]);
      await db.delete(_pendingConfigTable, where: 'company_id = ?', whereArgs: <Object?>[companyId]);
      await db.delete(_pendingDesignTable, where: 'company_id = ?', whereArgs: <Object?>[companyId]);
    } catch (_) {}
  }
}
