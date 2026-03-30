class CustomerSuggestionModel {
  final String customerName;
  final String? customerPhone;
  final String? category;
  final String? customerType;
  final String? notes;
  final String? location;
  final DateTime lastSeenAt;

  const CustomerSuggestionModel({
    required this.customerName,
    this.customerPhone,
    this.category,
    this.customerType,
    this.notes,
    this.location,
    required this.lastSeenAt,
  });

  String get normalizedName => _normalize(customerName);
  String get normalizedPhone => _normalize(customerPhone ?? '');

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
