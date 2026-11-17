/// Modelo de inventario diario (00:00 - 23:59) para un producto regional de Origo.
class ProductStock {
  final String id;
  final String icon;
  final String name;
  final String category;
  final String unit;
  final double openingStock;
  double todayIn;
  double todayOut;
  double quantity;
  final double minThreshold;

  ProductStock({
    required this.id,
    required this.icon,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.minThreshold,
    double? openingStock,
    this.todayIn = 0,
    this.todayOut = 0,
  }) : openingStock = openingStock ?? quantity;

  bool get isCritical => quantity <= minThreshold;
  bool get hasActivityToday => todayIn > 0 || todayOut > 0;
}
