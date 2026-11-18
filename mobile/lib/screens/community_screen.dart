import 'package:flutter/material.dart';

class ProposePurchaseInput {
  final String productId;
  final String productName;
  final String unit;
  final double quantity;

  const ProposePurchaseInput({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
  });
}

class CommunityScreen extends StatefulWidget {
  final String zone;
  final String currentBusinessId;
  final Map<String, dynamic>? liveData;
  final bool isLoading;
  final String? focusProductId;
  final VoidCallback onRefresh;
  final Future<void> Function({
    required String productId,
    required String productName,
    required String unit,
    required double quantity,
  }) onJoinProduct;
  final Future<void> Function(ProposePurchaseInput input) onProposePurchase;
  final Future<void> Function({
    required String productId,
    required String productName,
    required double quantity,
    required String unit,
  })? onReceiveToInventory;

  const CommunityScreen({
    super.key,
    required this.zone,
    required this.currentBusinessId,
    required this.liveData,
    required this.isLoading,
    this.focusProductId,
    required this.onRefresh,
    required this.onJoinProduct,
    required this.onProposePurchase,
    this.onReceiveToInventory,
  });

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final Map<String, double> _cardStepQuantities = {};
  final Set<String> _receivedProductIds = {};
  int _expandedIndex = 0; // Primera tarjeta desplegada por defecto

  @override
  void initState() {
    super.initState();
    _syncFocusedProduct();
  }

  @override
  void didUpdateWidget(covariant CommunityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusProductId != oldWidget.focusProductId && widget.focusProductId != null) {
      _syncFocusedProduct();
    }
  }

  void _syncFocusedProduct() {
    if (widget.focusProductId == null) return;
    final live = widget.liveData;
    final products = (live != null ? (live['products'] as List? ?? []) : [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final idx = products.indexWhere((p) => p['product_id'] == widget.focusProductId);
    if (idx != -1) {
      setState(() => _expandedIndex = idx);
    }
  }

  static const Map<String, String> _icons = {
    'prod_arroz_casanare': '🌾',
    'prod_aceite_vegetal': '🛢️',
    'prod_panela_criolla': '🟫',
    'prod_papa_pastusa': '🥔',
    'prod_abono_triple15': '🌱',
    'prod_cemento_gris': '🧱',
    'prod_sal_marina': '🧂',
    'prod_harina_pan': '🌽',
  };

  String _formatCop(num value) {
    final s = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final posFromEnd = s.length - i;
      buf.write(s[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) {
        buf.write('.');
      }
    }
    return '\$$buf COP';
  }

  void _openProposeSheet() {
    String selectedProduct = 'prod_arroz_casanare';
    String customName = '';
    String selectedUnit = 'bultos';
    final qtyCtrl = TextEditingController(text: '10');

    const products = [
      {'id': 'prod_arroz_casanare', 'name': 'Arroz Casanareño (50kg)', 'unit': 'bultos', 'icon': '🌾'},
      {'id': 'prod_aceite_vegetal', 'name': 'Aceite Vegetal 900ml', 'unit': 'cajas', 'icon': '🛢️'},
      {'id': 'prod_cemento_gris', 'name': 'Cemento Gris 50kg', 'unit': 'bultos', 'icon': '🧱'},
      {'id': 'prod_abono_triple15', 'name': 'Abono Triple 15', 'unit': 'bultos', 'icon': '🌱'},
      {'id': 'prod_panela_criolla', 'name': 'Panela Criolla', 'unit': 'pacas', 'icon': '🟫'},
      {'id': 'prod_papa_pastusa', 'name': 'Papa Pastusa / Criolla', 'unit': 'arrobas', 'icon': '🥔'},
      {'id': 'prod_sal_marina', 'name': 'Sal Marina Refinada', 'unit': 'bultos', 'icon': '🧂'},
      {'id': 'prod_harina_pan', 'name': 'Harina de Maíz Precocida', 'unit': 'pacas', 'icon': '🌽'},
      {'id': 'custom', 'name': '✨ Otro artículo personalizado...', 'unit': 'bultos', 'icon': '📦'},
    ];

    const units = [
      'bultos',
      'cajas',
      'pacas',
      'arrobas',
      'kilos',
      'libras',
      'unidades',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isCustom = selectedProduct == 'custom';

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '➕ Proponer compra colectiva',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Publica un artículo en el tablón comunitario para que las tiendas de tu zona se unan al pedido.',
                    style: TextStyle(color: Color(0xFF57534E), fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedProduct,
                    decoration: const InputDecoration(labelText: '📦 Artículo'),
                    items: products.map((p) {
                      return DropdownMenuItem<String>(
                        value: p['id'],
                        child: Text('${p['icon']} ${p['name']}'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setSheetState(() {
                          selectedProduct = v;
                          if (v != 'custom') {
                            final found = products.firstWhere((p) => p['id'] == v);
                            selectedUnit = found['unit'] ?? 'bultos';
                          }
                        });
                      }
                    },
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => customName = v,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del artículo',
                        hintText: 'Ej. Lenteja Importada 50kg',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedUnit,
                          decoration: const InputDecoration(labelText: '📏 Unidad'),
                          items: units
                              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: (v) => setSheetState(() => selectedUnit = v ?? selectedUnit),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Mi aporte inicial',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 10.0;
                      String finalId = selectedProduct;
                      String finalName = '';
                      if (isCustom) {
                        if (customName.trim().length < 2) return;
                        finalName = customName.trim();
                        finalId = 'prod_custom_${DateTime.now().millisecondsSinceEpoch}';
                      } else {
                        final found = products.firstWhere((p) => p['id'] == selectedProduct);
                        finalName = found['name'] ?? 'Producto';
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      await widget.onProposePurchase(
                        ProposePurchaseInput(
                          productId: finalId,
                          productName: finalName,
                          unit: selectedUnit,
                          quantity: qty > 0 ? qty : 5.0,
                        ),
                      );
                    },
                    child: const Text(
                      '✔ Publicar en el Tablón',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.liveData;
    final products = (live != null ? (live['products'] as List? ?? []) : [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // Fallback baseline si no hay conexión al servidor
    final displayProducts = products.isNotEmpty
        ? products
        : [
            {
              'product_id': 'prod_arroz_casanare',
              'product_name': 'Arroz Casanareño (50kg)',
              'total_quantity': 70.0,
              'target_quantity': 100.0,
              'unit': 'bultos',
              'discount_percentage': 16.2,
              'savings_cop': 2100000.0,
              'stores_count': 4,
              'contributions': [
                {'business_id': 't2', 'business_name': 'Agroinsumos Doña Martha', 'quantity': 25.0},
                {'business_id': 't3', 'business_name': 'Minimarket El Llano', 'quantity': 20.0},
                {'business_id': 'tienda_demo', 'business_name': 'Tienda La Esperanza', 'quantity': 15.0},
                {'business_id': 't4', 'business_name': 'Comercializadora El Triunfo', 'quantity': 10.0},
              ],
            },
            {
              'product_id': 'prod_aceite_vegetal',
              'product_name': 'Aceite Vegetal 900ml',
              'total_quantity': 26.0,
              'target_quantity': 40.0,
              'unit': 'cajas',
              'discount_percentage': 18.3,
              'savings_cop': 546000.0,
              'stores_count': 3,
              'contributions': [
                {'business_id': 't3', 'business_name': 'Minimarket El Llano', 'quantity': 10.0},
                {'business_id': 'tienda_demo', 'business_name': 'Tienda La Esperanza', 'quantity': 8.0},
                {'business_id': 't5', 'business_name': 'Granero El Morichal', 'quantity': 8.0},
              ],
            },
          ];

    final int storesCount = (live?['participating_stores_count'] as num?)?.toInt() ?? 4;
    final num totalSavings = (live?['total_net_savings_cop'] as num?) ?? 2460000;
    final num freightSavings = (live?['freight_savings_cop'] as num?) ?? 360000;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF047857), Color(0xFF0F766E)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '🤝 Tablón Comunitario · ${widget.zone}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar desde el servidor',
                    onPressed: widget.isLoading ? null : widget.onRefresh,
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Compras agrupadas por artículo para obtener precio de distribuidor y flete compartido.',
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      live != null ? '☁️ Conectado en vivo' : '✈️ Vista local',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '· $storesCount tiendas en la red',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Resumen Ahorro Total Red - 3 Métricas de Impacto Regional
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '💰 Impacto Regional Casanare',
                    style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF92400E), fontSize: 14),
                  ),
                  FilledButton.icon(
                    onPressed: _openProposeSheet,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Proponer compra', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ahorro red', style: TextStyle(fontSize: 11, color: Color(0xFF78350F))),
                          Text(
                            _formatCop(totalSavings),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF047857)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Flete unificado', style: TextStyle(fontSize: 11, color: Color(0xFF78350F))),
                          Text(
                            _formatCop(freightSavings),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFB45309)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Comercios', style: TextStyle(fontSize: 11, color: Color(0xFF78350F))),
                          Text(
                            '$storesCount tiendas',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF065F46)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Cabecera Tablón
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '📋 Pedidos activos en el Tablón',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            Text(
              '${displayProducts.length} artículo${displayProducts.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Color(0xFF57534E), fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Lista de Tarjetas Desplegables del Tablón (Acordeón)
        ...displayProducts.asMap().entries.map((entry) {
          final idx = entry.key;
          final prod = entry.value;
          final isExpanded = idx == _expandedIndex;

          final pid = prod['product_id'].toString();
          final pname = prod['product_name'].toString();
          final unit = (prod['unit'] ?? 'bultos').toString();
          final icon = _icons[pid] ?? '📦';

          final double currentQty = (prod['total_quantity'] as num?)?.toDouble() ?? 0.0;
          final double targetQty = (prod['target_quantity'] as num?)?.toDouble() ?? 50.0;
          final double discountPct = (prod['discount_percentage'] as num?)?.toDouble() ?? 0.0;
          final num savingsCop = (prod['savings_cop'] as num?) ?? 0;
          final int storesInProd = (prod['stores_count'] as num?)?.toInt() ?? 1;

          final contributions = (prod['contributions'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();

          final myContribution = contributions.where(
            (c) => c['business_id'].toString() == widget.currentBusinessId,
          ).firstOrNull;

          final stepQty = _cardStepQuantities[pid] ?? 10.0;
          final progress = (currentQty / targetQty).clamp(0.0, 1.0);

          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            elevation: isExpanded ? 2.5 : 1,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isExpanded ? const Color(0xFF047857) : const Color(0xFFE7E5E4),
                width: isExpanded ? 1.8 : 1.0,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _expandedIndex = _expandedIndex == idx ? -1 : idx;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header de la tarjeta
                    Row(
                      children: [
                        Text(icon, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pname,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${currentQty.toInt()} / ${targetQty.toInt()} $unit reunidos',
                                style: const TextStyle(
                                  color: Color(0xFF57534E),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.timer_outlined, size: 11, color: Color(0xFF92400E)),
                                        SizedBox(width: 3),
                                        Text(
                                          'Cierre: Jueves 6:00 PM',
                                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: progress >= 1.0 ? const Color(0xFFD1FAE5) : const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFA7F3D0), width: 0.8),
                                    ),
                                    child: Text(
                                      progress >= 1.0 ? '🎉 Meta lista' : '🟢 Ronda Activa',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: progress >= 1.0 ? const Color(0xFF065F46) : const Color(0xFF047857),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$discountPct% Dcto',
                            style: const TextStyle(
                              color: Color(0xFF065F46),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: const Color(0xFF78716C),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Barra de progreso
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(999),
                      color: const Color(0xFF059669),
                      backgroundColor: const Color(0xFFE7E5E4),
                    ),

                    // Contenido Desplegable (Detalles + Tiendas + Botón Participar)
                    if (isExpanded) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Despacho logístico regional
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.local_shipping_outlined, size: 16, color: Color(0xFF57534E)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Despacho: Molino aliado ➔ Circuito comercial Yopal (Sábados 9:00 AM)',
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF44403C), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Desglose de ahorros
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Ahorro por volumen:', style: TextStyle(fontSize: 11, color: Color(0xFF065F46))),
                                  Text(
                                    _formatCop(savingsCop),
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF047857), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Tiendas unidas:', style: TextStyle(fontSize: 11, color: Color(0xFF92400E))),
                                  Text(
                                    '$storesInProd tiendas',
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB45309), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Quiénes están participando
                      const Text(
                        '🏪 Tiendas participantes en este pedido:',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const SizedBox(height: 8),
                      ...contributions.map((c) {
                        final isMe = c['business_id'].toString() == widget.currentBusinessId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFFD1FAE5) : const Color(0xFFFAF9F6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isMe ? const Color(0xFFA7F3D0) : const Color(0xFFE7E5E4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🏪 ${c['business_name']}${isMe ? ' (Tú)' : ''}',
                                style: TextStyle(
                                  fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
                                  color: isMe ? const Color(0xFF065F46) : const Color(0xFF1C1917),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${(c['quantity'] as num).toInt()} $unit',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isMe ? const Color(0xFF047857) : const Color(0xFF57534E),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 14),

                      // Selector Interactivo de Cantidad para Participar
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF9F6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD6D3D1)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  myContribution != null
                                      ? 'Aporte actual: ${(myContribution['quantity'] as num).toInt()} $unit'
                                      : '¿Cuánto necesitas pedir?',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                                ),
                                const Text(
                                  'Directo al molino',
                                  style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w700, fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setState(() {
                                      final cur = _cardStepQuantities[pid] ?? 10.0;
                                      if (cur > 5) {
                                        _cardStepQuantities[pid] = cur - 5;
                                      } else if (cur > 1) {
                                        _cardStepQuantities[pid] = cur - 1;
                                      }
                                    });
                                  },
                                  icon: const Icon(Icons.remove_rounded),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  '+${stepQty.toInt()} $unit',
                                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(width: 16),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setState(() {
                                      final cur = _cardStepQuantities[pid] ?? 10.0;
                                      _cardStepQuantities[pid] = cur + 5;
                                    });
                                  },
                                  icon: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF047857),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: widget.isLoading
                                    ? null
                                    : () async {
                                        await widget.onJoinProduct(
                                          productId: pid,
                                          productName: pname,
                                          unit: unit,
                                          quantity: stepQty,
                                        );
                                      },
                                child: Text(
                                  myContribution != null
                                      ? '🤝 Aumentar pedido (+${stepQty.toInt()} $unit)'
                                      : '🤝 Participar con ${stepQty.toInt()} $unit',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (myContribution != null) ...[
                        const SizedBox(height: 12),
                        Builder(
                          builder: (ctx) {
                            final isGoalReached = currentQty >= targetQty;
                            final isAlreadyReceived = _receivedProductIds.contains(pid);
                            final myQty = (myContribution['quantity'] as num).toInt();
                            final remainingQty = (targetQty - currentQty).clamp(0.0, targetQty).toInt();

                            if (isAlreadyReceived) {
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F4),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFD6D3D1)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '✔ ¡Pedido recibido e ingresado a Mi Bodega! (+$myQty $unit)',
                                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1C1917), fontSize: 13),
                                          ),
                                          const Text(
                                            'Inventario contable actualizado con descuento mayorista.',
                                            style: TextStyle(fontSize: 11.5, color: Color(0xFF57534E)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            if (!isGoalReached) {
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309), size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Aporte activo: $myQty $unit (En espera de meta)',
                                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF92400E), fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Faltan $remainingQty $unit para completar la meta de ${targetQty.toInt()} $unit. Al completarse, el molino despacha y se habilitará la recepción.',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F)),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFD6D3D1)),
                                        foregroundColor: const Color(0xFF78716C),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.lock_outline_rounded, size: 18),
                                      label: Text(
                                        '🔒 Esperando meta (${currentQty.toInt()}/${targetQty.toInt()} $unit)',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                      ),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '⏳ Esta compra se despachará cuando se completen los $remainingQty $unit restantes.',
                                            ),
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }

                            // Meta alcanzada: se habilita la recepción
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.local_shipping_rounded, color: Color(0xFF047857), size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '🎉 ¡Meta alcanzada! Pedido despachado por el molino.',
                                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF065F46), fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'La carga ha llegado al circuito comercial. Toca para confirmar entrega y cargar a Mi Bodega.',
                                    style: TextStyle(fontSize: 11.5, color: Color(0xFF047857)),
                                  ),
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF047857),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.inventory_2_rounded, size: 18),
                                    label: Text(
                                      '📦 Recibir pedido en Mi Bodega (+$myQty $unit)',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                    onPressed: () async {
                                      setState(() {
                                        _receivedProductIds.add(pid);
                                      });
                                      await widget.onReceiveToInventory?.call(
                                        productId: pid,
                                        productName: pname,
                                        quantity: (myContribution['quantity'] as num).toDouble(),
                                        unit: unit,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
