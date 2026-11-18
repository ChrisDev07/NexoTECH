import 'package:flutter/material.dart';
import '../models/product_stock.dart';

class ProductCard extends StatelessWidget {
  final ProductStock item;
  final VoidCallback onTap;
  final VoidCallback? onOrderInCommunity;

  const ProductCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onOrderInCommunity,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
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
            onTap: onTap,
          ),
          if (item.isCritical) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '⚠️ Quedan solo ${item.quantity.toInt()} ${item.unit}',
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (onOrderInCommunity != null)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        side: const BorderSide(color: Color(0xFF047857), width: 1.2),
                        foregroundColor: const Color(0xFF047857),
                        backgroundColor: const Color(0xFFECFDF5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      icon: const Icon(Icons.group_work_rounded, size: 14),
                      label: const Text(
                        '🛒 Pedir en comunidad',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                      onPressed: onOrderInCommunity,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
