import 'package:flutter/material.dart';

class CommunityScreen extends StatelessWidget {
  final String zone;
  final String currentBusinessId;
  final Map<String, dynamic>? liveData;
  final int localExtraBultos;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onJoinOrder;

  const CommunityScreen({
    super.key,
    required this.zone,
    required this.currentBusinessId,
    required this.liveData,
    required this.localExtraBultos,
    required this.isLoading,
    required this.onRefresh,
    required this.onJoinOrder,
  });

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

  @override
  Widget build(BuildContext context) {
    final isLive = liveData != null && (liveData!['products'] as List? ?? []).isNotEmpty;
    final prod = isLive
        ? (liveData!['products'] as List).first as Map<String, dynamic>
        : null;

    final double totalBultos = isLive
        ? (prod!['total_quantity'] as num).toDouble()
        : (70 + localExtraBultos).toDouble();
    final int storesCount = isLive
        ? (liveData!['participating_stores_count'] as num).toInt()
        : 4;
    final double discountPct = isLive
        ? (prod!['discount_percentage'] as num).toDouble()
        : 16.2;
    final num productSavings = isLive
        ? (prod!['savings_cop'] as num)
        : (2100000 + localExtraBultos * 30000);
    final num freightSavings = isLive
        ? (liveData!['freight_savings_cop'] as num)
        : 360000;
    final num freightPerStore = isLive
        ? (liveData!['freight_per_store_cop'] as num)
        : 30000;
    final num totalSavings = isLive
        ? (liveData!['total_net_savings_cop'] as num)
        : (2460000 + localExtraBultos * 30000);
    final contributions = isLive
        ? (prod!['contributions'] as List? ?? []).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                  const Expanded(
                    child: Text(
                      '🤝 Juntos compramos más barato',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar desde el servidor',
                    onPressed: isLoading ? null : onRefresh,
                    icon: isLoading
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
                '$zone · $storesCount tiendas unidas para precio de molino y flete compartido.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isLive
                      ? '☁️ Conectado en vivo al servidor Rust'
                      : '✈️ Vista local (se sincronizará al conectar)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
                '${totalBultos.toInt()} / 100 bultos reunidos · $discountPct% Descuento',
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
              Text(
                '💰 Ahorro total en $zone',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatCop(totalSavings),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF047857),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Descuento volumen: ${_formatCop(productSavings)}\n'
                'Ahorro en flete: ${_formatCop(freightSavings)} (${_formatCop(freightPerStore)} por tienda)',
                style: const TextStyle(color: Color(0xFF78350F), fontSize: 13),
              ),
            ],
          ),
        ),
        if (contributions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE7E5E4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🏪 Tiendas participantes',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 10),
                ...contributions.map((c) {
                  final isMe = c['business_id'].toString() == currentBusinessId;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '🏪 ${c['business_name']}${isMe ? ' (Tú)' : ''}',
                            style: TextStyle(
                              fontWeight: isMe ? FontWeight.w900 : FontWeight.w700,
                              color: isMe ? const Color(0xFF047857) : const Color(0xFF1C1917),
                            ),
                          ),
                        ),
                        Text(
                          '${(c['quantity'] as num).toInt()} bultos',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: const Color(0xFF1C1917),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: isLoading ? null : onJoinOrder,
          child: const Text(
            '🤝 Sumar +10 bultos a la compra semanal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
