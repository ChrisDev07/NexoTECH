import 'package:flutter/material.dart';
import '../models/movement_log.dart';

class HomeScreen extends StatelessWidget {
  final bool isListening;
  final bool isVoiceModelReady;
  final String liveTranscript;
  final int lowStockCount;
  final bool isHistoryExpanded;
  final List<MovementLog> recentMovements;
  final VoidCallback onToggleMic;
  final VoidCallback onOpenCommunity;
  final VoidCallback onToggleHistory;
  final Future<void> Function()? onManualSync;
  final bool isSyncing;

  const HomeScreen({
    super.key,
    required this.isListening,
    this.isVoiceModelReady = true,
    this.liveTranscript = '',
    required this.lowStockCount,
    required this.isHistoryExpanded,
    required this.recentMovements,
    required this.onToggleMic,
    required this.onOpenCommunity,
    required this.onToggleHistory,
    this.onManualSync,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasPending = recentMovements.any((m) => !m.synced);

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Tarjeta Hero de Voz
        Container(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onToggleMic,
                child: CircleAvatar(
                  radius: 64,
                  backgroundColor: isListening ? Colors.red : const Color(0xFF047857),
                  child: Icon(
                    isListening ? Icons.mic : Icons.mic_none,
                    size: 62,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isListening
                    ? '🔴 Escuchando... Toca al terminar'
                    : (isVoiceModelReady
                        ? 'Presiona para hablar (100% Offline)'
                        : '⏳ Preparando voz sin internet...'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isListening ? Colors.red : const Color(0xFF047857),
                ),
              ),
              if (liveTranscript.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '"$liveTranscript"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF57534E),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Alerta de reposición
        if (lowStockCount > 0) ...[
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
                    '⚠️ Tienes $lowStockCount productos bajos de inventario',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                  onPressed: onOpenCommunity,
                  child: const Text('Pedir juntos'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Acordeón desplegable de Últimos Movimientos
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggleHistory,
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
                    InkWell(
                      onTap: onManualSync,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasPending
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasPending
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSyncing)
                              const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFB45309),
                                ),
                              )
                            else
                              Icon(
                                hasPending ? Icons.sync_rounded : Icons.cloud_done_rounded,
                                size: 13,
                                color: hasPending
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF047857),
                              ),
                            const SizedBox(width: 4),
                            Text(
                              isSyncing
                                  ? 'Sincronizando...'
                                  : (hasPending ? '⏳ Pendientes (Sincronizar)' : '☁️ Al día'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: hasPending
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF047857),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isHistoryExpanded
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
        if (isHistoryExpanded)
          ...recentMovements.take(8).map((m) {
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

    return onManualSync != null
        ? RefreshIndicator(
            onRefresh: onManualSync!,
            color: const Color(0xFF047857),
            child: list,
          )
        : list;
  }
}
