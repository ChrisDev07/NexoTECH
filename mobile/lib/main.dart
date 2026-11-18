import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'models/merchant_profile.dart';
import 'models/movement_log.dart';
import 'models/product_stock.dart';
import 'screens/community_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/login_screen.dart';
import 'services/nlp_service.dart';
import 'services/offline_ledger.dart';
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
  final SpeechToText _speech = SpeechToText();

  MerchantProfile? _currentUser;
  int _selectedTab = 0;
  bool _isOfflineMode = true;
  bool _isListening = false;
  bool _speechReady = false;
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
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted && _isListening) {
            setState(() => _isListening = false);
            if (_liveTranscript.trim().isNotEmpty) {
              _handleSpokenPhrase(_liveTranscript);
            }
          }
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
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
      await _speech.stop();
      setState(() => _isListening = false);
      if (_liveTranscript.trim().isNotEmpty) {
        _handleSpokenPhrase(_liveTranscript);
      }
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize();
    }

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Permite el micrófono para dictar por voz.')),
      );
      return;
    }

    setState(() {
      _liveTranscript = '';
      _isListening = true;
    });

    await _speech.listen(
      localeId: 'es_CO',
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (res) {
        if (!mounted) return;
        setState(() => _liveTranscript = res.recognizedWords);
        if (res.finalResult && res.recognizedWords.trim().isNotEmpty) {
          setState(() => _isListening = false);
          _handleSpokenPhrase(res.recognizedWords);
        }
      },
    );
  }

  void _handleSpokenPhrase(String phrase) {
    final parsed = _nlp.parsePhrase(phrase);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ No reconocí un producto en: "$phrase"')),
      );
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
        await _ledger.recordMovement(
          productId: product.id,
          productName: product.name,
          isSale: confirmedSale,
          quantity: confirmedQty,
          unit: product.unit,
          synced: !_isOfflineMode,
        );
        await _loadLedgerFromSqlite();
        if (!mounted) return;
        setState(() => _liveTranscript = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOfflineMode
                  ? '💾 Guardado sin internet en SQLite (pendiente de sincronizar)'
                  : '✅ ¡Guardado en el inventario del día!',
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return LoginScreen(
        onAuthenticated: (profile) => setState(() => _currentUser = profile),
      );
    }

    final lowCount = _inventory.where((e) => e.isCritical).length;

    return Scaffold(
      body: Column(
        children: [
          OrigoHeader(
            ownerName: _currentUser!.ownerName,
            storeLocation: '${_currentUser!.businessName} · ${_currentUser!.zone}',
            isOfflineMode: _isOfflineMode,
            onLogout: () => setState(() => _currentUser = null),
            onToggleOffline: () async {
              final nextOffline = !_isOfflineMode;
              if (!nextOffline) {
                await _ledger.markAllSynced();
                await _loadLedgerFromSqlite();
              }
              if (mounted) {
                setState(() => _isOfflineMode = nextOffline);
              }
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                HomeScreen(
                  isListening: _isListening,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('🎉 ¡Sumaste +10 bultos al pedido comunitario!')),
                    );
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
