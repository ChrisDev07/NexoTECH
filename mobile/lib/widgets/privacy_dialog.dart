import 'package:flutter/material.dart';

/// Diálogo oficial de Política de Tratamiento de Datos Personales (Ley 1581 de 2012 y Decreto 1074 de 2015).
/// Cumple con los requisitos legales para la convocatoria CREATIC Casanare.
void showOrigoPrivacyDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Text('🛡️ '),
          Expanded(
            child: Text(
              'Política de Tratamiento de Datos',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ley 1581 de 2012 y Decreto 1074 de 2015',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF047857),
                fontSize: 12.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Finalidades y Derechos:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            SizedBox(height: 5),
            Text(
              'Declaro haber sido informado(a) de que mis datos serán utilizados exclusivamente para gestionar pedidos, ventas, entregas, control de cartera/fiados y comunicación comercial; que es facultativo responder preguntas sobre datos sensibles; y que puedo ejercer gratuitamente mis derechos a conocer, actualizar, rectificar y suprimir mis datos conforme a la Política de Tratamiento de Datos Personales disponible en la aplicación y en www.casanare.gov.co.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF292524)),
            ),
            SizedBox(height: 14),
            Text(
              'Roles de Tratamiento:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            SizedBox(height: 5),
            Text(
              '• Responsable: La MiPyme usuaria actúa como Responsable del Tratamiento frente a los datos de sus clientes y su negocio.\n'
              '• Encargada: La Gobernación de Casanare y la plataforma Origo actúan como Encargadas del Tratamiento técnico seguro.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF44403C)),
            ),
            SizedBox(height: 14),
            Text(
              'Seguridad Criptográfica y Garantías:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            SizedBox(height: 5),
            Text(
              '✔ Clave/PIN protegida con PBKDF2-SHA256 (100.000 iteraciones) y sal criptográfica única.\n'
              '✔ Base de datos local SQLite aislada con protección anti-extracción (sin backups no autorizados).\n'
              '✔ Principio de minimización: no comercializamos ni cedemos tus datos a terceros.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF44403C)),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
