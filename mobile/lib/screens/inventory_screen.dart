import 'package:flutter/material.dart';
import '../models/product_stock.dart';
import '../widgets/product_card.dart';

class InventoryScreen extends StatefulWidget {
  final List<ProductStock> inventory;
  final void Function(ProductStock product) onSelectProduct;

  const InventoryScreen({
    super.key,
    required this.inventory,
    required this.onSelectProduct,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _onlyMovedToday = false;

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
          ],
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => ProductCard(
            item: item,
            onTap: () => widget.onSelectProduct(item),
          ),
        ),
      ],
    );
  }
}
