import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Libro Mayor Inmutable (Event Sourcing) en SQLite local para Android/iOS.
class OfflineLedgerService {
  static const _dbName = 'origo_local_ledger.db';
  static const _uuid = Uuid();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
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
      },
    );
    return _db!;
  }

  Future<void> recordMovement({
    required String productId,
    required String productName,
    required bool isSale,
    required double quantity,
    required String unit,
    required bool synced,
  }) async {
    final db = await database;
    await db.insert('movements', {
      'id': _uuid.v4(),
      'product_id': productId,
      'product_name': productName,
      'type': isSale ? 'OUT' : 'IN',
      'quantity': quantity,
      'unit': unit,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': synced ? 1 : 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAllMovements() async {
    final db = await database;
    return db.query('movements', orderBy: 'timestamp DESC');
  }

  Future<int> markAllSynced() async {
    final db = await database;
    return db.update('movements', {'synced': 1}, where: 'synced = ?', whereArgs: [0]);
  }
}
