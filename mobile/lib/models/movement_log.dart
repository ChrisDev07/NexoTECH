/// Registro inmutable de movimiento de inventario (Event Sourcing local).
class MovementLog {
  final String icon;
  final String productName;
  final bool isSale;
  final double quantity;
  final String unit;
  bool synced;

  MovementLog({
    required this.icon,
    required this.productName,
    required this.isSale,
    required this.quantity,
    required this.unit,
    required this.synced,
  });
}
