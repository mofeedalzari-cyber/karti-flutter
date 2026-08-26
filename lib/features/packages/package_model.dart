class PackageCounts {
  final int available;
  final int assigned;
  final int sold;
  const PackageCounts({this.available = 0, this.assigned = 0, this.sold = 0});
}

class PackageModel {
  final String id;
  final String networkId;
  final String name;
  final num price;
  final String? dataSize;
  final String? speed;
  final String? validity;
  final String? allowedTime;
  final String? description;
  final String? color; // "#RRGGBB" أو null
  final int sortOrder;
  final bool isActive;

  PackageModel({
    required this.id,
    required this.networkId,
    required this.name,
    required this.price,
    this.dataSize,
    this.speed,
    this.validity,
    this.allowedTime,
    this.description,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory PackageModel.fromMap(Map<String, dynamic> m) => PackageModel(
        id: m['id'] as String,
        networkId: m['network_id'] as String,
        name: m['name'] as String,
        price: (m['price'] ?? 0) as num,
        dataSize: m['data_size'] as String?,
        speed: m['speed'] as String?,
        validity: m['validity'] as String?,
        allowedTime: m['allowed_time'] as String?,
        description: m['description'] as String?,
        color: m['color'] as String?,
        sortOrder: (m['sort_order'] ?? 0) as int,
        isActive: (m['is_active'] as bool?) ?? true,
      );

  Map<String, dynamic> toInsertMap() => {
        'network_id': networkId,
        'name': name,
        'price': price,
        'data_size': dataSize,
        'speed': speed,
        'validity': validity,
        'allowed_time': allowedTime,
        'description': description,
        'color': color,
        'sort_order': sortOrder,
        'is_active': isActive,
      };
}

class NetworkLite {
  final String id;
  final String name;
  final String? currency;
  NetworkLite({required this.id, required this.name, this.currency});

  factory NetworkLite.fromMap(Map<String, dynamic> m) =>
      NetworkLite(id: m['id'] as String, name: m['name'] as String, currency: m['currency'] as String?);
}
