// INVENTORY_PHASE1_FLUTTER_V2
// lib/models/inventory_item_model.dart

class InventoryItem {
  final String id;
  final String clinicId;
  final String name;
  final String sku;
  final String category;
  final String unit;
  final double currentQty;
  final double minimumQty;
  final bool lowStockAlertEnabled;
  final bool lowStockActive;
  final DateTime? lowStockSince;
  final bool active;

  const InventoryItem({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.sku,
    required this.category,
    required this.unit,
    required this.currentQty,
    required this.minimumQty,
    required this.lowStockAlertEnabled,
    required this.lowStockActive,
    required this.lowStockSince,
    required this.active,
  });

  static String _string(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text == 'null' ? '' : text;
  }

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_string(value)) ?? 0;
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = _string(value).toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return fallback;
  }

  static DateTime? _date(dynamic value) {
    final text = _string(value);
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: _string(json['_id'] ?? json['id']),
      clinicId: _string(json['clinicId']),
      name: _string(json['name']),
      sku: _string(json['sku']),
      category: _string(json['category']),
      unit: _string(json['unit']),
      currentQty: _number(json['currentQty']),
      minimumQty: _number(json['minimumQty']),
      lowStockAlertEnabled: _bool(json['lowStockAlertEnabled'], fallback: true),
      lowStockActive: _bool(json['lowStockActive']),
      lowStockSince: _date(json['lowStockSince']),
      active: _bool(json['active'], fallback: true),
    );
  }
}
