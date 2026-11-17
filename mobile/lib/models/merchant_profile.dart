/// Perfil autenticado de una MiPyme en Origo (minimización de datos Ley 1581).
class MerchantProfile {
  final String ownerName;
  final String businessName;
  final String zone;
  final String phone;

  const MerchantProfile({
    required this.ownerName,
    required this.businessName,
    required this.zone,
    required this.phone,
  });
}
