import 'package:flutter/material.dart';
import '../models/merchant_profile.dart';
import '../services/offline_ledger.dart';

class LoginScreen extends StatefulWidget {
  final OfflineLedgerService ledger;
  final void Function(MerchantProfile profile) onAuthenticated;

  const LoginScreen({
    super.key,
    required this.ledger,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;
  bool _habeasAccepted = false;
  bool _busy = false;
  String _selectedZone = 'Comuna 2, Yopal';
  String? _errorText;

  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();

  final List<String> _zones = const [
    'Comuna 2, Yopal',
    'Comuna 5, Yopal',
    'Centro, Aguazul',
    'Villanueva',
    'Tauramena',
    'Maní',
    'Paz de Ariporo',
    'Monterrey',
  ];

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🛡️ Aviso de Privacidad (Ley 1581)'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'En Origo aplicamos minimización de datos: solo solicitamos tu nombre, negocio, zona y celular para operar tu inventario y compras colectivas.',
              ),
              SizedBox(height: 12),
              Text(
                'Responsable: La MiPyme usuaria.\nEncargado: Dirección TIC Gobernación de Casanare / Origo.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text(
                '✔ Conocer, actualizar y suprimir tus datos.\n'
                '✔ Claves protegidas con hash criptográfico + sal única.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
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
        final res = await widget.ledger.loginLocalUser(
          phone: _phoneCtrl.text,
          pin: _pinCtrl.text,
        );
        if (!mounted) return;
        if (res.error != null || res.profile == null) {
          setState(() => _errorText = res.error ?? 'Credenciales inválidas.');
          return;
        }
        widget.onAuthenticated(res.profile!);
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
                        decoration: const InputDecoration(labelText: '👤 Tu nombre'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _businessCtrl,
                        decoration: const InputDecoration(labelText: '🏪 Nombre de tu negocio'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedZone,
                        decoration: const InputDecoration(labelText: '📍 Zona en Casanare'),
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
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _habeasAccepted,
                        onChanged: (v) => setState(() => _habeasAccepted = v ?? false),
                        title: const Text(
                          'Acepto el Aviso de Privacidad (Ley 1581 de 2012)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _showPrivacyDialog,
                        child: const Text('🛡️ Leer Política de Privacidad completa'),
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
