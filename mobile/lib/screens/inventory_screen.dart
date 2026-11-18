import 'package:flutter/material.dart';
import '../models/product_stock.dart';
import '../widgets/product_card.dart';

class NewProductInput {
  final String name;
  final String category;
  final String unit;
  final double minThreshold;
  final List<String> synonyms;

  const NewProductInput({
    required this.name,
    required this.category,
    required this.unit,
    required this.minThreshold,
    required this.synonyms,
  });
}

class InventoryScreen extends StatefulWidget {
  final List<ProductStock> inventory;
  final void Function(ProductStock product) onSelectProduct;
  final Future<void> Function(NewProductInput input) onAddProduct;
  final void Function(ProductStock product)? onOrderInCommunity;

  const InventoryScreen({
    super.key,
    required this.inventory,
    required this.onSelectProduct,
    required this.onAddProduct,
    this.onOrderInCommunity,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _onlyMovedToday = false;

  void _openNewProductSheet() {
    final nameCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: '5');
    final synCtrl = TextEditingController();
    String selectedCategory = 'Víveres';
    String selectedUnit = 'unidades';

    const categories = [
      'Víveres',
      'Granos y Víveres',
      'Perecederos',
      'Agroinsumos',
      'Ferretería',
      'Mi Tienda',
    ];
    const units = [
      'unidades',
      'bultos',
      'cajas',
      'pacas',
      'arrobas',
      'kilos',
      'libras',
      'botellas',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
                  '➕ Nuevo producto en Mi Bodega',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Quedará disponible al instante en tu bodega y en el dictado por voz offline.',
                  style: TextStyle(color: Color(0xFF57534E), fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: '📦 Nombre del producto',
                    hintText: 'Ej. Café Tostado Yopal',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: '🏷️ Categoría'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedCategory = v ?? selectedCategory),
                ),
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
                        onChanged: (v) => setModalState(() => selectedUnit = v ?? selectedUnit),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '⚠️ Stock mínimo',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: synCtrl,
                  decoration: const InputDecoration(
                    labelText: '🎙️ Apodos de voz (opcional)',
                    hintText: 'Ej. cafe, cafecito, tinto',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.length < 2) return;
                    final minVal = double.tryParse(minCtrl.text.trim()) ?? 5.0;
                    final syns = synCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    if (ctx.mounted) Navigator.pop(ctx);
                    await widget.onAddProduct(
                      NewProductInput(
                        name: name,
                        category: selectedCategory,
                        unit: selectedUnit,
                        minThreshold: minVal > 0 ? minVal : 5.0,
                        synonyms: syns,
                      ),
                    );
                  },
                  child: const Text(
                    '✔ Guardar producto',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalIn = widget.inventory.fold<double>(0, (sum, p) => sum + p.todayIn);
    final totalOut = widget.inventory.fold<double>(0, (sum, p) => sum + p.todayOut);
    final items = _onlyMovedToday
        ? widget.inventory.where((p) => p.hasActivityToday).toList()
        : widget.inventory;

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
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _openNewProductSheet,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nuevo', style: TextStyle(fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD1FAE5),
                foregroundColor: const Color(0xFF065F46),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => ProductCard(
            item: item,
            onTap: () => widget.onSelectProduct(item),
            onOrderInCommunity: widget.onOrderInCommunity != null ? () => widget.onOrderInCommunity!(item) : null,
          ),
        ),
      ],
    );
  }
}
