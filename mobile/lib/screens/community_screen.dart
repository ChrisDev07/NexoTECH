import 'package:flutter/material.dart';

class CommunityScreen extends StatelessWidget {
  final int extraBultos;
  final VoidCallback onJoinOrder;

  const CommunityScreen({
    super.key,
    required this.extraBultos,
    required this.onJoinOrder,
  });

  @override
  Widget build(BuildContext context) {
    final totalBultos = 70 + extraBultos;
    final totalSavings = 2460000 + (extraBultos * 30000);

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
          onPressed: onJoinOrder,
          child: const Text(
            '🤝 Sumar mi pedido a la compra semanal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
