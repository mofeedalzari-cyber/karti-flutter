// نفس منطق src/routes/app.logs.tsx بالكامل — جدول logs، تحديد جماعي وحذف،
// تمييز سجلات بيع تم حذف عمليتها لاحقاً.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';

class LogRow {
  final String id;
  final String? actorUsername;
  final String action;
  final String? entity;
  final String? entityId;
  final Map<String, dynamic>? metadata;
  final String createdAt;

  LogRow({
    required this.id,
    this.actorUsername,
    required this.action,
    this.entity,
    this.entityId,
    this.metadata,
    required this.createdAt,
  });

  factory LogRow.fromMap(Map<String, dynamic> m) => LogRow(
        id: m['id'] as String,
        actorUsername: m['actor_username'] as String?,
        action: m['action'] as String? ?? '',
        entity: m['entity'] as String?,
        entityId: m['entity_id'] as String?,
        metadata: m['metadata'] as Map<String, dynamic>?,
        createdAt: m['created_at'] as String? ?? '',
      );
}

const _actionLabels = {'SELL_CARD': 'بيع كرت', 'UPLOAD_CARDS': 'رفع كروت'};
String labelizeAction(String a) => _actionLabels[a] ?? a;

final logsProvider = FutureProvider<List<LogRow>>((ref) async {
  final rows = await supabase.from('logs').select('id, actor_username, action, entity, entity_id, metadata, created_at').order('created_at', ascending: false).limit(200);
  return (rows as List).map((r) => LogRow.fromMap(r as Map<String, dynamic>)).toList();
});

/// معرّفات المبيعات الموجودة فعلياً — لتمييز سجلات بيع حُذفت عمليتها لاحقاً.
final existingSaleIdsProvider = FutureProvider<Set<String>>((ref) async {
  final logs = await ref.watch(logsProvider.future);
  final saleIds = logs.where((l) => l.action == 'SELL_CARD' && l.entity == 'sale' && l.entityId != null).map((l) => l.entityId!).toList();
  if (saleIds.isEmpty) return {};
  final rows = await supabase.from('sales').select('id').inFilter('id', saleIds);
  return (rows as List).map((r) => r['id'] as String).toSet();
});

bool isDeletedSaleLog(LogRow l, Set<String> existingSales) {
  return l.action == 'SELL_CARD' && l.entity == 'sale' && (l.entityId == null || !existingSales.contains(l.entityId));
}

Future<void> deleteLogs(List<String> ids) async {
  await supabase.from('logs').delete().inFilter('id', ids);
}

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final Set<String> _selected = {};

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السجلات'),
        content: Text('حذف ${_selected.length} سجل؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    await deleteLogs(_selected.toList());
    setState(() => _selected.clear());
    ref.invalidate(logsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(logsProvider);
    final existingSalesAsync = ref.watch(existingSaleIdsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('سجل النشاط')),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذر التحميل: $e')),
        data: (logs) {
          if (logs.isEmpty) return const Center(child: Text('لا يوجد نشاط بعد.'));
          final existingSales = existingSalesAsync.value ?? {};
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Checkbox(
                    value: logs.every((l) => _selected.contains(l.id)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.addAll(logs.map((l) => l.id));
                      } else {
                        _selected.clear();
                      }
                    }),
                  ),
                  const Text('تحديد الكل', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    TextButton.icon(onPressed: _bulkDelete, icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), label: Text('حذف (${_selected.length})', style: const TextStyle(color: Colors.red))),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final l = logs[i];
                    final deletedSale = isDeletedSaleLog(l, existingSales);
                    final selected = _selected.contains(l.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: Checkbox(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(l.id);
                            } else {
                              _selected.remove(l.id);
                            }
                          }),
                        ),
                        title: Row(children: [
                          Flexible(child: Text(labelizeAction(l.action), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                          Text(' — ${l.actorUsername ?? 'نظام'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          if (deletedSale)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                              child: const Text('عملية محذوفة', style: TextStyle(fontSize: 9, color: Colors.red)),
                            ),
                        ]),
                        subtitle: l.metadata != null
                            ? Text(jsonEncode(l.metadata), style: const TextStyle(fontSize: 10, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
