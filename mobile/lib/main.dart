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
  Map<String, dynamic>? _collectiveData;
  bool _loadingCollective = false;
  String _liveTranscript = '';
  String? _focusCollectiveProductId;

  final List<MovementLog> _recentMovements = [];
  List<ProductStock> _inventory = [];

  List<ProductStock> _buildBaseCatalog({required bool isDemoStore}) {
    return [
      ProductStock(
        id: 'prod_arroz_casanare',
        icon: '🌾',
        name: 'Arroz Casanareño',
        category: 'Granos y Víveres',
        unit: 'bultos',
        openingStock: isDemoStore ? 20 : 0,
        quantity: isDemoStore ? 20 : 0,
        minThreshold: 10,
      ),
      ProductStock(
        id: 'prod_aceite_vegetal',
        icon: '🛢️',
        name: 'Aceite Vegetal 900ml',
        category: 'Víveres',
        unit: 'cajas',
        openingStock: isDemoStore ? 10 : 0,
        quantity: isDemoStore ? 10 : 0,
        minThreshold: 5,
      ),
      ProductStock(
        id: 'prod_panela_criolla',
        icon: '🟫',
        name: 'Panela Criolla',
        category: 'Víveres',
        unit: 'pacas',
        openingStock: isDemoStore ? 15 : 0,
        quantity: isDemoStore ? 15 : 0,
        minThreshold: 8,
      ),
      ProductStock(
        id: 'prod_papa_pastusa',
        icon: '🥔',
        name: 'Papa Pastusa / Criolla',
        category: 'Perecederos',
        unit: 'arrobas',
        openingStock: isDemoStore ? 12 : 0,
        quantity: isDemoStore ? 12 : 0,
        minThreshold: 6,
      ),
      ProductStock(
        id: 'prod_abono_triple15',
        icon: '🌱',
        name: 'Abono Triple 15',
        category: 'Agroinsumos',
        unit: 'bultos',
        openingStock: isDemoStore ? 15 : 0,
        quantity: isDemoStore ? 15 : 0,
        minThreshold: 12,
      ),
      ProductStock(
        id: 'prod_cemento_gris',
        icon: '🧱',
        name: 'Cemento Gris 50kg',
        category: 'Ferretería',
        unit: 'bultos',
        openingStock: isDemoStore ? 30 : 0,
        quantity: isDemoStore ? 30 : 0,
        minThreshold: 20,
      ),
      ProductStock(
        id: 'prod_sal_marina',
        icon: '🧂',
        name: 'Sal Marina Refinada',
        category: 'Víveres',
        unit: 'bultos',
        openingStock: isDemoStore ? 8 : 0,
        quantity: isDemoStore ? 8 : 0,
        minThreshold: 5,
      ),
      ProductStock(
        id: 'prod_harina_pan',
        icon: '🌽',
        name: 'Harina de Maíz Precocida',
        category: 'Víveres',
        unit: 'pacas',
        openingStock: isDemoStore ? 12 : 0,
        quantity: isDemoStore ? 12 : 0,
        minThreshold: 7,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _inventory = _buildBaseCatalog(isDemoStore: false);
    _initServices();
  }

  Future<void> _initServices() async {
    await _nlp.loadCatalog();

    // Restaurar sesión activa guardada en SQLite local (funciona sin internet)
    try {
      final savedUser = await _ledger.getActiveUser();
      if (savedUser != null && mounted) {
        setState(() => _currentUser = savedUser);
        await _loadLedgerForCurrentUser();
      }
    } catch (_) {}

    // 1. Escuchar cambios reales de conectividad del celular (Wi-Fi / Datos / Modo Avión)
    _sync.onConnectivityChanged = (bool isOnline) async {
      if (!mounted) return;
      if (!isOnline) {
        _showSnack('✈️ Sin señal: los cambios se guardarán localmente en tu celular.');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      await _attemptAutoSync(notifyOnSuccess: true);
    };

    try {
      final onlineNow = await _sync.init();
      if (onlineNow) {
        await _attemptAutoSync(notifyOnSuccess: false);
        await _refreshCollective();
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
    if (result.syncedCount > 0 ||
        result.syncedUsersCount > 0 ||
        result.syncedProductsCount > 0) {
      await _loadLedgerForCurrentUser();
      if (notifyOnSuccess) {
        final parts = <String>[];
        if (result.syncedUsersCount > 0) parts.add('tienda sincronizada');
        if (result.syncedProductsCount > 0) {
          parts.add('${result.syncedProductsCount} producto${result.syncedProductsCount == 1 ? "" : "s"}');
        }
        if (result.syncedCount > 0) {
          parts.add('${result.syncedCount} movimiento${result.syncedCount == 1 ? "" : "s"}');
        }
        _showSnack('☁️ ¡Internet detectado! Subido al servidor: ${parts.join(", ")}.');
      }
    }
    if (result.reachedServer) {
      await _refreshCollective();
    }
  }

  Future<void> _refreshCollective() async {
    if (_loadingCollective) return;
    if (mounted) setState(() => _loadingCollective = true);
    try {
      final data = await _sync.fetchCollectiveSummary();
      if (mounted && data != null) {
        setState(() => _collectiveData = data);
      }
    } finally {
      if (mounted) setState(() => _loadingCollective = false);
    }
  }

  Future<void> _handleJoinProduct({
    required String productId,
    required String productName,
    required String unit,
    required double quantity,
  }) async {
    final user = _currentUser;
    if (user == null) return;
    if (mounted) setState(() => _loadingCollective = true);
    try {
      final live = await _sync.joinCollectiveOrder(
        user: user,
        productId: productId,
        productName: productName,
        unit: unit,
        quantity: quantity,
      );
      if (!mounted) return;
      if (live != null) {
        setState(() => _collectiveData = live);
        _showSnack('🎉 ¡Sumaste +${quantity.toInt()} $unit a $productName en el servidor!');
      } else {
        _showSnack('✈️ Sin señal: se sincronizará cuando recuperes conexión.');
      }
    } finally {
      if (mounted) setState(() => _loadingCollective = false);
    }
  }

  Future<void> _handleProposePurchase(ProposePurchaseInput input) async {
    final user = _currentUser;
    if (user == null) return;
    if (mounted) setState(() => _loadingCollective = true);
    try {
      final live = await _sync.joinCollectiveOrder(
        user: user,
        productId: input.productId,
        productName: input.productName,
        unit: input.unit,
        quantity: input.quantity,
      );
      if (!mounted) return;
      if (live != null) {
        setState(() => _collectiveData = live);
        _showSnack('🎉 ¡Compra colectiva de "${input.productName}" publicada en el tablón!');
      } else {
        _showSnack('✈️ Sin señal: se publicará al recuperar conexión.');
      }
    } finally {
      if (mounted) setState(() => _loadingCollective = false);
    }
  }

  void _handleOrderInCommunity(ProductStock product) {
    setState(() {
      _selectedTab = 2; // Pestaña Comunidad
      _focusCollectiveProductId = product.id;
    });
    _refreshCollective();
  }

  Future<void> _handleReceiveToInventory({
    required String productId,
    required String productName,
    required double quantity,
    required String unit,
  }) async {
    final user = _currentUser;
    if (user == null) return;

    await _ledger.recordMovement(
      businessId: user.id,
      productId: productId,
      productName: productName,
      isSale: false, // ENTRADA por despacho de compra colectiva
      quantity: quantity,
      unit: unit,
      synced: false,
    );
    await _loadLedgerForCurrentUser();
    await _attemptAutoSync(notifyOnSuccess: false);

    _showSnack(
      '📦 ¡Ingresados +${quantity.toInt()} $unit de $productName a tu Bodega con descuento mayorista!',
    );
  }

  Future<void> _handleAddCustomProduct(NewProductInput input) async {
    final user = _currentUser;
    if (user == null) return;

    await _ledger.addCustomProduct(
      businessId: user.id,
      name: input.name,
      category: input.category,
      unit: input.unit,
      minThreshold: input.minThreshold,
      synonyms: input.synonyms,
      synced: false,
    );
    await _loadLedgerForCurrentUser();

    final online = await _sync.checkOnlineNow();
    if (!online) {
      _showSnack('💾 "${input.name}" guardado en tu bodega local y listo para dictar por voz.');
      return;
    }

    final syncRes = await _sync.syncPendingMovements();
    if (syncRes.reachedServer) {
      _showSnack('✅ "${input.name}" agregado a tu bodega, voz offline y servidor Rust.');
    } else {
      _showSnack('💾 "${input.name}" guardado localmente (se subirá al conectar).');
    }
  }

  Future<void> _loadLedgerForCurrentUser() async {
    final user = _currentUser;
    if (user == null) return;

    final freshCatalog = _buildBaseCatalog(isDemoStore: user.isDemo);
    final customRows = await _ledger.getCustomProducts(user.id);
    _nlp.setCustomProducts(customRows);

    for (final cp in customRows) {
      freshCatalog.add(
        ProductStock(
          id: cp['id'].toString(),
          icon: '📦',
          name: cp['name'].toString(),
          category: (cp['category'] ?? 'Mi Tienda').toString(),
          unit: (cp['unit'] ?? 'unidades').toString(),
          openingStock: 0,
          quantity: 0,
          minThreshold: (cp['min_threshold'] as num?)?.toDouble() ?? 5.0,
        ),
      );
    }

    final rows = await _ledger.getAllMovements(user.id);
    final now = DateTime.now();
    final startOfDayMs = DateTime(now.year, now.month, now.day, 0, 0, 0).millisecondsSinceEpoch;
    final endOfDayMs = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    final logs = <MovementLog>[];
    for (final row in rows) {
      final pid = row['product_id'].toString();
      final isSale = row['type'].toString() == 'OUT';
      final qty = (row['quantity'] as num).toDouble();
      final ts = (row['timestamp'] as num).toInt();
      final prod = freshCatalog.where((p) => p.id == pid).firstOrNull;
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
        _inventory = freshCatalog;
        _recentMovements
          ..clear()
          ..addAll(logs);
      });
    }
  }

  Future<void> _onUserAuthenticated(MerchantProfile profile) async {
    setState(() {
      _currentUser = profile;
      _selectedTab = 0;
      _liveTranscript = '';
    });
    await _loadLedgerForCurrentUser();
    await _attemptAutoSync(notifyOnSuccess: true);
    await _refreshCollective();
  }

  Future<void> _onLogout() async {
    await _ledger.setActiveUserId(null);
    if (!mounted) return;
    setState(() {
      _currentUser = null;
      _recentMovements.clear();
      _inventory = _buildBaseCatalog(isDemoStore: false);
    });
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
      _showSnack('⚠️ Escuché "$phrase", pero no reconocí productos del catálogo.');
      return;
    }

    final batch = <MovementItemInput>[];
    for (final item in parsed) {
      final prod = _inventory.where((p) => p.id == item.productId).firstOrNull;
      if (prod != null) {
        batch.add(
          MovementItemInput(
            product: prod,
            isSale: item.action == 'SALIDA',
            quantity: item.quantity,
          ),
        );
      }
    }

    if (batch.isEmpty) {
      _showSnack('⚠️ No encontré los productos escuchados en tu bodega.');
      return;
    }

    _openConfirmBatch(batch);
  }

  void _openConfirmBatch(List<MovementItemInput> batch) {
    final user = _currentUser;
    if (user == null || batch.isEmpty) return;

    showOrigoConfirmationSheet(
      context: context,
      items: batch,
      onConfirm: (confirmedItems) async {
        // 0. Validación defensiva para cada producto
        for (final item in confirmedItems) {
          if (item.isSale && item.quantity > item.product.quantity + 1e-6) {
            final availStr = item.product.quantity % 1 == 0
                ? item.product.quantity.toInt().toString()
                : item.product.quantity.toStringAsFixed(1);
            _showSnack(
              '⚠️ Stock insuficiente para ${item.product.name}: solo tienes $availStr ${item.product.unit} disponibles.',
            );
            return;
          }
        }

        // 1. Guardar todos los movimientos en el Libro Mayor SQLite local
        for (final item in confirmedItems) {
          await _ledger.recordMovement(
            businessId: user.id,
            productId: item.product.id,
            productName: item.product.name,
            isSale: item.isSale,
            quantity: item.quantity,
            unit: item.product.unit,
            synced: false,
          );
        }

        await _loadLedgerForCurrentUser();
        if (mounted) setState(() => _liveTranscript = '');

        final summaryList = confirmedItems.map((i) {
          final q = i.quantity % 1 == 0 ? i.quantity.toInt() : i.quantity;
          return '${i.isSale ? "Venta" : "Entrada"}: $q ${i.product.unit} de ${i.product.name}';
        }).join(', ');

        // 2. Verificar conectividad real del celular y subir si hay internet
        final online = await _sync.checkOnlineNow();
        if (!online) {
          _showSnack('✈️ Sin señal: guardado en tu bodega local: $summaryList');
          return;
        }

        final syncRes = await _sync.syncPendingMovements();
        await _loadLedgerForCurrentUser();
        if (syncRes.reachedServer) {
          _showSnack('✅ ¡$summaryList guardados y sincronizados!');
        } else {
          _showSnack('💾 Guardado en local: $summaryList');
        }
      },
    );
  }

  void _openConfirm(ProductStock product, {bool isSale = true, double qty = 1}) {
    _openConfirmBatch([
      MovementItemInput(product: product, isSale: isSale, quantity: qty),
    ]);
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
              'Dirección del servidor donde se subirán tus datos al tener Wi-Fi o datos móviles:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL del servidor',
                hintText: 'http://10.209.55.173:8000',
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
                _showSnack('✔ Servidor guardado. Sincronizando...');
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
        ledger: _ledger,
        sync: _sync,
        onAuthenticated: _onUserAuthenticated,
      );
    }

    final lowCount = _inventory.where((e) => e.isCritical).length;

    return Scaffold(
      body: Column(
        children: [
          OrigoHeader(
            ownerName: _currentUser!.ownerName,
            storeLocation: '${_currentUser!.businessName} · ${_currentUser!.zone}',
            documentId: _currentUser!.documentId,
            address: _currentUser!.address,
            onConfigureServer: _openServerConfigDialog,
            onLogout: _onLogout,
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
                  onAddProduct: _handleAddCustomProduct,
                  onOrderInCommunity: _handleOrderInCommunity,
                ),
                CommunityScreen(
                  zone: _currentUser!.zone,
                  currentBusinessId: _currentUser!.id,
                  liveData: _collectiveData,
                  isLoading: _loadingCollective,
                  focusProductId: _focusCollectiveProductId,
                  onRefresh: _refreshCollective,
                  onJoinProduct: _handleJoinProduct,
                  onProposePurchase: _handleProposePurchase,
                  onReceiveToInventory: _handleReceiveToInventory,
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
        onDestinationSelected: (idx) {
          setState(() => _selectedTab = idx);
          if (idx == 2) _refreshCollective();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Bodega'),
          NavigationDestination(icon: Icon(Icons.groups_rounded), label: 'Comunidad'),
        ],
      ),
    );
  }
}
