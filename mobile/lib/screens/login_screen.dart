import 'package:flutter/material.dart';
import '../models/merchant_profile.dart';

class LoginScreen extends StatefulWidget {
  final void Function(MerchantProfile profile) onAuthenticated;

  const LoginScreen({
    super.key,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;
  bool _habeasAccepted = false;
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
                '✔ Claves protegidas con hash PBKDF2-SHA256 + sal.',
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

  void _handleSubmit() {
    setState(() => _errorText = null);

    if (_isRegister) {
      if (!_habeasAccepted) {
        setState(() => _errorText = 'Debes aceptar el Aviso de Privacidad (Ley 1581 de 2012).');
        return;
      }
      if (_ownerCtrl.text.trim().length < 2 || _businessCtrl.text.trim().length < 2) {
        setState(() => _errorText = 'Completa tu nombre y el nombre de tu negocio.');
        return;
      }
      if (_pinCtrl.text.trim().length < 4) {
        setState(() => _errorText = 'Crea una clave de 4 a 6 números.');
        return;
      }
      widget.onAuthenticated(
        MerchantProfile(
          ownerName: _ownerCtrl.text.trim(),
          businessName: _businessCtrl.text.trim(),
          zone: _selectedZone,
          phone: _phoneCtrl.text.trim(),
        ),
      );
    } else {
      if (_phoneCtrl.text.trim().isEmpty || _pinCtrl.text.trim().length < 4) {
        setState(() => _errorText = 'Ingresa tu celular y clave numérica.');
        return;
      }
      widget.onAuthenticated(
        MerchantProfile(
          ownerName: 'Don Pedro',
          businessName: 'Tienda La Esperanza',
          zone: 'Comuna 2, Yopal',
          phone: _phoneCtrl.text.trim(),
        ),
      );
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
                        value: _selectedZone,
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
                      onPressed: _handleSubmit,
                      child: Text(
                        _isRegister ? '✨ Crear mi tienda' : '✔ Entrar a mi tienda',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (!_isRegister) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () => widget.onAuthenticated(
                          const MerchantProfile(
                            ownerName: 'Don Pedro',
                            businessName: 'Tienda La Esperanza',
                            zone: 'Comuna 2, Yopal',
                            phone: '3101234567',
                          ),
                        ),
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
