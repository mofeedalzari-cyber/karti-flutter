// نفس منطق src/routes/app.settings.tsx بالكامل — تعديل الملف الشخصي، نسخ
// احتياطي/استعادة، ومنطقة الخطر (مسح البيانات). كل العمليات مباشرة عبر
// Supabase بدون أي سيرفر وسيط (راجع backup_providers.dart لتفاصيل السبب).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../services/supabase_service.dart';
import '../auth/profile_provider.dart';
import '../backup/backup_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _busy = false;
  bool _initialized = false;

  Future<void> _save() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await supabase.from('profiles').update({
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'full_name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      }).eq('id', profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البيانات')));
      ref.invalidate(profileProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          if (!_initialized) {
            _nameCtrl.text = profile.fullName ?? '';
            _phoneCtrl.text = profile.phone ?? '';
            _initialized = true;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoRow(label: 'اسم المستخدم', value: profile.phone ?? profile.username),
                      _InfoRow(label: 'نوع الحساب', value: profile.isSuperadmin ? 'سوبر أدمن' : (profile.role == Role.admin ? 'مدير' : 'وكيل')),
                      _InfoRow(label: 'الحالة', value: profile.isActive ? 'مفعّل' : 'موقوف'),
                      const SizedBox(height: 12),
                      TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneCtrl,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'رقم الهاتف', hintText: '7xxxxxxxx'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 16),
                        label: const Text('حفظ التعديلات'),
                      ),
                    ],
                  ),
                ),
              ),
              if (profile.isAdminOrAbove) ...[
                const SizedBox(height: 16),
                _BackupRestoreCard(isAdmin: true),
                const SizedBox(height: 16),
                const _DangerZoneCard(),
              ] else ...[
                const SizedBox(height: 16),
                _BackupRestoreCard(isAdmin: false),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _BackupRestoreCard extends StatefulWidget {
  final bool isAdmin;
  const _BackupRestoreCard({required this.isAdmin});

  @override
  State<_BackupRestoreCard> createState() => _BackupRestoreCardState();
}

class _BackupRestoreCardState extends State<_BackupRestoreCard> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final data = widget.isAdmin ? await backupMyNetwork() : await backupMyAgentData();
      final json = backupToJsonString(data);
      final dir = await getTemporaryDirectory();
      final name = 'karti-backup-${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$name');
      await file.writeAsString(json);
      if (mounted) await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية — كرتي');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
    if (result == null || result.files.single.bytes == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: Text(widget.isAdmin
            ? 'سيتم حذف بيانات شبكتك الحالية بالكامل واستبدالها بمحتوى الملف. لا يمكن التراجع.'
            : 'سيتم استعادة الزبائن والتسديدات وإعادة إنشاء الطلبات كطلبات جديدة (بانتظار موافقة المدير). المبيعات والكروت لا تُستعاد مباشرة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final content = String.fromCharCodes(result.files.single.bytes!);
      final payload = jsonDecode(content) as Map<String, dynamic>;
      if (!mounted) return;
      if (widget.isAdmin) {
        final r = await restoreMyNetwork(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت الاستعادة — ${r.stats.entries.map((e) => '${e.key}: ${e.value}').join('، ')}')));
        }
      } else {
        final r = await restoreMyAgentData(payload);
        if (mounted) {
          final msg = 'تمت الاستعادة — زبائن: ${r.customersRestored} (تخطي ${r.customersSkipped})، طلبات: ${r.requestsRestored}${r.notes.isNotEmpty ? ' — ${r.notes.join(' ')}' : ''}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستعادة: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.backup_outlined, size: 18),
              const SizedBox(width: 8),
              Text(widget.isAdmin ? 'نسخ احتياطي لشبكتي' : 'نسخ احتياطي لبياناتي', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Text(
              widget.isAdmin ? 'يحفظ كل بيانات شبكتك (الباقات، الكروت، المبيعات، الزبائن...) كملف JSON.' : 'يحفظ زبائنك ومبيعاتك وطلباتك كملف JSON.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _backup,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('نسخ احتياطي'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: _busy ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_outlined, size: 16),
                  label: const Text('استعادة'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DangerZoneCard extends StatefulWidget {
  const _DangerZoneCard();

  @override
  State<_DangerZoneCard> createState() => _DangerZoneCardState();
}

class _DangerZoneCardState extends State<_DangerZoneCard> {
  bool _expanded = false;
  final _confirmCtrl = TextEditingController();
  bool _busy = false;

  Future<void> _wipe() async {
    setState(() => _busy = true);
    try {
      await wipeAllData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصفير قاعدة البيانات بنجاح')));
      setState(() {
        _expanded = false;
        _confirmCtrl.clear();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل المسح: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _confirmCtrl.text.trim() == 'مسح';
    return Card(
      color: Colors.red.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.red.withValues(alpha: 0.3))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: const [
              Icon(Icons.warning_amber_outlined, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text('منطقة الخطر', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
            ]),
            const SizedBox(height: 6),
            Text(
              'سيتم حذف كل الشبكات والباقات والكروت وطلبات السحب والمبيعات والسجل وحسابات المناديب. لا يمكن التراجع. سيبقى حسابك كمدير.',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
            ),
            const SizedBox(height: 10),
            if (!_expanded)
              OutlinedButton.icon(
                onPressed: () => setState(() => _expanded = true),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.delete_forever_outlined, size: 16),
                label: const Text('مسح جميع بيانات الموقع'),
              )
            else ...[
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'للتأكيد اكتب كلمة '),
                TextSpan(text: 'مسح', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red.shade700)),
              ]), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              TextField(controller: _confirmCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'مسح')),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: (canDelete && !_busy) ? _wipe : null,
                  child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تأكيد المسح النهائي'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _expanded = false;
                    _confirmCtrl.clear();
                  }),
                  child: const Text('إلغاء'),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
