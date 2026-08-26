// نفس منطق network-backup.functions.ts + network-restore.functions.ts +
// admin-wipe.functions.ts بالكامل — لكن بدون createServerFn إطلاقاً، لأن
// كل العمليات فعلياً استعلامات Supabase عادية بصلاحيات المستخدم نفسه (RLS)،
// أو RPC آمنة (SECURITY DEFINER) بدون أي مفتاح SERVICE_ROLE سري. يعني تشتغل
// من الجوال مباشرة بدون أي سيرفر وسيط — لا Render ولا Edge Functions.
import 'dart:convert';
import 'dart:math';
import '../../services/supabase_service.dart';

const _uuidChars = '0123456789abcdef';
String _genId() {
  final r = Random();
  String hex(int n) => List.generate(n, (_) => _uuidChars[r.nextInt(16)]).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}

String _cleanPhone(dynamic v) => (v?.toString() ?? '').replaceAll(RegExp(r'\D'), '');

// ============================================================
// نسخ احتياطي لشبكة المدير الحالي (backupMyNetwork)
// ============================================================

Future<Map<String, dynamic>> backupMyNetwork() async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');

  final network = await supabase.from('networks').select('*').eq('owner_id', uid).maybeSingle();
  if (network == null) throw Exception('لا توجد شبكة مرتبطة بحسابك');
  final networkId = network['id'] as String;

  final result = <String, dynamic>{'exported_at': DateTime.now().toIso8601String(), 'network': network};

  const simpleTables = ['profiles', 'join_requests', 'card_requests', 'mikrotiks'];
  for (final t in simpleTables) {
    final rows = await supabase.from(t).select('*').eq('network_id', networkId);
    result[t] = rows;
  }

  // الكروت: عبر RPC admin_list_cards (نفس عمود password المحمي من SELECT المباشر)
  final cardsData = await supabase.rpc('admin_list_cards', params: {'_network_id': networkId, '_limit': 1000000});
  result['cards'] = (cardsData as List)
      .map((c) => {
            'id': c['id'],
            'package_id': c['package_id'],
            'network_id': networkId,
            'username': c['username'],
            'password': c['password'],
            'status': c['status'],
            'sold_to': c['sold_to'],
            'assigned_to': c['assigned_to'],
            'created_at': c['created_at'],
          })
      .toList();

  final pkgRows = await supabase.from('packages').select('*').eq('network_id', networkId);
  result['packages'] = pkgRows;

  final salesRows = await supabase.from('sales').select('*').eq('network_id', networkId);
  result['sales'] = salesRows;

  final custRows = await supabase.from('customers').select('*').eq('network_id', networkId);
  result['customers'] = custRows;

  // request_payments: لا عمود network_id، عبر معرّفات الطلبات
  final reqIds = ((result['card_requests'] as List?) ?? []).map((r) => r['id'] as String).toList();
  result['request_payments'] = reqIds.isEmpty ? [] : await supabase.from('request_payments').select('*').inFilter('request_id', reqIds);

  // customer_payments: عبر معرّفات الزبائن
  final custIds = ((result['customers'] as List?) ?? []).map((c) => c['id'] as String).toList();
  result['customer_payments'] = custIds.isEmpty ? [] : await supabase.from('customer_payments').select('*').inFilter('customer_id', custIds);

  result['logs'] = [];

  return result;
}

/// يحوّل نتيجة النسخ الاحتياطي لنص JSON منسّق، جاهز للحفظ/المشاركة كملف.
String backupToJsonString(Map<String, dynamic> backup) => const JsonEncoder.withIndent('  ').convert(backup);

// ============================================================
// استعادة نسخة احتياطية لشبكة المدير الحالي (restoreMyNetwork)
// ============================================================

class RestoreResult {
  final String networkId;
  final Map<String, int> stats;
  const RestoreResult({required this.networkId, required this.stats});
}

Future<RestoreResult> restoreMyNetwork(Map<String, dynamic> payload) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');
  if (payload['network'] is! Map) throw Exception('الملف لا يحتوي بيانات شبكة');

  final index = await supabase.rpc('restore_profile_index');
  final netProfiles = ((index?['network_profiles'] as List?) ?? []).cast<Map<String, dynamic>>();
  final usedUsernames = <String>{...((index?['usernames'] as List?) ?? []).map((u) => u.toString())};

  final wiped = await supabase.rpc('restore_wipe_my_network');
  final networkId = wiped?['network_id']?.toString() ?? '';
  if (networkId.isEmpty) throw Exception('لا توجد شبكة مرتبطة بحسابك');

  final allowedUserIds = <String>{uid, ...netProfiles.map((p) => p['id'].toString())};
  final usernameToId = <String, String>{};
  final phoneToId = <String, String>{};
  final namePhoneToId = <String, String>{};
  for (final p in netProfiles) {
    if (p['username'] != null) usernameToId[p['username'].toString()] = p['id'].toString();
    final phoneKey = _cleanPhone(p['phone']);
    if (phoneKey.isNotEmpty) phoneToId[phoneKey] = p['id'].toString();
    if (p['full_name'] != null && phoneKey.isNotEmpty) namePhoneToId['${p['full_name'].toString().trim()}::$phoneKey'] = p['id'].toString();
  }

  final oldIdToProfile = <String, Map<String, dynamic>>{};
  final backupProfiles = ((payload['profiles'] as List?) ?? []).cast<Map<String, dynamic>>();
  for (final p in backupProfiles) {
    if (p['id'] != null) oldIdToProfile[p['id'].toString()] = p;
  }

  String? findExistingProfileId(dynamic oldId) {
    if (oldId == null) return null;
    final oldKey = oldId.toString();
    if (allowedUserIds.contains(oldKey)) return oldKey;
    final prof = oldIdToProfile[oldKey];
    if (prof == null) return null;
    final username = prof['username']?.toString() ?? '';
    if (username.isNotEmpty && usernameToId.containsKey(username)) return usernameToId[username];
    final phoneKey = _cleanPhone(prof['phone']);
    if (phoneKey.isNotEmpty && phoneToId.containsKey(phoneKey)) return phoneToId[phoneKey];
    final nameKey = (prof['full_name'] != null && phoneKey.isNotEmpty) ? '${prof['full_name'].toString().trim()}::$phoneKey' : '';
    if (nameKey.isNotEmpty && namePhoneToId.containsKey(nameKey)) return namePhoneToId[nameKey];
    return null;
  }

  final packagesIn = ((payload['packages'] as List?) ?? []).cast<Map<String, dynamic>>();
  final cardsIn = ((payload['cards'] as List?) ?? []).cast<Map<String, dynamic>>();
  final reqsIn = ((payload['card_requests'] as List?) ?? []).cast<Map<String, dynamic>>();
  final salesIn = ((payload['sales'] as List?) ?? []).cast<Map<String, dynamic>>();
  final joinReqsIn = ((payload['join_requests'] as List?) ?? []).cast<Map<String, dynamic>>();
  final paymentsIn = ((payload['request_payments'] as List?) ?? []).cast<Map<String, dynamic>>();

  final agentRefIds = <String>{};
  void addRef(dynamic v) {
    if (v != null) agentRefIds.add(v.toString());
  }

  for (final c in cardsIn) {
    addRef(c['assigned_to']);
    addRef(c['sold_to']);
  }
  for (final r in reqsIn) addRef(r['agent_id']);
  for (final s in salesIn) addRef(s['agent_id']);
  for (final r in joinReqsIn) addRef(r['agent_id']);

  String makeBaseUsername(Map<String, dynamic> profile, String oldId) {
    final raw = (profile['username']?.toString() ?? '').trim();
    final safe = raw.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '');
    if (safe.length >= 3) return safe.substring(0, min(24, safe.length));
    final phoneKey = _cleanPhone(profile['phone']);
    if (phoneKey.isNotEmpty) return 'u$phoneKey'.substring(0, min(24, phoneKey.length + 1));
    return 'agent_${oldId.replaceAll('-', '').substring(0, min(12, oldId.length))}';
  }

  String uniqueUsername(String base) {
    var candidate = base;
    var i = 1;
    while (usedUsernames.contains(candidate)) {
      candidate = '${base.substring(0, min(20, base.length))}_$i';
      i++;
    }
    usedUsernames.add(candidate);
    return candidate;
  }

  var createdProfiles = 0;
  for (final oldId in agentRefIds.toList()) {
    if (findExistingProfileId(oldId) != null) continue;
    final prof = oldIdToProfile[oldId];
    if (prof == null) continue;
    final username = uniqueUsername(makeBaseUsername(prof, oldId));
    final createdId = await supabase.rpc('restore_create_agent', params: {
      '_username': username,
      '_full_name': prof['full_name'],
      '_phone': prof['phone'],
    });
    if (createdId == null) throw Exception('profiles: تعذر إنشاء حساب المندوب من النسخة');
    createdProfiles++;
    final idStr = createdId.toString();
    allowedUserIds.add(idStr);
    usernameToId[username] = idStr;
    final phoneKey = _cleanPhone(prof['phone']);
    if (phoneKey.isNotEmpty) phoneToId[phoneKey] = idStr;
    if (prof['full_name'] != null && phoneKey.isNotEmpty) namePhoneToId['${prof['full_name'].toString().trim()}::$phoneKey'] = idStr;
    oldIdToProfile[oldId] = {...prof, 'id': createdId, 'username': username};
  }

  String? remap(dynamic oldId) => findExistingProfileId(oldId);

  List<Map<String, dynamic>> scrubUserRefs(List<Map<String, dynamic>> rows, List<String> fields) {
    return rows.map((r) {
      final out = Map<String, dynamic>.from(r);
      for (final f in fields) {
        if (out[f] != null) out[f] = remap(out[f]);
      }
      return out;
    }).toList();
  }

  final stats = <String, int>{'profiles': createdProfiles};
  Future<void> ins(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      stats[table] = 0;
      return;
    }
    await supabase.rpc('restore_insert_rows', params: {'_table': table, '_rows': rows});
    stats[table] = rows.length;
  }

  final pkgMap = <String, String>{};
  final cardMap = <String, String>{};
  final reqMap = <String, String>{};
  for (final p in packagesIn) {
    if (p['id'] != null) pkgMap[p['id'].toString()] = _genId();
  }
  for (final c in cardsIn) {
    if (c['id'] != null) cardMap[c['id'].toString()] = _genId();
  }
  for (final r in reqsIn) {
    if (r['id'] != null) reqMap[r['id'].toString()] = _genId();
  }

  final newPackages = packagesIn.map((p) => {...p, 'id': pkgMap[p['id']?.toString()] ?? _genId(), 'network_id': networkId}).toList();
  await ins('packages', newPackages);
  final validPkgIds = newPackages.map((p) => p['id'] as String).toSet();

  final newCards = scrubUserRefs(
    cardsIn.map((c) => {...c, 'id': cardMap[c['id']?.toString()] ?? _genId(), 'network_id': networkId, 'package_id': pkgMap[c['package_id']?.toString()] ?? c['package_id']}).toList(),
    ['assigned_to', 'sold_to'],
  ).where((c) => validPkgIds.contains(c['package_id'])).toList();
  await ins('cards', newCards);

  final scrubbedReqs = reqsIn
      .map((r) => {
            ...r,
            'id': reqMap[r['id']?.toString()] ?? _genId(),
            'network_id': networkId,
            'agent_id': remap(r['agent_id']),
            'package_id': pkgMap[r['package_id']?.toString()] ?? r['package_id'],
            'decided_by': remap(r['decided_by']),
          })
      .where((r) => r['agent_id'] != null && validPkgIds.contains(r['package_id']))
      .toList();
  await ins('card_requests', scrubbedReqs);
  final insertedReqIds = scrubbedReqs.map((r) => r['id'] as String).toSet();

  final newSales = scrubUserRefs(
    salesIn.map((s) => {...s, 'id': _genId(), 'network_id': networkId, 'package_id': pkgMap[s['package_id']?.toString()] ?? s['package_id'], 'card_id': cardMap[s['card_id']?.toString()] ?? s['card_id']}).toList(),
    ['agent_id'],
  ).where((s) => s['agent_id'] != null && validPkgIds.contains(s['package_id'])).toList();
  await ins('sales', newSales);

  await ins(
      'join_requests',
      joinReqsIn
          .map((r) => {...r, 'id': _genId(), 'network_id': networkId, 'agent_id': remap(r['agent_id']), 'decided_by': remap(r['decided_by'])})
          .where((r) => r['agent_id'] != null)
          .toList());

  final scrubbedPayments = paymentsIn
      .map((r) => {...r, 'id': _genId(), 'request_id': reqMap[r['request_id']?.toString()] ?? r['request_id'], 'recorded_by': remap(r['recorded_by']) ?? uid})
      .where((r) => r['request_id'] != null && insertedReqIds.contains(r['request_id']))
      .toList();
  await ins('request_payments', scrubbedPayments);

  final customersIn = ((payload['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
  final custPaymentsIn = ((payload['customer_payments'] as List?) ?? []).cast<Map<String, dynamic>>();
  final mikrotiksIn = ((payload['mikrotiks'] as List?) ?? []).cast<Map<String, dynamic>>();

  final custMap = <String, String>{};
  for (final c in customersIn) {
    if (c['id'] != null) custMap[c['id'].toString()] = _genId();
  }

  final newCustomers = customersIn
      .map((c) => {...c, 'id': custMap[c['id']?.toString()] ?? _genId(), 'network_id': networkId, 'agent_id': remap(c['agent_id']) ?? uid})
      .where((c) => c['whatsapp'] != null)
      .toList();
  await ins('customers', newCustomers);
  final validCustIds = newCustomers.map((c) => c['id'] as String).toSet();

  await ins(
      'customer_payments',
      custPaymentsIn
          .map((p) => {...p, 'id': _genId(), 'network_id': networkId, 'customer_id': custMap[p['customer_id']?.toString()] ?? p['customer_id'], 'agent_id': remap(p['agent_id']) ?? uid})
          .where((p) => validCustIds.contains(p['customer_id']))
          .toList());

  await ins('mikrotiks', mikrotiksIn.map((m) => {...m, 'id': _genId(), 'network_id': networkId, 'created_by': remap(m['created_by']) ?? uid}).toList());

  return RestoreResult(networkId: networkId, stats: stats);
}

// ============================================================
// نسخ احتياطي/استعادة لبيانات المندوب الخاصة (agent-backup.functions.ts)
// ============================================================

Future<Map<String, dynamic>> backupMyAgentData() async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');

  final profile = await supabase.from('profiles').select('*').eq('id', uid).maybeSingle();
  final customers = await supabase.from('customers').select('*').eq('agent_id', uid);
  final sales = await supabase.from('sales').select('*').eq('agent_id', uid);
  final requests = await supabase.from('card_requests').select('*').eq('agent_id', uid);
  // ⚠️ لا نجلب عمود password هنا إطلاقاً — كلمات المرور تُسلَّم فقط عبر تدفق
  // البيع المُدقَّق أو دوال RPC الإدارية، مطابقةً للنسخة الأصلية بالضبط.
  final cards = await supabase.from('cards').select('id, package_id, network_id, username, status, sold_to, sold_at, assigned_to, assigned_at, created_at').or('assigned_to.eq.$uid,sold_to.eq.$uid');
  final custPayments = await supabase.from('customer_payments').select('*').eq('agent_id', uid);

  final reqIds = (requests as List).map((r) => r['id'] as String).toList();
  final payments = reqIds.isEmpty ? [] : await supabase.from('request_payments').select('*').inFilter('request_id', reqIds);

  return {
    'exported_at': DateTime.now().toIso8601String(),
    'kind': 'agent-backup',
    'profile': profile,
    'customers': customers,
    'sales': sales,
    'card_requests': requests,
    'cards': cards,
    'request_payments': payments,
    'customer_payments': custPayments,
  };
}

class AgentRestoreResult {
  final int customersRestored, customersSkipped;
  final int requestsRestored, requestsSkipped;
  final int paymentsRestored, paymentsSkipped;
  final List<String> notes;
  const AgentRestoreResult({
    required this.customersRestored,
    required this.customersSkipped,
    required this.requestsRestored,
    required this.requestsSkipped,
    required this.paymentsRestored,
    required this.paymentsSkipped,
    required this.notes,
  });
}

Future<AgentRestoreResult> restoreMyAgentData(Map<String, dynamic> payload) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) throw Exception('يجب تسجيل الدخول');

  final myProfile = await supabase.from('profiles').select('network_id, username').eq('id', uid).maybeSingle();
  final networkId = myProfile?['network_id'] as String?;
  final agentUsername = myProfile?['username'] as String? ?? '';

  var customersRestored = 0, customersSkipped = 0;
  var requestsRestored = 0, requestsSkipped = 0;
  var paymentsRestored = 0, paymentsSkipped = 0;
  final notes = <String>[];

  final backupCustomers = ((payload['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
  final oldCustomerIdToWhatsapp = <String, String>{};
  for (final c in backupCustomers) {
    if (c['id'] != null && c['whatsapp'] != null) oldCustomerIdToWhatsapp[c['id'].toString()] = c['whatsapp'].toString().trim();
  }

  // 1) الزبائن — إدراج الجدد فقط (تفادي التكرار حسب واتساب)
  if (backupCustomers.isNotEmpty) {
    final existing = await supabase.from('customers').select('id, whatsapp').eq('agent_id', uid);
    final existingSet = (existing as List).map((c) => (c['whatsapp']?.toString() ?? '').trim()).toSet();
    final toInsert = backupCustomers
        .where((c) => c['whatsapp'] != null && !existingSet.contains(c['whatsapp'].toString().trim()))
        .map((c) => {'agent_id': uid, 'network_id': networkId, 'name': (c['name']?.toString() ?? '').trim().isEmpty ? 'زبون' : c['name'].toString().trim(), 'whatsapp': c['whatsapp'].toString().trim()})
        .toList();
    customersSkipped = backupCustomers.length - toInsert.length;
    if (toInsert.isNotEmpty) {
      await supabase.from('customers').insert(toInsert);
      customersRestored = toInsert.length;
    }
  }

  // 2) طلبات سحب الكروت — إعادة إنشائها كطلبات PENDING جديدة للباقات الموجودة
  final requests = ((payload['card_requests'] as List?) ?? []).cast<Map<String, dynamic>>();
  if (requests.isNotEmpty && networkId != null) {
    final pkgIds = requests.map((r) => r['package_id']).whereType<String>().toSet().toList();
    final pkgs = pkgIds.isEmpty ? [] : await supabase.from('packages').select('id, name, price, network_id').inFilter('id', pkgIds);
    final pkgMap = {for (final p in (pkgs as List)) p['id'] as String: p};

    final toInsertReq = requests
        .map((r) {
          final pkg = pkgMap[r['package_id']];
          if (pkg == null || pkg['network_id'] != networkId) return null;
          final qty = num.tryParse(r['quantity']?.toString() ?? '') ?? 0;
          if (qty <= 0) return null;
          final unitPrice = (pkg['price'] ?? 0) as num;
          return {
            'agent_id': uid,
            'agent_username': agentUsername,
            'package_id': pkg['id'],
            'network_id': networkId,
            'package_name': pkg['name'],
            'network_name': r['network_name'] ?? '',
            'quantity': qty,
            'status': 'PENDING',
            'payment_method': r['payment_method'] == 'CASH' ? 'CASH' : 'CREDIT',
            'unit_price': unitPrice,
            'total_value': unitPrice * qty,
            'paid_amount': 0,
            'notes': r['notes'],
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    requestsSkipped = requests.length - toInsertReq.length;
    if (toInsertReq.isNotEmpty) {
      await supabase.from('card_requests').insert(toInsertReq);
      requestsRestored = toInsertReq.length;
    }
  } else if (requests.isNotEmpty && networkId == null) {
    notes.add('لا يمكن استعادة الطلبات: حسابك غير مرتبط بشبكة.');
  }

  // 3) تسديدات الزبائن — إعادة الربط حسب رقم واتساب
  final custPayments = ((payload['customer_payments'] as List?) ?? []).cast<Map<String, dynamic>>();
  if (custPayments.isNotEmpty) {
    final myCustomers = await supabase.from('customers').select('id, whatsapp').eq('agent_id', uid);
    final waToId = {for (final c in (myCustomers as List)) if (c['whatsapp'] != null) c['whatsapp'].toString().trim(): c['id'] as String};

    final toInsertPay = custPayments
        .map((p) {
          final wa = oldCustomerIdToWhatsapp[p['customer_id']?.toString()];
          final newCustId = wa != null ? waToId[wa] : null;
          if (newCustId == null) return null;
          final amt = num.tryParse(p['amount']?.toString() ?? '');
          if (amt == null) return null;
          return {'customer_id': newCustId, 'agent_id': uid, 'network_id': networkId, 'amount': amt, 'note': p['note']};
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    paymentsSkipped = custPayments.length - toInsertPay.length;
    if (toInsertPay.isNotEmpty) {
      await supabase.from('customer_payments').insert(toInsertPay);
      paymentsRestored = toInsertPay.length;
    }
  }

  final salesCount = ((payload['sales'] as List?) ?? []).length;
  final cardsCount = ((payload['cards'] as List?) ?? []).length;
  if (salesCount > 0 || cardsCount > 0) {
    notes.add('لا يمكن استعادة المبيعات والكروت مباشرة (ملكيتها للشبكة). أُعيد إنشاء الطلبات كطلبات جديدة بانتظار موافقة المدير.');
  }

  return AgentRestoreResult(
    customersRestored: customersRestored,
    customersSkipped: customersSkipped,
    requestsRestored: requestsRestored,
    requestsSkipped: requestsSkipped,
    paymentsRestored: paymentsRestored,
    paymentsSkipped: paymentsSkipped,
    notes: notes,
  );
}

// ============================================================
// إدارة المناديب من طرف المدير (admin-agents.functions.ts)
// ============================================================

const _adminUpdateAgentErrors = {
  'INVALID_PHONE': 'رقم جوال غير صحيح',
  'PASSWORD_TOO_SHORT': 'كلمة المرور قصيرة جداً',
  'MISSING_AGENT_ID': 'معرّف المندوب مفقود',
};

Future<void> adminUpdateAgent({
  required String agentId,
  String? fullName,
  String? phone,
  String? password,
}) async {
  try {
    await supabase.rpc('admin_update_agent', params: {
      '_agent_id': agentId,
      '_full_name': fullName,
      '_phone': phone,
      '_password': password,
      '_update_full_name': fullName != null,
      '_update_phone': phone != null,
    });
  } on PostgrestException catch (e) {
    final key = _adminUpdateAgentErrors.keys.firstWhere((k) => e.message.contains(k), orElse: () => '');
    throw Exception(_adminUpdateAgentErrors[key] ?? e.message);
  }
}

Future<void> adminDeleteAgent(String agentId) async {
  final uid = supabase.auth.currentUser?.id;
  if (agentId == uid) throw Exception('لا يمكنك حذف حسابك الخاص');
  await supabase.rpc('admin_delete_agent', params: {'_agent_id': agentId});
}

// ============================================================
// تعديل رقم جوال مستخدم — للسوبر أدمن (superadmin-agents.functions.ts)
// ============================================================

Future<void> superadminUpdateUserPhone({required String userId, required String phone}) async {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6 || digits.length > 20) throw Exception('رقم جوال غير صحيح');
  await supabase.rpc('superadmin_update_user_phone', params: {'_user_id': userId, '_phone': digits});
}

// ============================================================
// مسح كل بيانات الموقع (DangerZone → wipeAllData)
// ============================================================

Future<void> wipeAllData() async {
  await supabase.rpc('admin_wipe_database');
}
