// نسخة مبسّطة من src/lib/card-print.ts — النسخة الأصلية تدعم "قالب صورة
// مخصص" (رفع خلفية وتحديد موقع الكود عليها بالبكسل، عبر Canvas). هذي الميزة
// تحديداً (تخصيص الصورة) بحجم عمل كبير جداً بذاتها، فبنيت بدلها تصميم بطاقة
// قياسي نظيف واحترافي — يطبع نفس البيانات (اسم المستخدم/كلمة المرور/الباقة)
// بشكل منظّم بالجدول، بدون تخصيص الخلفية. لو احتجت التخصيص لاحقاً نضيفه
// كميزة منفصلة.
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/pdf_service.dart';

class PrintableCard {
  final String username;
  final String? password;
  const PrintableCard({required this.username, this.password});
}

Future<Uint8List> buildCardsPdf({
  required List<PrintableCard> cards,
  required String title,
}) async {
  final theme = await buildArabicPdfTheme();
  final doc = pw.Document(theme: theme);

  // 6 كروت بكل صفحة (شبكة 2×3) — حجم مناسب للقص والتوزيع.
  const perPage = 6;
  for (var start = 0; start < cards.length; start += perPage) {
    final pageCards = cards.skip(start).take(perPage).toList();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.GridView(
              crossAxisCount: 2,
              childAspectRatio: 2.4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: pageCards.map(_cardBox).toList(),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

pw.Widget _cardBox(PrintableCard c) => pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text('اسم المستخدم', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text(c.username, textDirection: pw.TextDirection.ltr, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if (c.password != null) ...[
            pw.SizedBox(height: 6),
            pw.Text('كلمة المرور', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text(c.password!, textDirection: pw.TextDirection.ltr, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ],
      ),
    );

Future<void> printCardsPdf({required List<PrintableCard> cards, required String title}) async {
  final bytes = await buildCardsPdf(cards: cards, title: title);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'كروت.pdf');
}
