import 'package:flutter/material.dart';

void main() {
  runApp(const OrigoApp());
}

class OrigoApp extends StatelessWidget {
  const OrigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Origo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF059669),
          primary: const Color(0xFF059669),
          secondary: const Color(0xFFF59E0B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool isListening = false;
  bool isOfflineMode = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🌾 Origo Casanare', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(isOfflineMode ? Icons.airplanemode_active : Icons.wifi),
            tooltip: isOfflineMode ? 'Modo Sin Conexión' : 'Conectado a Internet',
            onPressed: () {
              setState(() {
                isOfflineMode = !isOfflineMode;
              });
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('🎙️ Inventario por Voz (Offline)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Mantén presionado para dictar una entrada o salida', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTapDown: (_) => setState(() => isListening = true),
                      onTapUp: (_) => setState(() => isListening = false),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: isListening ? Colors.red : const Color(0xFF059669),
                        child: Icon(isListening ? Icons.mic : Icons.mic_none, size: 40, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(isListening ? 'Escuchando en el Llano...' : 'Presionar y hablar', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('📦 Balance de Stock Inmutable', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: const [
                  ListTile(
                    leading: CircleAvatar(child: Text('🌾')),
                    title: Text('Arroz Casanareño'),
                    subtitle: Text('Mínimo: 10 bultos'),
                    trailing: Text('5 bultos (Crítico)', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                  Divider(),
                  ListTile(
                    leading: CircleAvatar(child: Text('🛢️')),
                    title: Text('Aceite Vegetal 900ml'),
                    subtitle: Text('Mínimo: 5 cajas'),
                    trailing: Text('10 cajas', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                  Divider(),
                  ListTile(
                    leading: CircleAvatar(child: Text('🧂')),
                    title: Text('Sal Marina Refinada'),
                    subtitle: Text('Mínimo: 5 bultos'),
                    trailing: Text('3 bultos (Crítico)', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
