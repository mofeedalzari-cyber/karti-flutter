// نفس منطق src/routes/app.sales.tsx بالكامل — جدول sales، وRPC:
// sold_card_credentials (كلمات مرور الكروت المباعة، آمنة للمصرّح لهم فقط)،
// delete_sale.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import '../auth/profile_provider.dart';

class SaleRow {
  final String id;
  final String transactionNo;
  final String packageName;
  final String networkName;
  final String agentUsername;
  final String? agentId;
  final num price;
  final String soldAt;
  final String? buyerName;
  final String? customerId;
  final String? customerName;
  final String? cardId;
  final String? cardUsername;
  final String? cardPassword;
  final bool isExternal;

  SaleRow({
    required this.id,
    required this.transactionNo,
    required this.packageName,
    required this.networkName,
    required this.agentUsername,
    this.agentId,
    required this.price,
    required this.soldAt,
    this.buyerName,
    this.customerId,
    this.customerName,
    this.cardId,
    this.cardUsername,
    this.cardPassword,
    this.isExternal = false,
  });

  factory SaleRow.fromMap(Map<String, dynamic> m) {
    final customer = m['customers'] as Map<String, dynamic>?;
    return SaleRow(
      id: m['id'] as String,
      transactionNo: m['transaction_no'] as String? ?? '',
      packageName: m['package_name'] as String? ?? '',
      networkName: m['network_name'] as String? ?? '',
      agentUsername: m['agent_username'] as String? ?? '',
      agentId: m['agent_id'] as String?,
      price: (m['price'] ?? 0) as num,
      soldAt: m['sold_at'] as String? ?? '',
      buyerName: m['buyer_name'] as String?,
      customerId: m['customer_id'] as String?,
      customerName: customer?['name'] as String?,
      cardId: m['card_id'] as String?,
      cardUsername: m['card_number'] as String?,
      isExternal: (m['is_external'] as bool?) ?? false,
    );
  }

  String get agentKey => agentId ?? agentUsername;
}

class SalesDateFilter {
  final String? from; // yyyy-MM-dd
  final String? to;
  const SalesDateFilter({this.from, this.to});
}

final salesDateFilterProvider = StateProvider<SalesDateFilter>((ref) => const SalesDateFilter());

/// يجلب المبيعات ويثري كل صف بكلمة مرور الكرت عبر دالة آمنة — نفس منطق
/// النسخة الأصلية بالضبط.
final salesListProvider = FutureProvider<List<SaleRow>>((ref) async {
  final filter = ref.watch(salesDateFilterProvider);
  var query = supabase
      .from('sales')
      .select(
          'id, transaction_no, package_name, network_name, agent_username, agent_id, price, sold_at, buyer_name, customer_id, card_id, card_number, is_external, customers(name)')
      .order('sold_at', ascending: false)
      .limit((filter.from != null || filter.to != null) ? 5000 : 500);
  if (filter.from != null) query = query.gte('sold_at', '${filter.from}T00:00:00');
  if (filter.to != null) query = query.lte('sold_at', '${filter.to}T23:59:59.999');
  final rows = await query;

  final list = (rows as List).map((r) => SaleRow.fromMap(r as Map<String, dynamic>)).toList();
  final cardIds = list.map((s) => s.cardId).whereType<String>().toList();
  if (cardIds.isEmpty) return list;

  final creds = await supabase.rpc('sold_card_credentials', params: {'_card_ids': cardIds});
  final credMap = {for (final c in (creds as List)) c['id'] as String: c['password'] as String?};

  return list
      .map((s) => SaleRow(
            id: s.id,
            transactionNo: s.transactionNo,
            packageName: s.packageName,
            networkName: s.networkName,
            agentUsername: s.agentUsername,
            agentId: s.agentId,
            price: s.price,
            soldAt: s.soldAt,
            buyerName: s.buyerName,
            customerId: s.customerId,
            customerName: s.customerName,
            cardId: s.cardId,
            cardUsername: s.cardUsername,
            cardPassword: s.cardId != null ? credMap[s.cardId] : null,
            isExternal: s.isExternal,
          ))
      .toList();
});

Future<void> updateSale(String id, {required String? buyerName, num? price}) async {
  final payload = <String, dynamic>{'buyer_name': (buyerName?.trim().isEmpty ?? true) ? null : buyerName!.trim()};
  if (price != null) payload['price'] = price;
  await supabase.from('sales').update(payload).eq('id', id);
}

/// حذف مجموعة مبيعات — يحاول كل واحدة على حدة (نفس منطق bulkDelete بالنسخة
/// الأصلية)، يرجع عدد النجاح والفشل.
Future<({int ok, int fail})> bulkDeleteSales(List<String> ids, {required bool deleteCards}) async {
  int ok = 0, fail = 0;
  for (final id in ids) {
    try {
      await supabase.rpc('delete_sale', params: {'_sale_id': id, '_delete_card': deleteCards});
      ok++;
    } catch (_) {
      fail++;
    }
  }
  return (ok: ok, fail: fail);
}

bool canModifySale(SaleRow s, Profile? profile) {
  if (profile == null) return false;
  return profile.isAdminOrAbove || s.agentId == profile.id;
}
