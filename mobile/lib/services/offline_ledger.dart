import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/merchant_profile.dart';

/// Base de datos SQLite local de Origo:
/// 1. `local_users`: Cuentas de comercios aisladas con clave cifrada (SHA-256 + sal).
/// 2. `movements`: Libro mayor inmutable filtrado por `business_id`.
/// 3. `settings`: URL del servidor y sesión activa persistente.
class OfflineLedgerService {
  static const _dbName = 'origo_local_ledger.db';
  static const _defaultServerUrl = 'http://10.209.55.173:8000';
  static const _uuid = Uuid();
  Database? _db;

  static String sanitizePhone(String phone) =>
      phone.replaceAll(RegExp(r'\D+'), '').trim();

  static String _generateSaltHex() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _hashPin(String pin, String saltHex) {
    var digest = sha256.convert(utf8.encode('$saltHex:$pin')).bytes;
    for (int i = 0; i < 2000; i++) {
      digest = sha256.convert([...digest, ...utf8.encode(saltHex)]).bytes;
    }
    final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'sha256_iter2000:$hex';
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_users (
            id TEXT PRIMARY KEY,
            phone TEXT UNIQUE NOT NULL,
            owner_name TEXT NOT NULL,
            business_name TEXT NOT NULL,
            zone TEXT NOT NULL,
            pin_salt TEXT NOT NULL,
            pin_hash TEXT NOT NULL,
            habeas_data_accepted INTEGER NOT NULL,
            synced INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE movements (
            id TEXT PRIMARY KEY,
            business_id TEXT NOT NULL DEFAULT 'tienda_demo',
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
          CREATE TABLE custom_products (
            id TEXT PRIMARY KEY,
            business_id TEXT NOT NULL,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            unit TEXT NOT NULL,
            min_threshold REAL NOT NULL,
            synonyms TEXT NOT NULL,
            synced INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await _seedDemoUser(db);
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
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS local_users (
              id TEXT PRIMARY KEY,
              phone TEXT UNIQUE NOT NULL,
              owner_name TEXT NOT NULL,
              business_name TEXT NOT NULL,
              zone TEXT NOT NULL,
              pin_salt TEXT NOT NULL,
              pin_hash TEXT NOT NULL,
              habeas_data_accepted INTEGER NOT NULL,
              synced INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
          final cols = await db.rawQuery('PRAGMA table_info(movements)');
          final hasBusinessId = cols.any((c) => c['name'] == 'business_id');
          if (!hasBusinessId) {
            await db.execute(
              "ALTER TABLE movements ADD COLUMN business_id TEXT NOT NULL DEFAULT 'tienda_demo'",
            );
          }
          await _seedDemoUser(db);
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS custom_products (
              id TEXT PRIMARY KEY,
              business_id TEXT NOT NULL,
              name TEXT NOT NULL,
              category TEXT NOT NULL,
              unit TEXT NOT NULL,
              min_threshold REAL NOT NULL,
              synonyms TEXT NOT NULL,
              synced INTEGER NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
    return _db!;
  }

  Future<void> _seedDemoUser(Database db) async {
    final existing = await db.query('local_users', where: 'id = ?', whereArgs: ['tienda_demo']);
    if (existing.isNotEmpty) return;
    final salt = _generateSaltHex();
    final hash = _hashPin('1234', salt);
    await db.insert('local_users', {
      'id': 'tienda_demo',
      'phone': '3101234567',
      'owner_name': 'Don Pedro',
      'business_name': 'Tienda La Esperanza',
      'zone': 'Comuna 2, Yopal',
      'pin_salt': salt,
      'pin_hash': hash,
      'habeas_data_accepted': 1,
      'synced': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  MerchantProfile _rowToProfile(Map<String, dynamic> row) {
    return MerchantProfile(
      id: row['id'].toString(),
      ownerName: row['owner_name'].toString(),
      businessName: row['business_name'].toString(),
      zone: row['zone'].toString(),
      phone: row['phone'].toString(),
    );
  }

  // --- GESTIÓN DE USUARIOS LOCALES (OFFLINE-FIRST) ---

  Future<({MerchantProfile? profile, String? error})> registerLocalUser({
    required String ownerName,
    required String businessName,
    required String zone,
    required String phone,
    required String pin,
    required bool habeasAccepted,
  }) async {
    final cleanPhone = sanitizePhone(phone);
    final cleanPin = pin.trim();
    final cleanOwner = ownerName.trim();
    final cleanBusiness = businessName.trim();

    if (!habeasAccepted) {
      return (profile: null, error: 'Debes aceptar el Aviso de Privacidad (Ley 1581 de 2012).');
    }
    if (cleanOwner.length < 2 || cleanBusiness.length < 2) {
      return (profile: null, error: 'Completa tu nombre y el nombre de tu negocio.');
    }
    if (cleanPhone.length < 7 || cleanPhone.length > 15) {
      return (profile: null, error: 'Ingresa un número de celular válido.');
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(cleanPin)) {
      return (profile: null, error: 'Crea una clave de 4 a 6 números (ej. 1234).');
    }

    final db = await database;
    final dup = await db.query('local_users', where: 'phone = ?', whereArgs: [cleanPhone]);
    if (dup.isNotEmpty) {
      return (profile: null, error: 'Este celular ya está registrado en el dispositivo. Usa "Entrar".');
    }

    final id = 'tienda_${_uuid.v4().replaceAll('-', '').substring(0, 8)}';
    final salt = _generateSaltHex();
    final hash = _hashPin(cleanPin, salt);

    final row = {
      'id': id,
      'phone': cleanPhone,
      'owner_name': cleanOwner,
      'business_name': cleanBusiness,
      'zone': zone.trim(),
      'pin_salt': salt,
      'pin_hash': hash,
      'habeas_data_accepted': 1,
      'synced': 0, // Pendiente de registrar en el servidor al recuperar señal
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insert('local_users', row);
    await setActiveUserId(id);
    return (profile: _rowToProfile(row), error: null);
  }

  Future<({MerchantProfile? profile, String? error})> loginLocalUser({
    required String phone,
    required String pin,
  }) async {
    final cleanPhone = sanitizePhone(phone);
    final cleanPin = pin.trim();
    if (cleanPhone.isEmpty || cleanPin.isEmpty) {
      return (profile: null, error: 'Ingresa tu celular y tu clave numérica.');
    }

    final db = await database;
    final rows = await db.query('local_users', where: 'phone = ?', whereArgs: [cleanPhone]);
    if (rows.isEmpty) {
      return (profile: null, error: 'No existe una tienda con ese celular. Créala en "Crear tienda".');
    }

    final row = rows.first;
    final expectedHash = row['pin_hash'].toString();
    final salt = row['pin_salt'].toString();
    if (_hashPin(cleanPin, salt) != expectedHash) {
      return (profile: null, error: 'Clave incorrecta. Intenta nuevamente.');
    }

    final profile = _rowToProfile(row);
    await setActiveUserId(profile.id);
    return (profile: profile, error: null);
  }

  Future<MerchantProfile> loginDemoUser() async {
    final db = await database;
    await _seedDemoUser(db);
    final rows = await db.query('local_users', where: 'id = ?', whereArgs: ['tienda_demo']);
    final profile = _rowToProfile(rows.first);
    await setActiveUserId(profile.id);
    return profile;
  }

  Future<MerchantProfile?> getActiveUser() async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['active_user_id']);
    if (rows.isEmpty) return null;
    final activeId = rows.first['value']?.toString() ?? '';
    if (activeId.isEmpty) return null;
    final users = await db.query('local_users', where: 'id = ?', whereArgs: [activeId]);
    if (users.isEmpty) return null;
    return _rowToProfile(users.first);
  }

  Future<void> setActiveUserId(String? userId) async {
    final db = await database;
    if (userId == null || userId.isEmpty) {
      await db.delete('settings', where: 'key = ?', whereArgs: ['active_user_id']);
    } else {
      await db.insert(
        'settings',
        {'key': 'active_user_id', 'value': userId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getPendingUsers() async {
    final db = await database;
    return db.query('local_users', where: 'synced = ?', whereArgs: [0]);
  }

  Future<void> markUsersSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('local_users', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Guarda/actualiza en SQLite local un usuario autenticado contra el servidor Rust.
  Future<MerchantProfile> upsertSyncedRemoteUser({
    required String id,
    required String phone,
    required String pin,
    required String ownerName,
    required String businessName,
    required String zone,
  }) async {
    final db = await database;
    final cleanPhone = sanitizePhone(phone);
    final salt = _generateSaltHex();
    final hash = _hashPin(pin.trim(), salt);

    final row = {
      'id': id,
      'phone': cleanPhone,
      'owner_name': ownerName,
      'business_name': businessName,
      'zone': zone,
      'pin_salt': salt,
      'pin_hash': hash,
      'habeas_data_accepted': 1,
      'synced': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insert('local_users', row, conflictAlgorithm: ConflictAlgorithm.replace);
    await setActiveUserId(id);
    return _rowToProfile(row);
  }

  // --- PRODUCTOS PERSONALIZADOS POR TIENDA ---

  Future<Map<String, dynamic>> addCustomProduct({
    required String businessId,
    required String name,
    required String category,
    required String unit,
    required double minThreshold,
    required List<String> synonyms,
    String? id,
    bool synced = false,
  }) async {
    final db = await database;
    final prodId = id ?? 'prod_custom_${_uuid.v4().replaceAll('-', '').substring(0, 8)}';
    final synList = synonyms.where((s) => s.trim().isNotEmpty).toList();
    if (synList.isEmpty) synList.add(name.trim().toLowerCase());

    final row = {
      'id': prodId,
      'business_id': businessId,
      'name': name.trim(),
      'category': category.trim().isEmpty ? 'Mi Tienda' : category.trim(),
      'unit': unit.trim().isEmpty ? 'unidades' : unit.trim().toLowerCase(),
      'min_threshold': minThreshold > 0 ? minThreshold : 5.0,
      'synonyms': synList.join(','),
      'synced': synced ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    await db.insert('custom_products', row, conflictAlgorithm: ConflictAlgorithm.replace);
    return row;
  }

  Future<List<Map<String, dynamic>>> getCustomProducts(String businessId) async {
    final db = await database;
    return db.query(
      'custom_products',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingCustomProducts() async {
    final db = await database;
    return db.query('custom_products', where: 'synced = ?', whereArgs: [0]);
  }

  Future<void> markProductsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('custom_products', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> importRemoteCustomProducts(
    String businessId,
    List<Map<String, dynamic>> remoteProducts,
  ) async {
    if (remoteProducts.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final p in remoteProducts) {
      final synRaw = p['synonyms'];
      final synStr = synRaw is List
          ? synRaw.map((e) => e.toString()).join(',')
          : (synRaw?.toString() ?? p['name'].toString().toLowerCase());
      batch.insert(
        'custom_products',
        {
          'id': p['id'].toString(),
          'business_id': businessId,
          'name': p['name'].toString(),
          'category': (p['category'] ?? 'Mi Tienda').toString(),
          'unit': (p['default_unit'] ?? p['unit'] ?? 'unidades').toString(),
          'min_threshold': (p['min_threshold'] as num?)?.toDouble() ?? 5.0,
          'synonyms': synStr,
          'synced': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> importRemoteMovements(
    String businessId,
    List<Map<String, dynamic>> remoteMoves,
  ) async {
    if (remoteMoves.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final m in remoteMoves) {
      final rawTs = (m['timestamp'] as num?)?.toDouble() ??
          (DateTime.now().millisecondsSinceEpoch / 1000.0);
      final tsMs = rawTs < 1e11 ? (rawTs * 1000).round() : rawTs.round();
      batch.insert(
        'movements',
        {
          'id': m['id'].toString(),
          'business_id': (m['business_id'] ?? businessId).toString(),
          'product_id': m['product_id'].toString(),
          'product_name': (m['product_name'] ?? '').toString(),
          'type': m['type'].toString(),
          'quantity': (m['quantity'] as num).toDouble(),
          'unit': (m['unit'] ?? 'unidades').toString(),
          'timestamp': tsMs,
          'synced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  // --- MOVIMIENTOS AISLADOS POR TIENDA (`business_id`) ---

  Future<String> recordMovement({
    required String businessId,
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
      'business_id': businessId,
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

  Future<List<Map<String, dynamic>>> getAllMovements(String businessId) async {
    final db = await database;
    return db.query(
      'movements',
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'timestamp DESC',
    );
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
