import 'package:flutter/material.dart';
import 'models/merchant_profile.dart';
import 'models/movement_log.dart';
import 'models/product_stock.dart';
import 'screens/community_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/login_screen.dart';
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
  MerchantProfile? _currentUser;
  int _selectedTab = 0;
  bool _isOfflineMode = true;
  bool _isListening = false;
  bool _isHistoryExpanded = true;
  int _extraCollectiveBultos = 0;

  final List<MovementLog> _recentMovements = [
    MovementLog(
      icon: '🌾',
      productName: 'Arroz Casanareño',
      isSale: true,
      quantity: 5,
      unit: 'bultos',
      synced: true,
    ),
    MovementLog(
      icon: '🥔',
      productName: 'Papa Pastusa / Criolla',
      isSale: true,
      quantity: 4,
      unit: 'arrobas',
      synced: true,
    ),
  ];

  final List<ProductStock> _inventory = [
    ProductStock(
      id: 'prod_arroz_casanare',
      icon: '🌾',
      name: 'Arroz Casanareño',
      category: 'Granos y Víveres',
      unit: 'bultos',
      openingStock: 20,
      todayOut: 5,
      quantity: 15,
      minThreshold: 10,
    ),
    ProductStock(
      id: 'prod_aceite_vegetal',
      icon: '🛢️',
      name: 'Aceite Vegetal 900ml',
      category: 'Víveres',
      unit: 'cajas',
      quantity: 10,
      minThreshold: 5,
    ),
    ProductStock(
      id: 'prod_papa_pastusa',
      icon: '🥔',
      name: 'Papa Pastusa / Criolla',
      category: 'Perecederos',
      unit: 'arrobas',
      openingStock: 12,
      todayOut: 4,
      quantity: 8,
      minThreshold: 6,
    ),
    ProductStock(
      id: 'prod_cemento_gris',
      icon: '🧱',
      name: 'Cemento Gris 50kg',
      category: 'Ferretería',
      unit: 'bultos',
      quantity: 30,
      minThreshold: 20,
    ),
    ProductStock(
      id: 'prod_sal_marina',
      icon: '🧂',
      name: 'Sal Marina Refinada',
      category: 'Víveres',
      unit: 'bultos',
      quantity: 8,
      minThreshold: 5,
    ),
  ];

  void _openConfirm(ProductStock product, {bool isSale = true, double qty = 1}) {
    showOrigoConfirmationSheet(
      context: context,
      product: product,
      initialIsSale: isSale,
      initialQty: qty,
      onConfirm: (confirmedSale, confirmedQty) {
        setState(() {
          if (confirmedSale) {
            product.quantity = (product.quantity - confirmedQty).clamp(0, 9999);
            product.todayOut += confirmedQty;
          } else {
            product.quantity += confirmedQty;
            product.todayIn += confirmedQty;
          }
          _recentMovements.insert(
            0,
            MovementLog(
              icon: product.icon,
              productName: product.name,
              isSale: confirmedSale,
              quantity: confirmedQty,
              unit: product.unit,
              synced: !_isOfflineMode,
            ),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOfflineMode
                  ? '💾 Guardado sin internet (pendiente de sincronizar)'
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
            onToggleOffline: () {
              setState(() {
                _isOfflineMode = !_isOfflineMode;
                if (!_isOfflineMode) {
                  for (final m in _recentMovements) {
                    m.synced = true;
                  }
                }
              });
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                HomeScreen(
                  isListening: _isListening,
                  lowStockCount: lowCount,
                  isHistoryExpanded: _isHistoryExpanded,
                  recentMovements: _recentMovements,
                  onToggleMic: () {
                    setState(() => _isListening = !_isListening);
                    if (!_isListening) {
                      _openConfirm(_inventory.first, isSale: true, qty: 3);
                    }
                  },
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
