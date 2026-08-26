// نفس منطق src/routes/app.customers.tsx بالكامل — جداول customers, sales,
// customer_payments، وRPCs: network_customers, admin_settle_customer_via_agent,
// delete_customer, sold_card_credentials.
//
// الحساب المالي للزبون: الرصيد = (إجمالي المبيعات + الشحن اليدوي) - المدفوع.
// "الشحن اليدوي" يُسجَّل كصف customer_payments بمبلغ سالب (نفس الحيلة
// المستخدمة بالنسخة الأصلية بالضبط) — لا يُنشئ عملية بيع حقيقية.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class MyCustomer {
  final String id;
  final String name;
  final String whatsapp;
  final String createdAt;
  MyCustomer({required this.id, required this.name, required this.whatsapp, required this.createdAt});

  factory MyCustomer.fromMap(Map<String, dynamic> m) => MyCustomer(
        id: m['id'] as String,
        name: m['name'] as String,
        whatsapp: m['whatsapp'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
      );
}

class CustomerSale {
  final String id;
  final String transactionNo;
  final String packageName;
  final String networkName;
  final num price;
  final String soldAt;
  final String? customerId;
  final String? cardUsername;
  final String? cardPassword;

  CustomerSale({
    required this.id,
    required this.transactionNo,
    required this.packageName,
    required this.networkName,
    required this.price,
    required this.soldAt,
    this.customerId,
    this.cardUsername,
    this.cardPassword,
  });
}

class CustomerPayment {
  final String id;
  final String customerId;
  final num amount; // موجب = دفعة، سالب = شحن يدوي
  final String? note;
  final String createdAt;
  CustomerPayment({required this.id, required this.customerId, required this.amount, this.note, required this.createdAt});

  factory CustomerPayment.fromMap(Map<String, dynamic> m) => CustomerPayment(
        id: m['id'] as String,
        customerId: m['customer_id'] as String,
        amount: (m['amount'] ?? 0) as num,
        note: m['note'] as String?,
        createdAt: m['created_at'] as String? ?? '',
      );
}

final customerSearchProvider = StateProvider<String>((ref) => '');

final myCustomersListProvider = FutureProvider<List<MyCustomer>>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = await supabase.from('customers').select('id, name, whatsapp, created_at').eq('agent_id', uid).order('created_at', ascending: false);
  return (rows as List).map((r) => MyCustomer.fromMap(r as Map<String, dynamic>)).toList();
});

final myCustomerSalesProvider = FutureProvider<List<CustomerSale>>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = await supabase
      .from('sales')
      .select('id, transaction_no, package_name, network_name, price, sold_at, customer_id, buyer_name, card_id, card_number, is_external, cards(username)')
      .eq('agent_id', uid)
      .order('sold_at', ascending: false);
  final list = (rows as List).cast<Map<String, dynamic>>();
  final cardIds = list.map((r) => r['card_id'] as String?).whereType<String>().toList();
  Map<String, String?> credMap = {};
  if (cardIds.isNotEmpty) {
    final creds = await supabase.rpc('sold_card_credentials', params: {'_card_ids': cardIds});
    credMap = {for (final c in (creds as List)) c['id'] as String: c['password'] as String?};
  }
  return list.map((s) {
    final cards = s['cards'] as Map<String, dynamic>?;
    return CustomerSale(
      id: s['id'] as String,
      transactionNo: s['transaction_no'] as String? ?? '',
      packageName: s['package_name'] as String? ?? '',
      networkName: s['network_name'] as String? ?? '',
      price: (s['price'] ?? 0) as num,
      soldAt: s['sold_at'] as String? ?? '',
      customerId: s['customer_id'] as String?,
      cardUsername: (cards?['username'] as String?) ?? s['card_number'] as String?,
      cardPassword: s['card_id'] != null ? credMap[s['card_id']] : null,
    );
  }).toList();
});

final myCustomerPaymentsProvider = FutureProvider<List<CustomerPayment>>((ref) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = await supabase.from('customer_payments').select('id, customer_id, amount, note, created_at').eq('agent_id', uid).order('created_at', ascending: false);
  return (rows as List).map((r) => CustomerPayment.fromMap(r as Map<String, dynamic>)).toList();
});

final myActivePackagesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await supabase.from('packages').select('id, name, price').eq('is_active', true).order('sort_order');
  return (rows as List).cast<Map<String, dynamic>>();
});

class CustomerBalance {
  final num salesTotal;
  final num charges;
  final num paid;
  num get total => salesTotal + charges;
  num get balance => (total - paid).clamp(0, double.infinity);
  const CustomerBalance({required this.salesTotal, required this.charges, required this.paid});
}

CustomerBalance computeBalance(String customerId, List<CustomerSale> sales, List<CustomerPayment> payments) {
  final salesTotal = sales.where((s) => s.customerId == customerId).fold<num>(0, (a, s) => a + s.price);
  final customerPayments = payments.where((p) => p.customerId == customerId);
  final charges = customerPayments.where((p) => p.amount < 0).fold<num>(0, (a, p) => a + p.amount.abs());
  final paid = customerPayments.where((p) => p.amount > 0).fold<num>(0, (a, p) => a + p.amount);
  return CustomerBalance(salesTotal: salesTotal, charges: charges, paid: paid);
}

Future<void> recordCustomerPayment({required String customerId, required num amount, String? note}) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');
  final prof = await supabase.from('profiles').select('network_id').eq('id', uid).maybeSingle();
  await supabase.from('customer_payments').insert({
    'customer_id': customerId,
    'agent_id': uid,
    'network_id': prof?['network_id'],
    'amount': amount,
    'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
  });
}

/// شحن يدوي (دين على الزبون بدون بيع كرت فعلي) — نفس الحيلة بالضبط
/// (customer_payments بمبلغ سالب).
Future<void> addManualCharge({
  required String customerId,
  required num amount,
  String? packageName,
  int quantity = 1,
  String? cardNo,
  String? note,
}) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');
  final prof = await supabase.from('profiles').select('network_id').eq('id', uid).maybeSingle();
  final parts = <String>['مبلغ مضاف'];
  if (packageName != null) parts.add(quantity > 1 ? '$packageName × $quantity' : packageName);
  if (cardNo != null && cardNo.trim().isNotEmpty) parts.add('رقم الكرت: ${cardNo.trim()}');
  if (note != null && note.trim().isNotEmpty) parts.add(note.trim());
  await supabase.from('customer_payments').insert({
    'customer_id': customerId,
    'agent_id': uid,
    'network_id': prof?['network_id'],
    'amount': -amount.abs(),
    'note': parts.join(' — '),
  });
}

Future<void> deleteCustomerPayment(String id) async {
  await supabase.from('customer_payments').delete().eq('id', id);
}

Future<void> deleteMyCustomer(String id) async {
  await supabase.rpc('delete_customer', params: {'_customer_id': id});
}

/// إنشاء زبون جديد للمندوب الحالي (نفس منطق createCustomer بالكابينة).
Future<void> createMyCustomer({required String name, required String whatsapp, String? networkId}) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) throw Exception('أدخل اسم الزبون');
  final wa = whatsapp.replaceAll(RegExp(r'\D'), '');
  if (wa.length < 7) throw Exception('رقم واتساب غير صحيح');
  await supabase.from('customers').insert({'agent_id': uid, 'network_id': networkId, 'name': trimmedName, 'whatsapp': wa});
}

// ============================================================
// عرض المدير: زبائن الشبكة كاملة (network_customers RPC)
// ============================================================

class NetCustomer {
  final String id;
  final String name;
  final String whatsapp;
  final String? agentId;
  final String? agentUsername;
  final num balance;
  final num salesTotal;
  final num charges;
  final num paid;

  NetCustomer({
    required this.id,
    required this.name,
    required this.whatsapp,
    this.agentId,
    this.agentUsername,
    required this.balance,
    required this.salesTotal,
    required this.charges,
    required this.paid,
  });

  factory NetCustomer.fromMap(Map<String, dynamic> m) => NetCustomer(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        whatsapp: m['whatsapp'] as String? ?? '',
        agentId: m['agent_id'] as String?,
        agentUsername: m['agent_username'] as String?,
        balance: (m['balance'] ?? 0) as num,
        salesTotal: (m['sales_total'] ?? 0) as num,
        charges: (m['charges'] ?? 0) as num,
        paid: (m['paid'] ?? 0) as num,
      );
}

final networkCustomersProvider = FutureProvider<List<NetCustomer>>((ref) async {
  final data = await supabase.rpc('network_customers');
  return (data as List).map((r) => NetCustomer.fromMap(r as Map<String, dynamic>)).toList();
});

final netAgentFilterProvider = StateProvider<String?>((ref) => null); // null = الكل

Future<num> settleCustomerViaAgent({required String customerId, required num amount, String? note}) async {
  final data = await supabase.rpc('admin_settle_customer_via_agent', params: {
    '_customer_id': customerId,
    '_amount': amount,
    '_note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
  });
  final row = (data is List) ? data.first as Map<String, dynamic>? : data as Map<String, dynamic>?;
  return (row?['remaining'] ?? 0) as num;
}
