import 'package:flutter/material.dart';
import '../models/product_stock.dart';

Future<void> showOrigoConfirmationSheet({
  required BuildContext context,
  required ProductStock product,
  required bool initialIsSale,
  required double initialQty,
  required void Function(bool isSale, double quantity) onConfirm,
}) {
  bool currentIsSale = initialIsSale;
  double currentQty = initialQty;

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
                      onConfirm(currentIsSale, currentQty);
                      Navigator.pop(ctx);
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
