// نفس استعلامات src/routes/app.packages.tsx بالضبط — بدون أي تغيير على
// قاعدة البيانات: جداول networks/packages، ودوال RPC: package_counts,
// admin_network, superadmin_create_package, request_cards.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import 'package_model.dart';

final networksProvider = FutureProvider<List<NetworkLite>>((ref) async {
  final rows = await supabase.from('networks').select('id, name, currency').order('name');
  return (rows as List).map((r) => NetworkLite.fromMap(r)).toList();
});

/// فلتر الشبكة المختار حالياً (null = كل الشبكات)
final packageNetworkFilterProvider = StateProvider<String?>((ref) => null);

final packagesProvider = FutureProvider<List<PackageModel>>((ref) async {
  final filterNet = ref.watch(packageNetworkFilterProvider);
  var query = supabase
      .from('packages')
      .select(
          'id, network_id, name, price, data_size, speed, validity, allowed_time, description, color, sort_order, is_active');
  final rows = filterNet == null
      ? await query.order('price', ascending: false)
      : await query.eq('network_id', filterNet).order('price', ascending: false);
  return (rows as List).map((r) => PackageModel.fromMap(r)).toList();
});

/// عدد المتاح/المخصّص/المباع لكل باقة — عبر RPC package_counts لكل شبكة
/// (نفس منطق النسخة الأصلية بالضبط، بدون تنزيل آلاف صفوف الكروت للجهاز).
final packageCountsProvider = FutureProvider<Map<String, PackageCounts>>((ref) async {
  final networks = await ref.watch(networksProvider.future);
  final Map<String, PackageCounts> result = {};
  for (final n in networks) {
    final rows = await supabase.rpc('package_counts', params: {'_network_id': n.id});
    for (final row in (rows as List? ?? [])) {
      result[row['package_id'] as String] = PackageCounts(
        available: (row['available'] ?? 0) as int,
        assigned: (row['assigned'] ?? 0) as int,
        sold: (row['sold'] ?? 0) as int,
      );
    }
  }
  return result;
});

/// حفظ باقة (إضافة/تعديل) — يتعامل مع فرع السوبر أدمن (RPC خاص) تماماً مثل
/// النسخة الأصلية.
Future<void> savePackage({
  required PackageModel form,
  required String? editingId,
  required bool isSuperadmin,
}) async {
  if (editingId != null) {
    await supabase.from('packages').update(form.toInsertMap()).eq('id', editingId);
    return;
  }

  if (isSuperadmin) {
    final uid = supabase.auth.currentUser?.id;
    final mine = uid != null
        ? await supabase.rpc('admin_network', params: {'_uid': uid})
        : null;
    if (mine != null && form.networkId == mine) {
      await supabase.from('packages').insert(form.toInsertMap());
    } else {
      await supabase.rpc('superadmin_create_package', params: {
        '_network_id': form.networkId,
        '_name': form.name,
        '_price': form.price,
        if (form.dataSize != null) '_data_size': form.dataSize,
        if (form.speed != null) '_speed': form.speed,
        if (form.validity != null) '_validity': form.validity,
        if (form.allowedTime != null) '_allowed_time': form.allowedTime,
        if (form.color != null) '_color': form.color,
      });
    }
    return;
  }

  await supabase.from('packages').insert(form.toInsertMap());
}

/// نتيجة محاولة الحذف — تفرّق بين نجاح، وفشل بسبب ارتباط بمبيعات سابقة
/// (Foreign Key)، وأي خطأ آخر — تماماً مثل النسخة الأصلية.
enum DeleteOutcome { success, blockedByForeignKey, otherError }

class DeletePackageResult {
  final DeleteOutcome outcome;
  final String? errorMessage;
  const DeletePackageResult(this.outcome, [this.errorMessage]);
}

Future<DeletePackageResult> deletePackage(String id) async {
  try {
    await supabase.from('packages').delete().eq('id', id);
    return const DeletePackageResult(DeleteOutcome.success);
  } on PostgrestException catch (e) {
    final isFk = e.code == '23503' ||
        RegExp('foreign key|violates', caseSensitive: false).hasMatch(e.message);
    if (isFk) return const DeletePackageResult(DeleteOutcome.blockedByForeignKey);
    return DeletePackageResult(DeleteOutcome.otherError, e.message);
  }
}

Future<void> disablePackage(String id) async {
  await supabase.from('packages').update({'is_active': false}).eq('id', id);
}

/// بيع كرت مباشر (كبينة البيع) — نفس RPC sell_card بالضبط، يسحب كرت متاح
/// عشوائياً ويبيعه فوراً للمندوب الحالي دون انتظار موافقة إدارية.
const _sellErrorMessages = {
  'NO_CARDS_AVAILABLE': 'لا توجد كروت متوفرة لهذه الباقة',
  'ACCOUNT_INACTIVE': 'حسابك غير مفعّل',
  'FORBIDDEN': 'غير مصرح',
  'PACKAGE_NOT_FOUND': 'الباقة غير موجودة',
  'NETWORK_INACTIVE': 'الشبكة موقوفة',
};

class SaleResult {
  final String cardUsername;
  final String? cardPassword;
  final num price;
  final String transactionNo;
  final String packageName;
  const SaleResult({
    required this.cardUsername,
    this.cardPassword,
    required this.price,
    required this.transactionNo,
    required this.packageName,
  });

  factory SaleResult.fromMap(Map<String, dynamic> m) => SaleResult(
        cardUsername: m['card_username'] as String,
        cardPassword: m['card_password'] as String?,
        price: (m['price'] ?? 0) as num,
        transactionNo: m['transaction_no'] as String? ?? '',
        packageName: m['package_name'] as String? ?? '',
      );

  /// نفس نص المشاركة بالضبط من النسخة الأصلية (SaleCard.fullText)
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

/// يرجع SaleResult عند النجاح، أو يرمي استثناء برسالة مترجمة عند الفشل.
Future<SaleResult> sellCard(String packageId) async {
  try {
    final data = await supabase.rpc('sell_card', params: {'_package_id': packageId});
    final row = (data is List) ? data.first as Map<String, dynamic> : data as Map<String, dynamic>;
    return SaleResult.fromMap(row);
  } on PostgrestException catch (e) {
    final key = _sellErrorMessages.keys.firstWhere((k) => e.message.contains(k), orElse: () => '');
    throw Exception(_sellErrorMessages[key] ?? e.message);
  }
}
/// نتيجة طلب سحب الكروت (نفس رسائل الخطأ بالنسخة الأصلية)
const _requestErrorMessages = {
  'FORBIDDEN': 'غير مصرح',
  'ACCOUNT_INACTIVE': 'حسابك غير مفعّل',
  'PACKAGE_NOT_FOUND': 'الباقة غير موجودة',
  'PACKAGE_NOT_IN_YOUR_NETWORK': 'هذه الباقة ليست ضمن شبكتك',
  'AGENT_NETWORK_NOT_SET': 'لم يتم تعيين شبكتك بعد',
  'INVALID_QUANTITY': 'كمية غير صحيحة',
};

/// يرجع null عند النجاح، أو رسالة الخطأ المترجمة عند الفشل.
Future<String?> requestCards({
  required String packageId,
  required int quantity,
  required String notes,
  required String paymentMethod, // "CREDIT" أو "CASH"
}) async {
  try {
    await supabase.rpc('request_cards', params: {
      '_package_id': packageId,
      '_quantity': quantity,
      '_notes': notes,
      '_payment_method': paymentMethod,
    });
    return null;
  } on PostgrestException catch (e) {
    return _requestErrorMessages[e.message] ?? e.message;
  }
}
