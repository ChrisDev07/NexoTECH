import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'offline_ledger.dart';

class SyncResult {
  final bool reachedServer;
  final int syncedCount;
  final int pendingRemaining;

  const SyncResult({
    required this.reachedServer,
    required this.syncedCount,
    required this.pendingRemaining,
  });
}

/// Monitorea la conectividad real del celular (Wi-Fi / Datos / Modo Avión)
/// y sincroniza automáticamente los movimientos locales con el servidor.
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

  /// Sube al servidor todos los movimientos locales con synced = 0.
  Future<SyncResult> syncPendingMovements({String businessId = 'tienda_demo'}) async {
    if (_isSyncing) {
      final pending = await _ledger.getPendingMovements();
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pending.length);
    }

    final pending = await _ledger.getPendingMovements();
    if (pending.isEmpty) {
      return const SyncResult(reachedServer: true, syncedCount: 0, pendingRemaining: 0);
    }

    final online = await checkOnlineNow();
    if (!online) {
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pending.length);
    }

    _isSyncing = true;
    try {
      final baseUrl = await _ledger.getServerUrl();
      final uri = Uri.parse('$baseUrl/api/sync/movements');
      final payload = {
        'movements': pending
            .map((m) => {
                  'id': m['id'],
                  'business_id': businessId,
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
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final syncedIds = (data['synced_ids'] as List? ?? []).map((e) => e.toString()).toList();
        await _ledger.markIdsAsSynced(syncedIds);
        final stillPending = await _ledger.getPendingMovements();
        return SyncResult(
          reachedServer: true,
          syncedCount: syncedIds.length,
          pendingRemaining: stillPending.length,
        );
      }
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pending.length);
    } catch (_) {
      return SyncResult(reachedServer: false, syncedCount: 0, pendingRemaining: pending.length);
    } finally {
      _isSyncing = false;
    }
  }
}
