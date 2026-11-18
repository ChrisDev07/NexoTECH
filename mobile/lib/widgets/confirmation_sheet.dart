import 'package:flutter/material.dart';
import '../models/product_stock.dart';

String _fmtQty(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class MovementItemInput {
  final ProductStock product;
  bool isSale;
  double quantity;

  MovementItemInput({
    required this.product,
    required this.isSale,
    required this.quantity,
  });
}

Future<void> showOrigoConfirmationSheet({
  required BuildContext context,
  required List<MovementItemInput> items,
  required void Function(List<MovementItemInput> confirmedItems) onConfirm,
}) {
  // Copia local para permitir edición interactiva en el modal
  final editableItems = items
      .map(
        (i) => MovementItemInput(
          product: i.product,
          isSale: i.isSale,
          quantity: i.quantity,
        ),
      )
      .toList();

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final bool hasMultiple = editableItems.length > 1;
          final bool hasExceedsStock = editableItems.any(
            (i) => i.isSale && i.quantity > i.product.quantity + 1e-6,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
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
                Text(
                  hasMultiple
                      ? '👂 Escuché ${editableItems.length} productos'
                      : '👂 ¿Lo entendí bien?',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  hasMultiple
                      ? 'Revisa o ajusta cada artículo antes de registrar en tu Bodega'
                      : 'Ajusta la cantidad con + o − antes de guardar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF57534E), fontSize: 13.5),
                ),
                const SizedBox(height: 14),

                // Lista de productos reconocidos (soporta 1 o múltiples)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: editableItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final item = editableItems[idx];
                      final double available = item.product.quantity;
                      final bool exceeds = item.isSale && item.quantity > available + 1e-6;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF9F6),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: exceeds ? const Color(0xFFEF4444) : const Color(0xFFE7E5E4),
                            width: exceeds ? 2 : 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => setModalState(() => item.isSale = !item.isSale),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: item.isSale
                                          ? const Color(0xFFFFEDD5)
                                          : const Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      item.isSale ? '📤 Venta realizada ⇄' : '📥 Mercancía recibida ⇄',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: item.isSale
                                            ? const Color(0xFFC2410C)
                                            : const Color(0xFF065F46),
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '📦 Stock: ${_fmtQty(available)} ${item.product.unit}',
                                      style: TextStyle(
                                        color: available <= 0
                                            ? const Color(0xFFB91C1C)
                                            : const Color(0xFF047857),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    if (editableItems.length > 1) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          setModalState(() {
                                            editableItems.removeAt(idx);
                                          });
                                          if (editableItems.isEmpty) {
                                            Navigator.pop(ctx);
                                          }
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF78716C)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${item.product.icon} ${item.product.name}',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFD6D3D1)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFD1FAE5),
                                      foregroundColor: const Color(0xFF065F46),
                                      minimumSize: const Size(42, 42),
                                    ),
                                    onPressed: () {
                                      if (item.quantity > 1) {
                                        setModalState(() => item.quantity -= 1);
                                      } else if (item.quantity > 0.5) {
                                        setModalState(() => item.quantity = 0.5);
                                      }
                                    },
                                    icon: const Icon(Icons.remove, size: 24),
                                  ),
                                  Text(
                                    '${_fmtQty(item.quantity)} ${item.product.unit}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: exceeds
                                          ? const Color(0xFFB91C1C)
                                          : const Color(0xFF1C1917),
                                    ),
                                  ),
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFD1FAE5),
                                      foregroundColor: const Color(0xFF065F46),
                                      minimumSize: const Size(42, 42),
                                    ),
                                    onPressed: () => setModalState(() => item.quantity += 1),
                                    icon: const Icon(Icons.add, size: 24),
                                  ),
                                ],
                              ),
                            ),
                            if (exceeds) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      available <= 0
                                          ? '⚠️ Sin stock en bodega (0 ${item.product.unit}). Registra una entrada.'
                                          : '⚠️ Stock insuficiente: solo tienes ${_fmtQty(available)} ${item.product.unit} y estás vendiendo ${_fmtQty(item.quantity)}.',
                                      style: const TextStyle(
                                        color: Color(0xFF991B1B),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (available > 0) ...[
                                      const SizedBox(height: 6),
                                      OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF991B1B),
                                          side: const BorderSide(color: Color(0xFFDC2626)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        ),
                                        onPressed: () => setModalState(() => item.quantity = available),
                                        child: Text(
                                          'Ajustar a ${_fmtQty(available)} ${item.product.unit} (disponible)',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      disabledBackgroundColor: const Color(0xFFD6D3D1),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: hasExceedsStock || editableItems.isEmpty
                        ? null
                        : () {
                            onConfirm(editableItems);
                            Navigator.pop(ctx);
                          },
                    child: Text(
                      hasExceedsStock
                          ? '⛔ Ajusta productos con stock insuficiente'
                          : hasMultiple
                              ? '✔ Guardar ${editableItems.length} movimientos en Mi Bodega'
                              : '✔ Sí, es correcto (Guardar)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
