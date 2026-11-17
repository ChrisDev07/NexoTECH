import 'package:flutter/material.dart';

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

class ProductStock {
  final String id;
  final String icon;
  final String name;
  final String category;
  final String unit;
  final double openingStock;
  double todayIn;
  double todayOut;
  double quantity;
  final double minThreshold;

  ProductStock({
    required this.id,
    required this.icon,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.minThreshold,
    double? openingStock,
    this.todayIn = 0,
    this.todayOut = 0,
  }) : openingStock = openingStock ?? quantity;

  bool get isCritical => quantity <= minThreshold;
  bool get hasActivityToday => todayIn > 0 || todayOut > 0;
}

class MovementLog {
  final String icon;
  final String productName;
  final bool isSale;
  final double quantity;
  final String unit;
  bool synced;

  MovementLog({
    required this.icon,
    required this.productName,
    required this.isSale,
    required this.quantity,
    required this.unit,
    required this.synced,
  });
}

class OrigoHomeShell extends StatefulWidget {
  const OrigoHomeShell({super.key});

  @override
  State<OrigoHomeShell> createState() => _OrigoHomeShellState();
}

class _OrigoHomeShellState extends State<OrigoHomeShell> {
  int _selectedTab = 0;
  bool _isOfflineMode = true;
  bool _isListening = false;
  bool _isHistoryExpanded = true;
  bool _onlyMovedToday = false;
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
      icon: '🧱',
      productName: 'Cemento Gris 50kg',
      isSale: false,
      quantity: 10,
      unit: 'bultos',
      synced: true,
    ),
    MovementLog(
      icon: '🥔',
      productName: 'Papa Pastusa / Criolla',
      isSale: true,
      quantity: 3,
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
      quantity: 5,
      minThreshold: 10,
    ),
    ProductStock(
      id: 'prod_aceite_vegetal',
      icon: '🛢️',
      name: 'Aceite Vegetal 900ml',
      category: 'Víveres',
      unit: 'cajas',
      quantity: 14,
      minThreshold: 5,
    ),
    ProductStock(
      id: 'prod_papa_pastusa',
      icon: '🥔',
      name: 'Papa Pastusa / Criolla',
      category: 'Perecederos',
      unit: 'arrobas',
      quantity: 3,
      minThreshold: 6,
    ),
    ProductStock(
      id: 'prod_cemento_gris',
      icon: '🧱',
      name: 'Cemento Gris 50kg',
      category: 'Ferretería',
      unit: 'bultos',
      quantity: 25,
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

  void _openConfirmationSheet({
    required ProductStock product,
    required bool isSale,
    required double initialQty,
  }) {
    bool currentIsSale = isSale;
    double currentQty = initialQty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D3D1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '👂 ¿Lo entendí bien?',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ajusta la cantidad con + o − antes de guardar',
                    style: TextStyle(color: Color(0xFF57534E), fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF9F6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE7E5E4), width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => setModalState(() => currentIsSale = !currentIsSale),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: currentIsSale
                                      ? const Color(0xFFFFEDD5)
                                      : const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  currentIsSale ? '📤 Venta realizada ⇄' : '📥 Mercancía recibida ⇄',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: currentIsSale
                                        ? const Color(0xFFC2410C)
                                        : const Color(0xFF065F46),
                                  ),
                                ),
                              ),
                            ),
                            const Text(
                              '✨ 100% Entendido',
                              style: TextStyle(
                                color: Color(0xFF047857),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${product.icon} ${product.name}',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD6D3D1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFD1FAE5),
                                  foregroundColor: const Color(0xFF065F46),
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () {
                                  if (currentQty > 0.5) {
                                    setModalState(() => currentQty -= 1);
                                  }
                                },
                                icon: const Icon(Icons.remove, size: 28),
                              ),
                              Text(
                                '${currentQty.toStringAsFixed(currentQty % 1 == 0 ? 0 : 1)} ${product.unit}',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                              ),
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFD1FAE5),
                                  foregroundColor: const Color(0xFF065F46),
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () => setModalState(() => currentQty += 1),
                                icon: const Icon(Icons.add, size: 28),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        setState(() {
                          if (currentIsSale) {
                            product.quantity = (product.quantity - currentQty).clamp(0, 9999);
                            product.todayOut += currentQty;
                          } else {
                            product.quantity += currentQty;
                            product.todayIn += currentQty;
                          }
                          _recentMovements.insert(
                            0,
                            MovementLog(
                              icon: product.icon,
                              productName: product.name,
                              isSale: currentIsSale,
                              quantity: currentQty,
                              unit: product.unit,
                              synced: !_isOfflineMode,
                            ),
                          );
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isOfflineMode
                                  ? '💾 Guardado sin internet (pendiente de sincronizar)'
                                  : '✅ ¡Guardado en tu inventario!',
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        '✔ Sí, es correcto (Guardar)',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        '❌ Descartar o volver a hablar',
                        style: TextStyle(color: Color(0xFF57534E), fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF065F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '🌾 ORIGO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _isOfflineMode = !_isOfflineMode;
                    if (!_isOfflineMode) {
                      for (final m in _recentMovements) {
                        m.synced = true;
                      }
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isOfflineMode
                        ? const Color(0xFFF59E0B)
                        : Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _isOfflineMode ? '✈️ Sin Internet' : '🟢 Conectado',
                    style: TextStyle(
                      color: _isOfflineMode ? const Color(0xFF1C1917) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '¡Hola, Don Pedro! ☀️',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '📍 Tienda La Esperanza · Comuna 2, Yopal',
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ProductStock item) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: item.isCritical ? const Color(0xFFFFFAFA) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: item.isCritical ? const Color(0xFFFCA5A5) : const Color(0xFFE7E5E4),
          width: 1.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(item.icon, style: const TextStyle(fontSize: 24)),
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        subtitle: Text(
          item.hasActivityToday
              ? '00:00: ${item.openingStock.toInt()} · Hoy: +${item.todayIn.toInt()} / -${item.todayOut.toInt()}'
              : '00:00: ${item.openingStock.toInt()} · Sin movimientos hoy',
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: item.isCritical ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${item.isCritical ? "⚠️ " : "✔ "}${item.quantity.toInt()} ${item.unit}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: item.isCritical ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
            ),
          ),
        ),
        onTap: () => _openConfirmationSheet(product: item, isSale: true, initialQty: 1),
      ),
    );
  }

  Widget _buildHomeTab() {
    final lowCount = _inventory.where((e) => e.isCritical).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Tarjeta Hero de Voz
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7E5E4)),
          ),
          child: Column(
            children: [
              const Text(
                'Registra con tu voz',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sin teclados ni formularios. Funciona incluso sin internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF57534E), fontSize: 14),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () {
                  setState(() => _isListening = !_isListening);
                  if (!_isListening) {
                    _openConfirmationSheet(
                      product: _inventory.first,
                      isSale: true,
                      initialQty: 3,
                    );
                  }
                },
                child: CircleAvatar(
                  radius: 46,
                  backgroundColor: _isListening ? Colors.red : const Color(0xFF047857),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    size: 46,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isListening ? '🔴 Escuchando... Toca al terminar' : 'Presiona para hablar',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _isListening ? Colors.red : const Color(0xFF047857),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (lowCount > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '⚠️ Tienes $lowCount productos bajos de inventario',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                  onPressed: () => setState(() => _selectedTab = 2),
                  child: const Text('Pedir juntos'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _isHistoryExpanded = !_isHistoryExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE7E5E4), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📜 Últimos movimientos',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                Row(
                  children: [
                    Text(
                      _recentMovements.any((m) => !m.synced)
                          ? '⏳ Pendientes'
                          : '☁️ Al día',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _recentMovements.any((m) => !m.synced)
                            ? const Color(0xFFB45309)
                            : const Color(0xFF047857),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isHistoryExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF1C1917),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_isHistoryExpanded)
          ..._recentMovements.take(8).map((m) {
          final qtyText = m.quantity.toStringAsFixed(m.quantity % 1 == 0 ? 0 : 1);
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE7E5E4)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(m.icon, style: const TextStyle(fontSize: 22)),
              ),
              title: Text(
                '${m.isSale ? "📤 Venta" : "📥 Entrada"} · $qtyText ${m.unit}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              subtitle: Text(m.productName),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: m.synced ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  m.synced ? '☁️ Sync' : '⏳ Offline',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: m.synced ? const Color(0xFF047857) : const Color(0xFFB45309),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInventoryTab() {
    final totalIn = _inventory.fold<double>(0, (sum, p) => sum + p.todayIn);
    final totalOut = _inventory.fold<double>(0, (sum, p) => sum + p.todayOut);
    final items = _onlyMovedToday
        ? _inventory.where((p) => p.hasActivityToday).toList()
        : _inventory;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📦 Inventario del día',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF047857),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '🕒 00:00 – 23:59',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '+${totalIn.toInt()}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF047857),
                            ),
                          ),
                          const Text('📥 Entradas hoy', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '-${totalOut.toInt()}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFC2410C),
                            ),
                          ),
                          const Text('📤 Ventas hoy', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Todos'),
              selected: !_onlyMovedToday,
              onSelected: (_) => setState(() => _onlyMovedToday = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('📅 Movidos hoy'),
              selected: _onlyMovedToday,
              onSelected: (_) => setState(() => _onlyMovedToday = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map(_buildProductCard),
      ],
    );
  }

  Widget _buildCommunityTab() {
    final totalBultos = 70 + _extraCollectiveBultos;
    final totalSavings = 2460000 + (_extraCollectiveBultos * 30000);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF047857), Color(0xFF0F766E)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🤝 Juntos compramos más barato',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'Comuna 2, Yopal · 4 tiendas unidas para precio de molino y flete compartido.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7E5E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🌾 Arroz Casanareño (50kg)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: (totalBultos / 100).clamp(0.0, 1.0),
                minHeight: 14,
                borderRadius: BorderRadius.circular(999),
                color: const Color(0xFF059669),
                backgroundColor: const Color(0xFFE7E5E4),
              ),
              const SizedBox(height: 8),
              Text(
                '$totalBultos / 100 bultos reunidos · 16.2% Descuento',
                style: const TextStyle(color: Color(0xFF57534E), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF59E0B), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '💰 Ahorro total en la Comuna 2',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '\$$totalSavings COP',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF047857),
                ),
              ),
              const Text(
                'Incluye descuento mayorista + flete compartido (\$30.000 por tienda)',
                style: TextStyle(color: Color(0xFF78350F), fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: const Color(0xFF1C1917),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () {
            setState(() => _extraCollectiveBultos += 10);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🎉 ¡Sumaste +10 bultos al pedido comunitario!')),
            );
          },
          child: const Text(
            '🤝 Sumar mi pedido a la compra semanal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildHomeTab(),
                _buildInventoryTab(),
                _buildCommunityTab(),
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
