// نفس منطق src/lib/pdf-extract.ts بالضبط (استخراج النص + تحليله لأزواج
// مستخدم/كلمة مرور بنفس قواعد Regex الأصلية) — الفرق الوحيد هو مكتبة
// استخراج النص نفسها.
//
// ⚠️ تنويه مهم بخصوص الترخيص: هذي الميزة تستخدم حزمة `syncfusion_flutter_pdf`
// لاستخراج النص من PDF. مكتبات Syncfusion لفلاتر تتطلب ترخيصاً — إما "رخصة
// مجتمعية مجانية" (Community License) لو ربح شركتك أقل من حد معيّن سنوياً
// (راجع syncfusion.com/sales/communitylicense)، أو رخصة تجارية مدفوعة.
// تأكد من الأهلية أو احصل على ترخيص قبل نشر هذي الميزة بالإنتاج. لو ما
// تنطبق عليك الرخصة المجانية، تقدر تكتفي برفع الكروت عبر نص/TXT/CSV/JSON
// (يشتغل بدون أي مكتبة خارجية) وتعطيل هذا الجزء فقط.
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

enum CardExtractMode { userOnly, userPass }

/// يستخرج كل النص من ملف PDF (حتى 200 صفحة، نفس حد النسخة الأصلية).
String extractPdfText(Uint8List bytes, {int maxPages = 200}) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    final pageCount = document.pages.count > maxPages ? maxPages : document.pages.count;
    final buffer = StringBuffer();
    for (var i = 0; i < pageCount; i++) {
      buffer.writeln(PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i));
    }
    return buffer.toString();
  } finally {
    document.dispose();
  }
}

/// يحوّل النص الخام المستخرج إلى أسطر كروت (مستخدم فقط أو مستخدم|كلمة مرور)
/// — نفس منطق pdfTextToCardLines() الأصلي حرفياً (نفس أنماط Regex بالضبط).
String pdfTextToCardLines(String allText, CardExtractMode mode) {
  final tokens = RegExp(r'\d{3,20}').allMatches(allText).map((m) => m.group(0)!).toList();
  final usernames = <String>[];
  final passwords = <String>[];
  for (final t in tokens) {
    if (t.length >= 8) {
      usernames.add(t);
    } else {
      passwords.add(t);
    }
  }

  final seen = <String>{};
  final uniqueUsers = usernames.where((u) => seen.add(u)).toList();

  if (mode == CardExtractMode.userOnly) return uniqueUsers.join('\n');

  final inlineRe = RegExp(r'(\d{8,20})\D{1,20}?(\d{3,7})(?!\d)');
  final inlinePairs = <String, String>{};
  for (final m in inlineRe.allMatches(allText)) {
    final user = m.group(1)!;
    if (!inlinePairs.containsKey(user)) inlinePairs[user] = m.group(2)!;
  }

  if (inlinePairs.length >= (uniqueUsers.length * 0.6).floor()) {
    return uniqueUsers.map((u) => inlinePairs.containsKey(u) ? '$u|${inlinePairs[u]}' : u).join('\n');
  }
  if (passwords.length >= uniqueUsers.length) {
    return List.generate(uniqueUsers.length, (i) => '${uniqueUsers[i]}|${passwords[i]}').join('\n');
  }
  return uniqueUsers.join('\n');
}
