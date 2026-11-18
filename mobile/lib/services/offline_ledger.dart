import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Libro Mayor Inmutable (Event Sourcing) en SQLite local para Android/iOS.
class OfflineLedgerService {
  static const _dbName = 'origo_local_ledger.db';
  static const _defaultServerUrl = 'http://192.168.1.100:8000';
  static const _uuid = Uuid();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE movements (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            type TEXT NOT NULL,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            synced INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        }
      },
    );
    return _db!;
  }

  Future<String> recordMovement({
    required String productId,
    required String productName,
    required bool isSale,
    required double quantity,
    required String unit,
    required bool synced,
  }) async {
    final db = await database;
    final id = _uuid.v4();
    await db.insert('movements', {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'type': isSale ? 'OUT' : 'IN',
      'quantity': quantity,
      'unit': unit,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': synced ? 1 : 0,
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getAllMovements() async {
    final db = await database;
    return db.query('movements', orderBy: 'timestamp DESC');
  }

  Future<List<Map<String, dynamic>>> getPendingMovements() async {
    final db = await database;
    return db.query(
      'movements',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> markIdsAsSynced(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('movements', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    return ids.length;
  }

  Future<String> getServerUrl() async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['server_url']);
    if (rows.isNotEmpty) {
      final val = rows.first['value']?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return _defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    final db = await database;
    await db.insert(
      'settings',
      {'key': 'server_url', 'value': clean},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
