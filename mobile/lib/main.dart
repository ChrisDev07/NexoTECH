import 'package:flutter/material.dart';
import 'models/merchant_profile.dart';
import 'models/movement_log.dart';
import 'models/product_stock.dart';
import 'screens/community_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/login_screen.dart';
import 'services/nlp_service.dart';
import 'services/offline_ledger.dart';
import 'services/offline_voice_service.dart';
import 'services/sync_service.dart';
import 'widgets/confirmation_sheet.dart';
import 'widgets/origo_header.dart';

void main() {
  runApp(const OrigoApp());
}

class OrigoApp extends StatelessWidget {
  const OrigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Origo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFAF9F6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF047857),
          primary: const Color(0xFF047857),
          secondary: const Color(0xFFF59E0B),
          surface: const Color(0xFFFFFFFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const OrigoHomeShell(),
    );
  }
}

class OrigoHomeShell extends StatefulWidget {
  const OrigoHomeShell({super.key});

  @override
  State<OrigoHomeShell> createState() => _OrigoHomeShellState();
}

class _OrigoHomeShellState extends State<OrigoHomeShell> {
  final RegionalNlpService _nlp = RegionalNlpService();
  final OfflineLedgerService _ledger = OfflineLedgerService();
  final OfflineVoiceService _voice = OfflineVoiceService();
  late final AutoSyncService _sync = AutoSyncService(_ledger);

  MerchantProfile? _currentUser;
  int _selectedTab = 0;
  bool _isListening = false;
  bool _isVoiceModelReady = false;
  bool _isHistoryExpanded = true;
  int _extraCollectiveBultos = 0;
  String _liveTranscript = '';

  final List<MovementLog> _recentMovements = [];

  final List<ProductStock> _inventory = [
    ProductStock(
      id: 'prod_arroz_casanare',
      icon: '🌾',
      name: 'Arroz Casanareño',
      category: 'Granos y Víveres',
      unit: 'bultos',
      openingStock: 20,
      quantity: 20,
      minThreshold: 10,
    ),
    ProductStock(
      id: 'prod_aceite_vegetal',
      icon: '🛢️',
      name: 'Aceite Vegetal 900ml',
      category: 'Víveres',
      unit: 'cajas',
      openingStock: 10,
      quantity: 10,
      minThreshold: 5,
    ),
    ProductStock(
      id: 'prod_panela_criolla',
      icon: '🟫',
      name: 'Panela Criolla',
      category: 'Víveres',
      unit: 'pacas',
      openingStock: 15,
      quantity: 15,
      minThreshold: 8,
    ),
    ProductStock(
      id: 'prod_papa_pastusa',
      icon: '🥔',
      name: 'Papa Pastusa / Criolla',
      category: 'Perecederos',
      unit: 'arrobas',
      openingStock: 12,
      quantity: 12,
      minThreshold: 6,
    ),
    ProductStock(
      id: 'prod_abono_triple15',
      icon: '🌱',
      name: 'Abono Triple 15',
      category: 'Agroinsumos',
      unit: 'bultos',
      openingStock: 15,
      quantity: 15,
      minThreshold: 12,
    ),
    ProductStock(
      id: 'prod_cemento_gris',
      icon: '🧱',
      name: 'Cemento Gris 50kg',
      category: 'Ferretería',
      unit: 'bultos',
      openingStock: 30,
      quantity: 30,
      minThreshold: 20,
    ),
    ProductStock(
      id: 'prod_sal_marina',
      icon: '🧂',
      name: 'Sal Marina Refinada',
      category: 'Víveres',
      unit: 'bultos',
      openingStock: 8,
      quantity: 8,
      minThreshold: 5,
    ),
    ProductStock(
      id: 'prod_harina_pan',
      icon: '🌽',
      name: 'Harina de Maíz Precocida',
      category: 'Víveres',
      unit: 'pacas',
      openingStock: 12,
      quantity: 12,
      minThreshold: 7,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _nlp.loadCatalog();
    await _loadLedgerFromSqlite();

    // 1. Escuchar cambios reales de conectividad del celular (Wi-Fi / Datos / Modo Avión)
    _sync.onConnectivityChanged = (bool isOnline) async {
      if (!mounted) return;
      if (!isOnline) {
        _showSnack('✈️ Sin señal: los movimientos se guardarán localmente en tu celular.');
        return;
      }
      // Esperar brevemente a que Android complete el enrutamiento al desactivar Modo Avión
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      await _attemptAutoSync(notifyOnSuccess: true);
    };

    try {
      final onlineNow = await _sync.init();
      if (onlineNow) {
        await _attemptAutoSync(notifyOnSuccess: false);
      }
    } catch (_) {}

    // 2. Inicializar motor de voz 100% offline (Vosk embebido)
    _voice.onModelStatus = (status) {
      if (!mounted) return;
      if (status == 'ready') {
        setState(() => _isVoiceModelReady = true);
      } else if (status.startsWith('error:')) {
        setState(() => _isVoiceModelReady = false);
        _showSnack('⚠️ ${status.substring(6)}');
      }
    };

    _voice.onListeningStarted = () {
      if (!mounted) return;
      setState(() {
        _isListening = true;
        _liveTranscript = '';
      });
    };

    _voice.onPartial = (partial) {
      if (!mounted) return;
      setState(() => _liveTranscript = partial);
    };

    _voice.onFinal = (finalText) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        if (finalText.isNotEmpty) _liveTranscript = finalText;
      });
      if (finalText.trim().isNotEmpty) {
        _handleSpokenPhrase(finalText);
      } else {
        _showSnack('⚠️ No se escuchó voz. Habla cerca del micrófono e intenta de nuevo.');
      }
    };

    _voice.onError = (err) {
      if (!mounted) return;
      setState(() => _isListening = false);
      _showSnack('⚠️ $err');
    };

    try {
      final ready = await _voice.init();
      if (mounted && ready) {
        setState(() => _isVoiceModelReady = true);
      }
    } catch (_) {}
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _attemptAutoSync({required bool notifyOnSuccess}) async {
    final result = await _sync.syncPendingMovements();
    if (result.syncedCount > 0) {
      await _loadLedgerFromSqlite();
      if (notifyOnSuccess) {
        _showSnack(
          '☁️ ¡Internet detectado! ${result.syncedCount} movimiento${result.syncedCount == 1 ? "" : "s"} subido${result.syncedCount == 1 ? "" : "s"} al servidor.',
        );
      }
    }
  }

  Future<void> _loadLedgerFromSqlite() async {
    final rows = await _ledger.getAllMovements();
    final now = DateTime.now();
    final startOfDayMs = DateTime(now.year, now.month, now.day, 0, 0, 0).millisecondsSinceEpoch;
    final endOfDayMs = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    for (final p in _inventory) {
      p.quantity = p.openingStock;
      p.todayIn = 0;
      p.todayOut = 0;
    }

    final logs = <MovementLog>[];
    for (final row in rows) {
      final pid = row['product_id'].toString();
      final isSale = row['type'].toString() == 'OUT';
      final qty = (row['quantity'] as num).toDouble();
      final ts = (row['timestamp'] as num).toInt();
      final prod = _inventory.where((p) => p.id == pid).firstOrNull;
      if (prod != null) {
        if (isSale) {
          prod.quantity = (prod.quantity - qty).clamp(0, 99999);
          if (ts >= startOfDayMs && ts <= endOfDayMs) prod.todayOut += qty;
        } else {
          prod.quantity += qty;
          if (ts >= startOfDayMs && ts <= endOfDayMs) prod.todayIn += qty;
        }
      }
      logs.add(
        MovementLog(
          icon: prod?.icon ?? '📦',
          productName: row['product_name'].toString(),
          isSale: isSale,
          quantity: qty,
          unit: row['unit'].toString(),
          synced: (row['synced'] as num).toInt() == 1,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _recentMovements
          ..clear()
          ..addAll(logs);
      });
    }
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _voice.stopListening();
      return;
    }

    final status = await _voice.startListening();
    if (!mounted) return;

    if (status == 'listening') {
      setState(() {
        _liveTranscript = '';
        _isListening = true;
      });
    } else if (status == 'loading_model') {
      _showSnack('⏳ Terminando de cargar el modelo de voz sin internet... intenta en 2 segundos.');
    }
  }

  void _handleSpokenPhrase(String phrase) {
    final parsed = _nlp.parsePhrase(phrase);
    if (parsed.isEmpty) {
      _showSnack('⚠️ Escuché "$phrase", pero no reconocí un producto del catálogo.');
      return;
    }
    final first = parsed.first;
    final prod = _inventory.where((p) => p.id == first.productId).firstOrNull;
    if (prod != null) {
      _openConfirm(
        prod,
        isSale: first.action == 'SALIDA',
        qty: first.quantity,
      );
    }
  }

  void _openConfirm(ProductStock product, {bool isSale = true, double qty = 1}) {
    showOrigoConfirmationSheet(
      context: context,
      product: product,
      initialIsSale: isSale,
      initialQty: qty,
      onConfirm: (confirmedSale, confirmedQty) async {
        // 1. Siempre guardar primero en SQLite local (synced = 0) -> Cero pérdida de datos
        await _ledger.recordMovement(
          productId: product.id,
          productName: product.name,
          isSale: confirmedSale,
          quantity: confirmedQty,
          unit: product.unit,
          synced: false,
        );
        await _loadLedgerFromSqlite();
        if (mounted) setState(() => _liveTranscript = '');

        // 2. Revisar conectividad REAL del celular y sincronizar automáticamente si hay señal
        final online = await _sync.checkOnlineNow();
        if (!online) {
          _showSnack('💾 Sin señal: guardado localmente. Se subirá al servidor al tener internet.');
          return;
        }

        final syncRes = await _sync.syncPendingMovements();
        await _loadLedgerFromSqlite();
        if (syncRes.reachedServer) {
          _showSnack('✅ ¡Guardado y subido automáticamente al servidor!');
        } else {
          _showSnack('💾 Guardado en local (pendiente de conectar con el servidor).');
        }
      },
    );
  }

  Future<void> _openServerConfigDialog() async {
    final currentUrl = await _ledger.getServerUrl();
    final ctrl = TextEditingController(text: currentUrl);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🌐 Servidor de Sincronización'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dirección del servidor donde se subirán los datos al tener Wi-Fi o datos móviles:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL del servidor',
                hintText: 'http://192.168.1.50:8000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) {
                await _ledger.setServerUrl(url);
                if (ctx.mounted) Navigator.pop(ctx);
                _showSnack('✔ Servidor guardado. Intentando sincronizar...');
                await _attemptAutoSync(notifyOnSuccess: true);
              }
            },
            child: const Text('Guardar y sincronizar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return LoginScreen(
        onAuthenticated: (profile) {
          setState(() => _currentUser = profile);
          _attemptAutoSync(notifyOnSuccess: true);
        },
      );
    }

    final lowCount = _inventory.where((e) => e.isCritical).length;

    return Scaffold(
      body: Column(
        children: [
          OrigoHeader(
            ownerName: _currentUser!.ownerName,
            storeLocation: '${_currentUser!.businessName} · ${_currentUser!.zone}',
            onConfigureServer: _openServerConfigDialog,
            onLogout: () => setState(() => _currentUser = null),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                HomeScreen(
                  isListening: _isListening,
                  isVoiceModelReady: _isVoiceModelReady,
                  liveTranscript: _liveTranscript,
                  lowStockCount: lowCount,
                  isHistoryExpanded: _isHistoryExpanded,
                  recentMovements: _recentMovements,
                  onToggleMic: _toggleMic,
                  onOpenCommunity: () => setState(() => _selectedTab = 2),
                  onToggleHistory: () => setState(() => _isHistoryExpanded = !_isHistoryExpanded),
                ),
                InventoryScreen(
                  inventory: _inventory,
                  onSelectProduct: (p) => _openConfirm(p, isSale: true, qty: 1),
                ),
                CommunityScreen(
                  extraBultos: _extraCollectiveBultos,
                  onJoinOrder: () {
                    setState(() => _extraCollectiveBultos += 10);
                    _showSnack('🎉 ¡Sumaste +10 bultos al pedido comunitario!');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFD1FAE5),
        onDestinationSelected: (idx) => setState(() => _selectedTab = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Bodega'),
          NavigationDestination(icon: Icon(Icons.groups_rounded), label: 'Comunidad'),
        ],
      ),
    );
  }
}
