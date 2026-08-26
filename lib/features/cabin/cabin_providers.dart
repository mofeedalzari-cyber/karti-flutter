// نفس منطق src/routes/app.cabin.tsx بالكامل — RPC: agent_cabin, sell_card,
// delete_customer. كبينة البيع الخاصة بالمندوب: كروته المسحوبة الجاهزة
// للبيع، مع اختيار زبون إلزامي قبل كل عملية بيع.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class CabinRow {
  final String packageId;
  final String packageName;
  final String networkId;
  final String networkName;
  final num price;
  final String? color;
  final String? dataSize;
  final String? speed;
  final String? validity;
  final String currency;
  final int available;
  final int soldCount;

  CabinRow({
    required this.packageId,
    required this.packageName,
    required this.networkId,
    required this.networkName,
    required this.price,
    this.color,
    this.dataSize,
    this.speed,
    this.validity,
    required this.currency,
    required this.available,
    required this.soldCount,
  });

  factory CabinRow.fromMap(Map<String, dynamic> m) => CabinRow(
        packageId: m['package_id'] as String,
        packageName: m['package_name'] as String? ?? '',
        networkId: m['network_id'] as String? ?? '',
        networkName: m['network_name'] as String? ?? '',
        price: (m['price'] ?? 0) as num,
        color: m['color'] as String?,
        dataSize: m['data_size'] as String?,
        speed: m['speed'] as String?,
        validity: m['validity'] as String?,
        currency: m['currency'] as String? ?? '',
        available: (m['available'] ?? 0) as int,
        soldCount: (m['sold_count'] ?? 0) as int,
      );
}

class CabinCustomer {
  final String id;
  final String name;
  final String whatsapp;
  final String? networkId;
  const CabinCustomer({required this.id, required this.name, required this.whatsapp, this.networkId});

  factory CabinCustomer.fromMap(Map<String, dynamic> m) => CabinCustomer(
        id: m['id'] as String,
        name: m['name'] as String,
        whatsapp: m['whatsapp'] as String? ?? '',
        networkId: m['network_id'] as String?,
      );
}

final cabinRowsProvider = FutureProvider<List<CabinRow>>((ref) async {
  final data = await supabase.rpc('agent_cabin');
  return (data as List).map((r) => CabinRow.fromMap(r as Map<String, dynamic>)).toList();
});

final myCustomersProvider = FutureProvider<List<CabinCustomer>>((ref) async {
  final rows = await supabase.from('customers').select('id, name, whatsapp, network_id').order('created_at', ascending: false);
  return (rows as List).map((r) => CabinCustomer.fromMap(r as Map<String, dynamic>)).toList();
});

/// نفس دالة normalizeWa بالنسخة الأصلية: تنظيف رقم واتساب لأرقام فقط.
String normalizeWa(String v) => v.replaceAll(RegExp(r'\D'), '');

/// null = فشل (مع رسالة خطأ)، غير ذلك = الزبون المُنشأ
Future<CabinCustomer?> createCustomer({
  required String name,
  required String whatsapp,
  String? networkId,
}) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) throw Exception('أدخل اسم الزبون');
  final wa = normalizeWa(whatsapp);
  if (wa.length < 7) throw Exception('رقم واتساب غير صحيح');

  final data = await supabase
      .from('customers')
      .insert({'agent_id': uid, 'network_id': networkId, 'name': trimmedName, 'whatsapp': wa})
      .select('id, name, whatsapp, network_id')
      .single();
  return CabinCustomer.fromMap(data);
}

Future<void> deleteCustomer(String id) async {
  await supabase.rpc('delete_customer', params: {'_customer_id': id});
}

const _sellErrorMessages = {
  'NO_CARDS_AVAILABLE': 'لا توجد كروت في كبينتك لهذه الباقة',
  'ACCOUNT_INACTIVE': 'حسابك غير مفعّل',
  'FORBIDDEN': 'غير مصرح',
  'PACKAGE_NOT_FOUND': 'الباقة غير موجودة',
  'NETWORK_INACTIVE': 'الشبكة موقوفة',
};

class CabinSaleResult {
  final String? saleId;
  final String cardUsername;
  final String? cardPassword;
  final num price;
  final String transactionNo;
  final String packageName;
  String? customerName;

  CabinSaleResult({
    this.saleId,
    required this.cardUsername,
    this.cardPassword,
    required this.price,
    required this.transactionNo,
    required this.packageName,
    this.customerName,
  });

  factory CabinSaleResult.fromMap(Map<String, dynamic> m) => CabinSaleResult(
        saleId: m['sale_id'] as String?,
        cardUsername: m['card_username'] as String? ?? '',
        cardPassword: m['card_password'] as String?,
        price: (m['price'] ?? 0) as num,
        transactionNo: m['transaction_no'] as String? ?? '',
        packageName: m['package_name'] as String? ?? '',
      );

  String shareText(String networkName) {
    final buf = StringBuffer()
      ..writeln('الشبكة: $networkName')
      ..writeln('الباقة: $packageName')
      ..writeln('المستخدم: $cardUsername');
    if (cardPassword != null) buf.writeln('كلمة المرور: $cardPassword');
    buf.writeln('السعر: $price');
    buf.write('رقم العملية: $transactionNo');
    return buf.toString();
  }
}

/// بيع من الكابينة — يتطلب زبون إلزامياً (خلافاً لبيع الباقات العام)، ويربط
/// عملية البيع بالزبون مباشرة بعد نجاحها.
Future<CabinSaleResult> sellFromCabin({
  required String packageId,
  required CabinCustomer customer,
}) async {
  Map<String, dynamic> row;
  try {
    final data = await supabase.rpc('sell_card', params: {'_package_id': packageId});
    row = (data is List) ? data.first as Map<String, dynamic> : data as Map<String, dynamic>;
  } on PostgrestException catch (e) {
    final key = _sellErrorMessages.keys.firstWhere((k) => e.message.contains(k), orElse: () => '');
    throw Exception(_sellErrorMessages[key] ?? e.message);
  }
  final result = CabinSaleResult.fromMap(row);
  if (result.saleId != null) {
    await supabase.from('sales').update({'customer_id': customer.id, 'buyer_name': customer.name}).eq('id', result.saleId!);
    result.customerName = customer.name;
  }
  return result;
}
