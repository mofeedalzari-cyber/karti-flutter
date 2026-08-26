// نفس منطق src/routes/app.networks.index.tsx بالضبط — بدون أي تغيير على
// جداول أو دوال قاعدة البيانات (networks, packages, cards, sales،
// وRPC: superadmin_create_network).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import '../auth/profile_provider.dart';

class NetworkModel {
  final String id;
  final String name;
  final String? description;
  final String currency;
  final String primaryColor;
  final String secondaryColor;
  final bool isActive;
  final String createdAt;

  NetworkModel({
    required this.id,
    required this.name,
    this.description,
    required this.currency,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isActive,
    required this.createdAt,
  });

  factory NetworkModel.fromMap(Map<String, dynamic> m) => NetworkModel(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        currency: (m['currency'] as String?) ?? 'ر.س',
        primaryColor: (m['primary_color'] as String?) ?? '#009688',
        secondaryColor: (m['secondary_color'] as String?) ?? '#14B8A6',
        isActive: (m['is_active'] as bool?) ?? true,
        createdAt: m['created_at'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'currency': currency,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'is_active': isActive,
      };
}

class NetworkCounts {
  final int packages;
  final int available;
  final int sold;
  final num value;
  const NetworkCounts({this.packages = 0, this.available = 0, this.sold = 0, this.value = 0});
}

final networksListProvider = FutureProvider<List<NetworkModel>>((ref) async {
  final rows = await supabase
      .from('networks')
      .select('id, name, description, currency, primary_color, secondary_color, is_active, created_at')
      .order('created_at', ascending: false);
  return (rows as List).map((r) => NetworkModel.fromMap(r)).toList();
});

/// نفس منطق حساب العدادات بالنسخة الأصلية: يجلب packages/cards/sales
/// خام ويحسب العدّ والقيمة بطرف العميل لكل شبكة.
final networkCountsProvider = FutureProvider<Map<String, NetworkCounts>>((ref) async {
  final results = await Future.wait([
    supabase.from('packages').select('network_id'),
    supabase.from('cards').select('network_id, status'),
    supabase.from('sales').select('network_id, price'),
  ]);
  final pkgs = results[0] as List;
  final cards = results[1] as List;
  final sales = results[2] as List;

  final Map<String, Map<String, num>> raw = {};
  Map<String, num> get(String id) => raw.putIfAbsent(id, () => {'pkgs': 0, 'avail': 0, 'sold': 0, 'value': 0});

  for (final p in pkgs) {
    get(p['network_id'] as String)['pkgs'] = (get(p['network_id'] as String)['pkgs'] ?? 0) + 1;
  }
  for (final c in cards) {
    final g = get(c['network_id'] as String);
    if (c['status'] == 'AVAILABLE') {
      g['avail'] = (g['avail'] ?? 0) + 1;
    } else {
      g['sold'] = (g['sold'] ?? 0) + 1;
    }
  }
  for (final s in sales) {
    final g = get(s['network_id'] as String);
    g['value'] = (g['value'] ?? 0) + ((s['price'] ?? 0) as num);
  }

  return raw.map((k, v) => MapEntry(
        k,
        NetworkCounts(
          packages: v['pkgs']!.toInt(),
          available: v['avail']!.toInt(),
          sold: v['sold']!.toInt(),
          value: v['value']!,
        ),
      ));
});

Future<void> saveNetwork({
  required NetworkModel form,
  required String? editingId,
  required bool isSuperadmin,
}) async {
  if (editingId != null) {
    await supabase.from('networks').update(form.toMap()).eq('id', editingId);
    return;
  }
  if (isSuperadmin) {
    await supabase.rpc('superadmin_create_network', params: {
      '_name': form.name,
      '_currency': form.currency,
    });
    return;
  }
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');
  await supabase.from('networks').insert({
    ...form.toMap(),
    'owner_id': uid,
    'created_by': uid,
  });
}

Future<void> deleteNetwork(String id) async {
  await supabase.from('networks').delete().eq('id', id);
}
