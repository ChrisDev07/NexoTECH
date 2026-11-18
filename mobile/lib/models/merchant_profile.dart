/// Perfil comercial autenticado de una MiPyme en Origo.
class MerchantProfile {
  final String id;
  final String ownerName;
  final String businessName;
  final String documentId; // Cédula de Ciudadanía o NIT para facturación y despacho
  final String address;    // Dirección física exacta del local comercial
  final String zone;
  final String phone;

  const MerchantProfile({
    required this.id,
    required this.ownerName,
    required this.businessName,
    this.documentId = '',
    this.address = '',
    required this.zone,
    required this.phone,
  });

  bool get isDemo => id == 'tienda_demo';
}
