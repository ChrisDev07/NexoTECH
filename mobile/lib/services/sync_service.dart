import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'offline_ledger.dart';

class SyncResult {
  final bool reachedServer;
  final int syncedUsersCount;
  final int syncedCount;
  final int pendingRemaining;

  const SyncResult({
    required this.reachedServer,
    this.syncedUsersCount = 0,
    required this.syncedCount,
    required this.pendingRemaining,
  });
}

/// Monitorea la conectividad real del celular (Wi-Fi / Datos / Modo Avión)
/// y sincroniza automáticamente cuentas creadas offline y movimientos locales con el servidor.
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

  /// Sincroniza primero tiendas nuevas creadas offline y luego movimientos pendientes.
  Future<SyncResult> syncPendingMovements() async {
    if (_isSyncing) {
      final pending = await _ledger.getPendingMovements();
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pending.length);
    }

    final pendingUsers = await _ledger.getPendingUsers();
    final pendingMoves = await _ledger.getPendingMovements();
    if (pendingUsers.isEmpty && pendingMoves.isEmpty) {
      return const SyncResult(reachedServer: true, syncedUsersCount: 0, syncedCount: 0, pendingRemaining: 0);
    }

    final online = await checkOnlineNow();
    if (!online) {
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pendingMoves.length);
    }

    _isSyncing = true;
    int syncedUsers = 0;
    int syncedMoves = 0;
    bool reached = false;

    try {
      final baseUrl = await _ledger.getServerUrl();

      // 1. Subir tiendas creadas sin internet primero (para mantener integridad referencial)
      if (pendingUsers.isNotEmpty) {
        final usersUri = Uri.parse('$baseUrl/api/sync/users');
        final usersResp = await http
            .post(
              usersUri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'users': pendingUsers}),
            )
            .timeout(const Duration(seconds: 6));

        if (usersResp.statusCode == 200) {
          reached = true;
          final data = jsonDecode(usersResp.body) as Map<String, dynamic>;
          final ids = (data['synced_ids'] as List? ?? []).map((e) => e.toString()).toList();
          await _ledger.markUsersSynced(ids);
          syncedUsers = ids.length;
        }
      }

      // 2. Subir movimientos pendientes etiquetados con su business_id real
      if (pendingMoves.isNotEmpty) {
        final movesUri = Uri.parse('$baseUrl/api/sync/movements');
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
              movesUri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          reached = true;
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
        syncedCount: syncedMoves,
        pendingRemaining: stillPending.length,
      );
    } catch (_) {
      return SyncResult(
        reachedServer: false,
        syncedUsersCount: syncedUsers,
        syncedCount: syncedMoves,
        pendingRemaining: pendingMoves.length,
      );
    } finally {
      _isSyncing = false;
    }
  }
}
