// نفس منطق src/routes/app.manage-cards.tsx للأجزاء الأساسية (القائمة،
// الفلاتر، الحذف/الإرجاع الجماعي) — بدون أي تغيير على RPC:
// admin_list_cards, admin_unassign_cards, admin_delete_cards.
//
// ⚠️ مؤجَّل للاحقاً بنفس المرحلة (موثّق بـ MIGRATION_PLAN.md): نقل الكروت
// المباعة بين المناديب (transferSold)، وحذف الكروت المباعة القديمة تلقائياً
// (delOldSold) — عمليات متخصصة أقل استخداماً يومياً.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class CardRow {
  final String id;
  final String username;
  final String? password;
  final String status; // AVAILABLE / ASSIGNED / SOLD
  final String packageId;
  final String packageName;
  final String? assignedTo;
  final String? assignedFullName;
  final String? soldTo;
  final String? soldFullName;
  final String createdAt;
  final String? customerName;

  CardRow({
    required this.id,
    required this.username,
    this.password,
    required this.status,
    required this.packageId,
    required this.packageName,
    this.assignedTo,
    this.assignedFullName,
    this.soldTo,
    this.soldFullName,
    required this.createdAt,
    this.customerName,
  });

  factory CardRow.fromMap(Map<String, dynamic> m) => CardRow(
        id: m['id'] as String,
        username: m['username'] as String,
        password: m['password'] as String?,
        status: m['status'] as String,
        packageId: m['package_id'] as String,
        packageName: m['package_name'] as String? ?? '',
        assignedTo: m['assigned_to'] as String?,
        soldTo: m['sold_to'] as String?,
        createdAt: m['created_at'] as String? ?? '',
      );

  /// رقم نظامي ثابت (باركود) مشتق من المعرّف — مطابق لـ systemCode() الأصلية
  String get systemCode {
    final hex = id.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    final last12 = hex.length > 12 ? hex.substring(hex.length - 12) : hex.padLeft(12, '0');
    return last12;
  }
}

class ManageCardsFilters {
  final String? networkId;
  final String? packageId; // null = الكل
  final String? agentId; // null = الكل
  final String search;
  const ManageCardsFilters({this.networkId, this.packageId, this.agentId, this.search = ''});

  ManageCardsFilters copyWith({
    String? networkId,
    bool clearNetwork = false,
    String? packageId,
    bool clearPackage = false,
    String? agentId,
    bool clearAgent = false,
    String? search,
  }) =>
      ManageCardsFilters(
        networkId: clearNetwork ? null : (networkId ?? this.networkId),
        packageId: clearPackage ? null : (packageId ?? this.packageId),
        agentId: clearAgent ? null : (agentId ?? this.agentId),
        search: search ?? this.search,
      );
}

final manageCardsFiltersProvider = StateProvider<ManageCardsFilters>((ref) => const ManageCardsFilters());

final manageCardsPackagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final rows = await supabase.from('packages').select('id, name, price').eq('network_id', networkId).order('name');
  return (rows as List).cast<Map<String, dynamic>>();
});

final manageCardsAgentsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  final roles = await supabase.from('user_roles').select('user_id').eq('role', 'agent');
  final agentIds = (roles as List).map((r) => r['user_id'] as String).toList();
  if (agentIds.isEmpty) return [];
  final rows = await supabase
      .from('profiles')
      .select('id, full_name, username, phone')
      .eq('network_id', networkId)
      .inFilter('id', agentIds)
      .order('full_name');
  return (rows as List).map((p) {
    final name = (p['full_name'] as String?) ??
        (p['phone'] as String?) ??
        (p['username'] as String?) ??
        (p['id'] as String).substring(0, 8);
    return {'id': p['id'], 'name': name};
  }).toList();
});

/// نفس منطق جلب الكروت مع إثراء الأسماء (assigned/sold/customer) بالنسخة
/// الأصلية بالضبط.
final manageCardsListProvider = FutureProvider<List<CardRow>>((ref) async {
  final f = ref.watch(manageCardsFiltersProvider);
  if (f.networkId == null) return [];

  final data = await supabase.rpc('admin_list_cards', params: {
    '_network_id': f.networkId,
    if (f.packageId != null) '_package_id': f.packageId,
    if (f.agentId != null) '_agent_id': f.agentId,
    if (f.search.isNotEmpty) '_search': f.search,
  });
  final rows = (data as List).map((r) => CardRow.fromMap(r as Map<String, dynamic>)).toList();

  // إثراء أسماء المُسحوب لهم/المُباع لهم
  final ids = {
    ...rows.map((r) => r.assignedTo).whereType<String>(),
    ...rows.map((r) => r.soldTo).whereType<String>(),
  }.toList();
  Map<String, String> nameMap = {};
  if (ids.isNotEmpty) {
    final profs = await supabase.from('profiles').select('id, full_name, username, phone').inFilter('id', ids);
    for (final p in (profs as List)) {
      nameMap[p['id'] as String] =
          (p['full_name'] as String?) ?? (p['phone'] as String?) ?? (p['username'] as String?) ?? '';
    }
  }

  // اسم الزبون من سجل المبيعات
  final cardIds = rows.map((r) => r.id).toList();
  Map<String, String> custMap = {};
  if (cardIds.isNotEmpty) {
    final salesRows = await supabase.from('sales').select('card_id, buyer_name, customers(name)').inFilter('card_id', cardIds);
    for (final s in (salesRows as List)) {
      final customer = s['customers'] as Map<String, dynamic>?;
      final name = (customer?['name'] as String?) ?? (s['buyer_name'] as String?);
      if (s['card_id'] != null && name != null) custMap[s['card_id'] as String] = name;
    }
  }

  return rows
      .map((r) => CardRow(
            id: r.id,
            username: r.username,
            password: r.password,
            status: r.status,
            packageId: r.packageId,
            packageName: r.packageName,
            assignedTo: r.assignedTo,
            assignedFullName: r.assignedTo != null ? nameMap[r.assignedTo] : null,
            soldTo: r.soldTo,
            soldFullName: r.soldTo != null ? nameMap[r.soldTo] : null,
            createdAt: r.createdAt,
            customerName: custMap[r.id],
          ))
      .toList();
});

class BulkDeleteResult {
  final int deleted;
  final int unassigned;
  const BulkDeleteResult({required this.deleted, required this.unassigned});
}

/// نفس المنطق الذكي بالنسخة الأصلية: الكروت "مسحوبة" تُرجَع للمتاح
/// (admin_unassign_cards)، والباقي يُحذف (admin_delete_cards) مع _force
/// تلقائي لو فيها كروت مباعة أو extendedDelete مفعّل.
Future<BulkDeleteResult> bulkDeleteOrUnassign({
  required List<CardRow> allCards,
  required Set<String> selectedIds,
  required bool extendedDelete,
}) async {
  if (selectedIds.isEmpty) return const BulkDeleteResult(deleted: 0, unassigned: 0);
  final statusMap = {for (final c in allCards) c.id: c.status};
  final assignedIds = selectedIds.where((id) => statusMap[id] == 'ASSIGNED').toList();
  final otherIds = selectedIds.where((id) => statusMap[id] != 'ASSIGNED').toList();

  int unassigned = 0;
  if (assignedIds.isNotEmpty) {
    final data = await supabase.rpc('admin_unassign_cards', params: {'_ids': assignedIds});
    unassigned = (data as num?)?.toInt() ?? 0;
  }

  int deleted = 0;
  if (otherIds.isNotEmpty) {
    final soldRefs = await supabase.from('sales').select('card_id').inFilter('card_id', otherIds);
    final refSet = (soldRefs as List).map((r) => r['card_id'] as String).toSet();
    final hasSoldCards = otherIds.any((id) => refSet.contains(id) || statusMap[id] == 'SOLD');
    final forceDelete = extendedDelete || hasSoldCards;
    final data = await supabase.rpc('admin_delete_cards', params: {'_ids': otherIds, '_force': forceDelete});
    final row = (data is List) ? data.first as Map<String, dynamic>? : data as Map<String, dynamic>?;
    deleted = (row?['deleted'] as num?)?.toInt() ?? 0;
  }
  return BulkDeleteResult(deleted: deleted, unassigned: unassigned);
}

/// نقل كروت مباعة لمندوب آخر — نفس RPC admin_transfer_sold_cards بالضبط.
class TransferResult {
  final int moved;
  final num amount;
  const TransferResult({required this.moved, required this.amount});
}

Future<TransferResult> transferSoldCards({
  required List<String> cardIds,
  required String toAgentId,
}) async {
  final data = await supabase.rpc('admin_transfer_sold_cards', params: {
    '_ids': cardIds,
    '_to_agent': toAgentId,
  });
  final row = (data is List) ? data.first as Map<String, dynamic>? : data as Map<String, dynamic>?;
  return TransferResult(moved: (row?['moved'] as num?)?.toInt() ?? 0, amount: (row?['amount'] ?? 0) as num);
}

/// حذف الكروت المباعة/المسحوبة الأقدم من 30 يوم — نفس منطق النسخة الأصلية.
Future<int> deleteOldSoldCards(List<CardRow> allCards) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final ids = allCards
      .where((c) =>
          (c.status == 'SOLD' || c.status == 'ASSIGNED') &&
          DateTime.tryParse(c.createdAt)?.isBefore(cutoff) == true)
      .map((c) => c.id)
      .toList();
  if (ids.isEmpty) return 0;
  final data = await supabase.rpc('admin_delete_cards', params: {'_ids': ids, '_force': true});
  final row = (data is List) ? data.first as Map<String, dynamic>? : data as Map<String, dynamic>?;
  return (row?['deleted'] as num?)?.toInt() ?? 0;
}

/// حذف/إرجاع كرت واحد — نفس منطق delOne بالنسخة الأصلية.
Future<bool> deleteOrUnassignOne(CardRow card, {required bool extendedDelete}) async {
  if (card.status == 'ASSIGNED') {
    await supabase.rpc('admin_unassign_cards', params: {'_ids': [card.id]});
    return true; // unassigned
  }
  final refs = await supabase.from('sales').select('card_id').eq('card_id', card.id).limit(1);
  final isSold = card.status == 'SOLD';
  await supabase.rpc('admin_delete_cards', params: {
    '_ids': [card.id],
    '_force': extendedDelete || (refs as List).isNotEmpty || isSold,
  });
  return false; // deleted
}
