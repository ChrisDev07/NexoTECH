/// Perfil autenticado de una MiPyme en Origo (minimización de datos Ley 1581).
class MerchantProfile {
  final String id;
  final String ownerName;
  final String businessName;
  final String zone;
  final String phone;

  const MerchantProfile({
    required this.id,
    required this.ownerName,
    required this.businessName,
    required this.zone,
    required this.phone,
  });

  bool get isDemo => id == 'tienda_demo';
}
