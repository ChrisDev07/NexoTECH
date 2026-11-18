import 'package:flutter/material.dart';
import '../models/merchant_profile.dart';
import '../services/offline_ledger.dart';
import '../services/sync_service.dart';
import '../widgets/privacy_dialog.dart';

class LoginScreen extends StatefulWidget {
  final OfflineLedgerService ledger;
  final AutoSyncService sync;
  final void Function(MerchantProfile profile) onAuthenticated;

  const LoginScreen({
    super.key,
    required this.ledger,
    required this.sync,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;
  bool _habeasAccepted = false;
  bool _busy = false;
  String _selectedZone = 'Yopal';
  String? _errorText;

  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  final _documentCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  final List<String> _zones = const [
    'Yopal',
    'Aguazul',
    'Villanueva',
    'Tauramena',
    'Maní',
    'Paz de Ariporo',
    'Monterrey',
    'Pore',
    'Trinidad',
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _ownerCtrl.dispose();
    _businessCtrl.dispose();
    _documentCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _showPrivacyDialog() {
    showOrigoPrivacyDialog(context);
  }

  Future<void> _handleSubmit() async {
    if (_busy) return;
    setState(() {
      _errorText = null;
      _busy = true;
    });

    try {
      if (_isRegister) {
        final res = await widget.ledger.registerLocalUser(
          ownerName: _ownerCtrl.text,
          businessName: _businessCtrl.text,
          documentId: _documentCtrl.text,
          address: _addressCtrl.text,
          zone: _selectedZone,
          phone: _phoneCtrl.text,
          pin: _pinCtrl.text,
          habeasAccepted: _habeasAccepted,
        );
        if (!mounted) return;
        if (res.error != null || res.profile == null) {
          setState(() => _errorText = res.error ?? 'Error al crear la tienda.');
          return;
        }
        widget.onAuthenticated(res.profile!);
      } else {
        // 1. Si hay internet, validar primero contra el servidor Rust y descargar movimientos/productos
        final remote = await widget.sync.loginOnlineAndPull(
          phone: _phoneCtrl.text,
          pin: _pinCtrl.text,
        );
        if (!mounted) return;
        if (remote.profile != null) {
          widget.onAuthenticated(remote.profile!);
          return;
        }
        // Si el servidor respondió error explícito (401), verificar si la cuenta existe offline local sin sincronizar
        final local = await widget.ledger.loginLocalUser(
          phone: _phoneCtrl.text,
          pin: _pinCtrl.text,
        );
        if (!mounted) return;
        if (local.profile != null) {
          widget.onAuthenticated(local.profile!);
          return;
        }
        setState(
          () => _errorText = remote.error ?? local.error ?? 'Credenciales inválidas.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleDemoLogin() async {
    if (_busy) return;
    setState(() {
      _errorText = null;
      _busy = true;
    });
    try {
      final profile = await widget.ledger.loginDemoUser();
      if (!mounted) return;
      widget.onAuthenticated(profile);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF047857), Color(0xFF065F46)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: const Column(
              children: [
                Text(
                  '🌾 ORIGO',
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'Inventario por voz sin internet y compras en comunidad para Casanare',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 2,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Entrar')),
                        ButtonSegment(value: true, label: Text('Crear tienda')),
                      ],
                      selected: {_isRegister},
                      onSelectionChanged: (s) => setState(() {
                        _isRegister = s.first;
                        _errorText = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (_errorText != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '⚠️ $_errorText',
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_isRegister) ...[
                      TextField(
                        controller: _ownerCtrl,
                        decoration: const InputDecoration(
                          labelText: '👤 Nombre del comerciante',
                          hintText: 'Ej. Don Pedro',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _documentCtrl,
                        decoration: const InputDecoration(
                          labelText: '🪪 Cédula de Ciudadanía / NIT',
                          hintText: 'Ej. 74.852.140',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _businessCtrl,
                        decoration: const InputDecoration(
                          labelText: '🏪 Nombre de tu negocio',
                          hintText: 'Ej. Tienda La Esperanza',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: '📍 Dirección exacta del local',
                          hintText: 'Ej. Calle 24 # 18-35, Yopal',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedZone,
                        decoration: const InputDecoration(labelText: '📍 Municipio (Casanare)'),
                        items: _zones
                            .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedZone = v ?? _selectedZone),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: '📱 Número celular'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '🔐 Clave numérica (4–6 dígitos)'),
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE7E5E4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('🛡️ ', style: TextStyle(fontSize: 14)),
                                Expanded(
                                  child: Text(
                                    'AVISO DE PRIVACIDAD (Ley 1581 / Dec. 1074)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1C1917),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'En cumplimiento de la Ley 1581 de 2012 y el Decreto 1074 de 2015, le informamos que los datos personales suministrados serán tratados para gestionar su registro, operación comercial, inventario, ventas, pedidos y contacto dentro de esta aplicación. Frente a los datos de clientes finales registrados por los comercios, la MiPyme usuaria actúa como Responsable del Tratamiento y la Gobernación de Casanare, como operadora de la plataforma, actúa como Encargada del Tratamiento. Usted puede ejercer sus derechos a conocer, actualizar, rectificar y suprimir sus datos, así como consultar nuestra Política de Tratamiento de Datos Personales directamente en esta aplicación.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: Color(0xFF57534E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _showPrivacyDialog,
                              child: const Text(
                                '📄 Ver Política de Tratamiento de Datos Personales (enlace offline)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF047857),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _habeasAccepted,
                        onChanged: (v) => setState(() => _habeasAccepted = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'He leído el Aviso de Privacidad y autorizo de manera previa, expresa e informada el tratamiento de mis datos personales conforme a la Política de Tratamiento de Datos Personales.',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _busy ? null : _handleSubmit,
                      child: Text(
                        _isRegister ? '✨ Crear mi tienda' : '✔ Entrar a mi tienda',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!_isRegister) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _busy ? null : _handleDemoLogin,
                        child: const Text('⚡ Entrar con cuenta demo (Don Pedro)'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
