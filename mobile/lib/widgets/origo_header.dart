import 'package:flutter/material.dart';

class OrigoHeader extends StatelessWidget {
  final String ownerName;
  final String storeLocation;
  final bool isOfflineMode;
  final VoidCallback onToggleOffline;

  const OrigoHeader({
    super.key,
    required this.ownerName,
    required this.storeLocation,
    required this.isOfflineMode,
    required this.onToggleOffline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF047857), Color(0xFF065F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '🌾 ORIGO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              InkWell(
                onTap: onToggleOffline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOfflineMode
                        ? const Color(0xFFF59E0B)
                        : Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isOfflineMode ? '✈️ Sin Internet' : '🟢 Conectado',
                    style: TextStyle(
                      color: isOfflineMode ? const Color(0xFF1C1917) : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '¡Hola, $ownerName! ☀️',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '📍 $storeLocation',
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
