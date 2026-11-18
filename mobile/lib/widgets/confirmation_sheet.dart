import 'package:flutter/material.dart';
import '../models/product_stock.dart';

String _fmtQty(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

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
          final double available = product.quantity;
          final bool exceedsStock = currentIsSale && currentQty > available + 1e-6;

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
                    border: Border.all(
                      color: exceedsStock ? const Color(0xFFEF4444) : const Color(0xFFE7E5E4),
                      width: 2,
                    ),
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
                          Text(
                            '📦 Stock: ${_fmtQty(available)} ${product.unit}',
                            style: TextStyle(
                              color: available <= 0
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF047857),
                              fontWeight: FontWeight.w800,
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
                                if (currentQty > 1) {
                                  setModalState(() => currentQty -= 1);
                                } else if (currentQty > 0.5) {
                                  setModalState(() => currentQty = 0.5);
                                }
                              },
                              icon: const Icon(Icons.remove, size: 28),
                            ),
                            Text(
                              '${_fmtQty(currentQty)} ${product.unit}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: exceedsStock
                                    ? const Color(0xFFB91C1C)
                                    : const Color(0xFF1C1917),
                              ),
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
                      if (exceedsStock) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                available <= 0
                                    ? '⚠️ No tienes existencias de ${product.name} en bodega (0 ${product.unit}). Registra primero una entrada.'
                                    : '⚠️ Stock insuficiente: solo tienes ${_fmtQty(available)} ${product.unit} disponibles y estás intentando vender ${_fmtQty(currentQty)} ${product.unit}.',
                                style: const TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              if (available > 0) ...[
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF991B1B),
                                    side: const BorderSide(color: Color(0xFFDC2626)),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                  ),
                                  onPressed: () => setModalState(() => currentQty = available),
                                  child: Text(
                                    'Ajustar a ${_fmtQty(available)} ${product.unit} (disponible)',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
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
                    onPressed: exceedsStock
                        ? null
                        : () {
                            onConfirm(currentIsSale, currentQty);
                            Navigator.pop(ctx);
                          },
                    child: Text(
                      exceedsStock
                          ? '⛔ Stock insuficiente para vender'
                          : '✔ Sí, es correcto (Guardar)',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
