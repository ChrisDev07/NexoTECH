import 'package:flutter/material.dart';

class OrigoHeader extends StatelessWidget {
  final String ownerName;
  final String storeLocation;
  final String documentId;
  final String address;
  final VoidCallback? onConfigureServer;
  final VoidCallback? onShowPrivacy;
  final VoidCallback? onLogout;
  final bool hasPendingSync;
  final bool isSyncing;
  final VoidCallback? onManualSync;

  const OrigoHeader({
    super.key,
    required this.ownerName,
    required this.storeLocation,
    this.documentId = '',
    this.address = '',
    this.onConfigureServer,
    this.onShowPrivacy,
    this.onLogout,
    this.hasPendingSync = false,
    this.isSyncing = false,
    this.onManualSync,
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
                  color: Colors.white.withValues(alpha: 0.18),
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
              Row(
                children: [
                  if (hasPendingSync || isSyncing)
                    IconButton(
                      onPressed: isSyncing ? null : onManualSync,
                      icon: isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.cloud_upload_rounded,
                              color: Color(0xFFFDE68A),
                              size: 24,
                            ),
                      tooltip: isSyncing
                          ? 'Sincronizando con la nube...'
                          : 'Sincronizar cambios pendientes con la nube',
                    ),
                  if (onShowPrivacy != null)
                    IconButton(
                      onPressed: onShowPrivacy,
                      icon: const Icon(Icons.shield_outlined, color: Colors.white, size: 21),
                      tooltip: 'Política de Privacidad (Ley 1581)',
                    ),
                  if (onConfigureServer != null)
                    IconButton(
                      onPressed: onConfigureServer,
                      icon: const Icon(Icons.dns_rounded, color: Colors.white, size: 21),
                      tooltip: 'Servidor de sincronización',
                    ),
                  if (onLogout != null)
                    IconButton(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 21),
                      tooltip: 'Cerrar sesión',
                    ),
                ],
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
            '🏪 $storeLocation',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (documentId.isNotEmpty || address.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '${documentId.isNotEmpty ? "🪪 CC/NIT: $documentId" : ""}${documentId.isNotEmpty && address.isNotEmpty ? " · " : ""}${address.isNotEmpty ? "📍 $address" : ""}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
