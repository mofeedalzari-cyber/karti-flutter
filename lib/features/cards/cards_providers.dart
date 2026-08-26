// نفس منطق src/routes/app.cards.tsx بالضبط — نفس دالة RPC bulk_upload_cards
// بدون أي تعديل على قاعدة البيانات.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../../services/supabase_service.dart';

enum CardUploadMode { userOnly, userPass }

class CardEntry {
  final String username;
  final String? password;
  const CardEntry({required this.username, this.password});

  Map<String, dynamic> toMap() => {
        'username': username,
        if (password != null) 'password': password,
      };
}

class ParsedCards {
  final List<CardEntry> entries;
  final List<String> errors;
  final int total;
  const ParsedCards({required this.entries, required this.errors, required this.total});
}

/// يحلّل النص الملصوق/المرفوع بنفس منطق النسخة الأصلية بالضبط: يدعم الفاصل
/// | أو , أو tab أو مسافة، وأسطر JSON مفردة {"username":...,"password":...}.
ParsedCards parseCardLines(String rawText, CardUploadMode mode) {
  final lines = rawText.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final entries = <CardEntry>[];
  final errors = <String>[];

  for (final line in lines) {
    if (mode == CardUploadMode.userOnly) {
      entries.add(CardEntry(username: line));
      continue;
    }
    if (line.startsWith('{')) {
      try {
        final o = jsonDecode(line) as Map<String, dynamic>;
        if (o['username'] != null) {
          entries.add(CardEntry(
            username: o['username'].toString(),
            password: o['password']?.toString(),
          ));
          continue;
        }
      } catch (_) {
        /* تجاهل، جرّب الفواصل بالأسفل */
      }
    }
    final sep = line.contains('|')
        ? '|'
        : line.contains(',')
            ? ','
            : line.contains('\t')
                ? '\t'
                : ' ';
    final parts = line.split(sep);
    final u = parts.first.trim();
    final p = parts.skip(1).join(sep).trim();
    if (u.isEmpty) {
      errors.add(line);
      continue;
    }
    entries.add(CardEntry(username: u, password: p.isEmpty ? null : p));
  }
  return ParsedCards(entries: entries, errors: errors, total: lines.length);
}

/// يحوّل محتوى ملف JSON (Array) لأسطر نصية، مطابق لمعالجة الملفات بالنسخة
/// الأصلية.
String? jsonFileToLines(String content) {
  try {
    final arr = jsonDecode(content);
    if (arr is List) {
      return arr.map((x) {
        if (x is String) return x;
        final m = x as Map<String, dynamic>;
        final pass = m['password'];
        return '${m['username']}${pass != null ? '|$pass' : ''}';
      }).join('\n');
    }
  } catch (_) {
    /* ليس JSON صالح */
  }
  return null;
}

class BulkUploadResult {
  final int inserted;
  final int duplicates;
  final int errors;
  const BulkUploadResult({required this.inserted, required this.duplicates, required this.errors});

  factory BulkUploadResult.fromMap(Map<String, dynamic> m) => BulkUploadResult(
        inserted: (m['inserted'] ?? 0) as int,
        duplicates: (m['duplicates'] ?? 0) as int,
        errors: (m['errors'] ?? 0) as int,
      );
}

Future<BulkUploadResult> bulkUploadCards({
  required String packageId,
  required List<CardEntry> entries,
}) async {
  final data = await supabase.rpc('bulk_upload_cards', params: {
    '_package_id': packageId,
    '_entries': entries.map((e) => e.toMap()).toList(),
  });
  final row = (data is List) ? data.first as Map<String, dynamic> : data as Map<String, dynamic>;
  return BulkUploadResult.fromMap(row);
}

final cardsPackagesOfNetworkProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, networkId) async {
  if (networkId.isEmpty) return [];
  final rows = await supabase.from('packages').select('id, name').eq('network_id', networkId).order('name');
  return (rows as List).cast<Map<String, dynamic>>();
});
