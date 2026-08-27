// نفس تصميم ومنطق src/routes/app.cards.tsx — رفع كروت بالجملة (نص/ملف).
// ملاحظة: استخراج الكروت من ملفات PDF مؤجّل للمرحلة 7 (راجع MIGRATION_PLAN.md)
// — هذي النسخة تدعم اللصق المباشر وملفات TXT/CSV/JSON فقط حالياً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/pdf_extract.dart' as pdf_extract;
import '../auth/profile_provider.dart';
import '../packages/packages_providers.dart';
import 'cards_providers.dart';

class CardsUploadScreen extends ConsumerWidget {
  const CardsUploadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (profile) {
        // هذي الصفحة للمدير (والسوبر أدمن) فقط — نفس تحقق role !== "admin" بالنسخة الأصلية
        if (profile?.isAdminOrAbove != true) {
          return const Center(child: Text('هذه الصفحة متاحة للمدراء فقط'));
        }
        return const _CardsUploadBody();
      },
    );
  }
}

class _CardsUploadBody extends ConsumerStatefulWidget {
  const _CardsUploadBody();

  @override
  ConsumerState<_CardsUploadBody> createState() => _CardsUploadBodyState();
}

class _CardsUploadBodyState extends ConsumerState<_CardsUploadBody> {
  String? _networkId;
  String? _packageId;
  CardUploadMode _mode = CardUploadMode.userPass;
  final _textCtrl = TextEditingController();
  ParsedCards _parsed = const ParsedCards(entries: [], errors: [], total: 0);
  bool _busy = false;
  bool _extractingPdf = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_reparse);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _reparse() {
    setState(() => _parsed = parseCardLines(_textCtrl.text, _mode));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'json', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    final ext = file.extension?.toLowerCase();

    if (ext == 'pdf') {
      setState(() => _extractingPdf = true);
      try {
        final text = pdf_extract.extractPdfText(file.bytes!);
        final pdfMode = _mode == CardUploadMode.userOnly ? pdf_extract.CardExtractMode.userOnly : pdf_extract.CardExtractMode.userPass;
        final lines = pdf_extract.pdfTextToCardLines(text, pdfMode);
        _textCtrl.text = lines;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر استخراج النص من الملف: $e')));
        }
      } finally {
        if (mounted) setState(() => _extractingPdf = false);
      }
      return;
    }

    final content = String.fromCharCodes(file.bytes!);
    if (ext == 'json') {
      final lines = jsonFileToLines(content);
      if (lines != null) {
        _textCtrl.text = lines;
        return;
      }
    }
    _textCtrl.text = content;
  }

  Future<void> _upload() async {
    if (_packageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر الباقة')));
      return;
    }
    if (_parsed.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد بيانات صالحة')));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await bulkUploadCards(packageId: _packageId!, entries: _parsed.entries);
      if (!mounted) return;
      final parts = <String>[];
      if (r.inserted > 0) parts.add('تم إضافة ${r.inserted} كرت');
      if (r.duplicates > 0) parts.add('تخطي ${r.duplicates} مكرر');
      if (r.errors > 0) parts.add('${r.errors} خطأ');
      final msg = parts.isNotEmpty ? parts.join(' — ') : 'لم تتم إضافة أي كرت';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _textCtrl.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final networksAsync = ref.watch(networksProvider);
    final packagesAsync =
        _networkId == null ? null : ref.watch(cardsPackagesOfNetworkProvider(_networkId!));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('رفع الكروت', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('أضف الكروت بالجملة إلى الباقات', style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: networksAsync.when(
                data: (networks) => DropdownButtonFormField<String>(
                  initialValue: _networkId,
                  decoration: const InputDecoration(labelText: 'الشبكة'),
                  items: networks.map((n) => DropdownMenuItem(value: n.id, child: Text(n.name))).toList(),
                  onChanged: (v) => setState(() {
                    _networkId = v;
                    _packageId = null;
                  }),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('تعذر التحميل'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _packageId,
                decoration: const InputDecoration(labelText: 'الباقة'),
                items: (packagesAsync?.value ?? [])
                    .map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['name'] as String)))
                    .toList(),
                onChanged: _networkId == null ? null : (v) => setState(() => _packageId = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        SegmentedButton<CardUploadMode>(
          segments: const [
            ButtonSegment(value: CardUploadMode.userPass, label: Text('مستخدم | كلمة مرور')),
            ButtonSegment(value: CardUploadMode.userOnly, label: Text('مستخدم فقط')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() {
            _mode = s.first;
            _reparse();
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _mode == CardUploadMode.userPass
              ? 'كل سطر: 3852557443|1234 — يدعم أيضاً الفواصل: , أو tab'
              : 'كل سطر يمثل اسم مستخدم فقط.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _textCtrl,
          maxLines: 10,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'لصق أو تحميل ملف (TXT / CSV / JSON)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _extractingPdf ? null : _pickFile,
              icon: _extractingPdf
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.description_outlined, size: 16),
              label: Text(_extractingPdf ? 'جارٍ استخراج النص...' : 'تحميل ملف (TXT/CSV/JSON/PDF)'),
            ),
            const SizedBox(width: 12),
            if (_parsed.total > 0) ...[
              _CountBadge(icon: Icons.check, label: '${_parsed.entries.length} صالح', color: Colors.green),
              const SizedBox(width: 8),
              if (_parsed.errors.isNotEmpty)
                _CountBadge(icon: Icons.warning_amber, label: '${_parsed.errors.length} خطأ', color: Colors.orange),
            ],
          ],
        ),
        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: _busy || _packageId == null || _parsed.entries.isEmpty ? null : _upload,
          icon: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_outlined),
          label: Text(_busy ? 'جارٍ الرفع...' : 'رفع ${_parsed.entries.length} كرت'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _CountBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
