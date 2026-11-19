import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/merchant_profile.dart';
import 'offline_ledger.dart';

class SyncResult {
  final bool reachedServer;
  final int syncedUsersCount;
  final int syncedProductsCount;
  final int syncedCount;
  final int pendingRemaining;

  const SyncResult({
    required this.reachedServer,
    this.syncedUsersCount = 0,
    this.syncedProductsCount = 0,
    required this.syncedCount,
    required this.pendingRemaining,
  });
}

class RemoteLoginResult {
  final MerchantProfile? profile;
  final String? error;
  final bool serverUnreachable;

  const RemoteLoginResult({
    this.profile,
    this.error,
    this.serverUnreachable = false,
  });
}

/// Monitorea la conectividad real del celular (Wi-Fi / Datos / Modo Avión),
/// sincroniza usuarios, productos personalizados y movimientos con el backend Rust,
/// y conecta Login y Comunidad en vivo cuando hay señal.
class AutoSyncService {
  static const MethodChannel _networkChannel = MethodChannel('co.nexotech.origo/network');
  final OfflineLedgerService _ledger;

  void Function(bool isOnline)? onConnectivityChanged;
  bool _initialized = false;
  bool _isSyncing = false;
  bool _lastKnownOnline = true;

  AutoSyncService(this._ledger);

  bool get lastKnownOnline => _lastKnownOnline;

  Future<bool> init() async {
    if (!_initialized) {
      _networkChannel.setMethodCallHandler(_handleNativeCall);
      _initialized = true;
    }
    try {
      final online = await _networkChannel.invokeMethod<bool>('isOnline');
      _lastKnownOnline = online ?? false;
    } catch (_) {
      _lastKnownOnline = false;
    }
    return _lastKnownOnline;
  }

  Future<bool> checkOnlineNow() async {
    try {
      final online = await _networkChannel.invokeMethod<bool>('isOnline');
      _lastKnownOnline = online ?? false;
    } catch (_) {
      _lastKnownOnline = false;
    }
    return _lastKnownOnline;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onConnectivityChanged') {
      final online = call.arguments == true;
      if (online != _lastKnownOnline) {
        _lastKnownOnline = online;
        onConnectivityChanged?.call(online);
      }
    }
  }

  /// Inicia sesión contra el backend Rust si hay internet, guarda la cuenta en SQLite
  /// y descarga (pull) sus productos personalizados y movimientos existentes.
  Future<RemoteLoginResult> loginOnlineAndPull({
    required String phone,
    required String pin,
  }) async {
    final online = await checkOnlineNow();
    if (!online) {
      return const RemoteLoginResult(serverUnreachable: true);
    }

    try {
      final baseUrl = await _ledger.getServerUrl();
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': OfflineLedgerService.sanitizePhone(phone),
              'pin': pin.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final token = data['token']?.toString() ?? '';
        final u = data['user'] as Map<String, dynamic>;

        final profile = await _ledger.upsertSyncedRemoteUser(
          id: u['id'].toString(),
          phone: u['phone'].toString(),
          pin: pin,
          ownerName: u['owner_name'].toString(),
          businessName: u['business_name'].toString(),
          documentId: u['document_id']?.toString() ?? '',
          address: u['address']?.toString() ?? '',
          zone: u['zone'].toString(),
        );

        // Descargar productos propios y movimientos desde el servidor Rust
        if (token.isNotEmpty) {
          await _pullStoreDataFromServer(baseUrl, token, profile.id);
        }

        return RemoteLoginResult(profile: profile);
      } else if (resp.statusCode == 401 || resp.statusCode == 400) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return RemoteLoginResult(
          error: data['error']?.toString() ?? 'Celular o clave incorrectos.',
        );
      }
      return const RemoteLoginResult(serverUnreachable: true);
    } catch (_) {
      return const RemoteLoginResult(serverUnreachable: true);
    }
  }

  Future<void> _pullStoreDataFromServer(
    String baseUrl,
    String token,
    String businessId,
  ) async {
    final headers = {'Authorization': 'Bearer $token'};
    try {
      final prodResp = await http
          .get(Uri.parse('$baseUrl/api/products'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (prodResp.statusCode == 200) {
        final data = jsonDecode(prodResp.body) as Map<String, dynamic>;
        final list = (data['custom_products'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        await _ledger.importRemoteCustomProducts(businessId, list);
      }
    } catch (_) {}

    try {
      final movResp = await http
          .get(Uri.parse('$baseUrl/api/movements'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (movResp.statusCode == 200) {
        final list = (jsonDecode(movResp.body) as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        await _ledger.importRemoteMovements(businessId, list);
      }
    } catch (_) {}
  }

  /// Sincroniza en orden: 1) cuentas offline, 2) productos propios, 3) movimientos pendientes.
  /// [force]: Si es true, omite la comprobación preliminar del canal nativo e intenta conectar directamente por HTTP.
  Future<SyncResult> syncPendingMovements({bool force = false}) async {
    if (_isSyncing) {
      final pending = await _ledger.getPendingMovements();
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pending.length);
    }

    final pendingUsers = await _ledger.getPendingUsers();
    final pendingProducts = await _ledger.getPendingCustomProducts();
    final pendingMoves = await _ledger.getPendingMovements();
    if (pendingUsers.isEmpty && pendingProducts.isEmpty && pendingMoves.isEmpty) {
      return const SyncResult(
        reachedServer: true,
        syncedUsersCount: 0,
        syncedProductsCount: 0,
        syncedCount: 0,
        pendingRemaining: 0,
      );
    }

    if (!force) {
      final online = await checkOnlineNow();
      if (!online) {
        return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pendingMoves.length);
      }
    }

    _isSyncing = true;
    int syncedUsers = 0;
    int syncedProducts = 0;
    int syncedMoves = 0;
    bool reached = false;

    try {
      final baseUrl = await _ledger.getServerUrl();

      // 1. Subir tiendas creadas sin internet primero
      if (pendingUsers.isNotEmpty) {
        final usersResp = await http
            .post(
              Uri.parse('$baseUrl/api/sync/users'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'users': pendingUsers}),
            )
            .timeout(const Duration(seconds: 18));

        if (usersResp.statusCode == 200) {
          reached = true;
          _lastKnownOnline = true;
          final data = jsonDecode(usersResp.body) as Map<String, dynamic>;
          final ids = (data['synced_ids'] as List? ?? []).map((e) => e.toString()).toList();
          await _ledger.markUsersSynced(ids);
          syncedUsers = ids.length;
        }
      }

      // 2. Subir productos personalizados creados en Mi Bodega
      if (pendingProducts.isNotEmpty) {
        final prodResp = await http
            .post(
              Uri.parse('$baseUrl/api/sync/products'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'products': pendingProducts}),
            )
            .timeout(const Duration(seconds: 18));

        if (prodResp.statusCode == 200) {
          reached = true;
          _lastKnownOnline = true;
          final data = jsonDecode(prodResp.body) as Map<String, dynamic>;
          final ids = (data['synced_ids'] as List? ?? []).map((e) => e.toString()).toList();
          await _ledger.markProductsSynced(ids);
          syncedProducts = ids.length;
        }
      }

      // 3. Subir movimientos pendientes etiquetados con su business_id real
      if (pendingMoves.isNotEmpty) {
        final payload = {
          'movements': pendingMoves
              .map((m) => {
                    'id': m['id'],
                    'business_id': m['business_id'] ?? 'tienda_demo',
                    'product_id': m['product_id'],
                    'product_name': m['product_name'],
                    'type': m['type'],
                    'quantity': m['quantity'],
                    'unit': m['unit'],
                    'timestamp': m['timestamp'],
                    'device_id': 'origo_android',
                  })
              .toList(),
        };

        final response = await http
            .post(
              Uri.parse('$baseUrl/api/sync/movements'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 18));

        if (response.statusCode == 200) {
          reached = true;
          _lastKnownOnline = true;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final syncedIds = (data['synced_ids'] as List? ?? []).map((e) => e.toString()).toList();
          await _ledger.markIdsAsSynced(syncedIds);
          syncedMoves = syncedIds.length;
        }
      }

      final stillPending = await _ledger.getPendingMovements();
      return SyncResult(
        reachedServer: reached,
        syncedUsersCount: syncedUsers,
        syncedProductsCount: syncedProducts,
        syncedCount: syncedMoves,
        pendingRemaining: stillPending.length,
      );
    } catch (_) {
      return SyncResult(
        reachedServer: false,
        syncedUsersCount: syncedUsers,
        syncedProductsCount: syncedProducts,
        syncedCount: syncedMoves,
        pendingRemaining: pendingMoves.length,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Consulta en vivo el resumen real de Compras Colectivas desde el servidor Rust.
  Future<Map<String, dynamic>?> fetchCollectiveSummary() async {
    final online = await checkOnlineNow();
    if (!online) return null;
    try {
      final baseUrl = await _ledger.getServerUrl();
      final resp = await http
          .get(Uri.parse('$baseUrl/api/collective'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Suma o propone un pedido real de la tienda actual en el tablón comunitario del servidor Rust.
  Future<Map<String, dynamic>?> joinCollectiveOrder({
    required MerchantProfile user,
    String productId = 'prod_arroz_casanare',
    String productName = 'Arroz Casanareño',
    String unit = 'bultos',
    double quantity = 10.0,
  }) async {
    final online = await checkOnlineNow();
    if (!online) return null;
    try {
      final baseUrl = await _ledger.getServerUrl();
      final resp = await http
          .post(
            Uri.parse('$baseUrl/api/collective/join'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'business_id': user.id,
              'business_name': user.businessName,
              'zone': user.zone,
              'product_id': productId,
              'product_name': productName,
              'quantity': quantity,
              'unit': unit,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
