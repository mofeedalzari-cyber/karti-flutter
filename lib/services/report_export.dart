// نفس فكرة src/lib/pdfmake-report.ts + src/lib/dashboard-export.ts —
// مولّد تقرير عام (ملخص + أقسام جداول) قابل لإعادة الاستخدام من أي صفحة
// (لوحة التحكم، المبيعات...). النتيجة: ملف PDF أو Excel.
//
// ملاحظة: استُخدمت حزمة `excel` (رخصة MIT مفتوحة، بدون أي قيود) بدل مكتبات
// أخرى تتطلب ترخيصاً تجارياً — عكس استخراج نص PDF (راجع pdf_extract.dart)
// اللي يحتاج Syncfusion لأنه ما فيه بديل مجاني موثوق بنفس الجودة لهذي المهمة
// المحددة (قراءة/تحليل PDF)، بينما إنشاء Excel من الصفر له بدائل مجانية جيدة.
import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/pdf_service.dart';

class ReportSummaryRow {
  final String label;
  final String value;
  const ReportSummaryRow(this.label, this.value);
}

class ReportTableSection {
  final String title;
  final List<String> cols;
  final List<List<String>> rows;
  const ReportTableSection({required this.title, required this.cols, required this.rows});
}

// ============================================================
// PDF
// ============================================================

Future<Uint8List> buildReportPdf({
  required String title,
  required List<ReportSummaryRow> summary,
  required List<ReportTableSection> sections,
  String systemName = 'كرتي — نظام إدارة الشبكات والمناديب',
  String? userName,
}) async {
  final theme = await buildArabicPdfTheme();
  final doc = pw.Document(theme: theme);
  final dateStr = DateTime.now().toString().split('.').first;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => context.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(systemName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    if (userName != null) pw.Text('المستخدم: $userName', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(dateStr, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(color: PdfColors.teal700, thickness: 1.2),
              ],
            )
          : pw.SizedBox.shrink(),
      footer: (context) => pw.Column(children: [
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('© كرتي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('صفحة ${context.pageNumber} / ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
      ]),
      build: (context) => [
        if (summary.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            children: summary
                .map((s) => pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(s.label, style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(s.value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                    ]))
                .toList(),
          ),
        ],
        for (final sec in sections) ...[
          pw.SizedBox(height: 18),
          pw.Text(sec.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: sec.cols.map((c) => _cell(c, bold: true)).toList(),
              ),
              ...sec.rows.map((row) => pw.TableRow(children: row.map((v) => _cell(v)).toList())),
            ],
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

Future<void> exportReportToPdf({
  required String title,
  required List<ReportSummaryRow> summary,
  required List<ReportTableSection> sections,
  String? userName,
}) async {
  final bytes = await buildReportPdf(title: title, summary: summary, sections: sections, userName: userName);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$title.pdf');
}

// ============================================================
// Excel
// ============================================================

Uint8List buildReportExcel({
  required List<ReportSummaryRow> summary,
  required List<ReportTableSection> sections,
}) {
  final workbook = xls.Excel.createExcel();
  final summarySheet = workbook['الملخص'];
  summarySheet.appendRow([xls.TextCellValue('البند'), xls.TextCellValue('القيمة')]);
  for (final s in summary) {
    summarySheet.appendRow([xls.TextCellValue(s.label), xls.TextCellValue(s.value)]);
  }

  for (final sec in sections) {
    final name = sec.title.length > 30 ? sec.title.substring(0, 30) : sec.title;
    final sheet = workbook[name];
    sheet.appendRow(sec.cols.map((c) => xls.TextCellValue(c)).toList());
    for (final row in sec.rows) {
      sheet.appendRow(row.map((v) => xls.TextCellValue(v)).toList());
    }
  }

  // حذف الورقة الافتراضية الفارغة (Sheet1) لو ظلّت موجودة
  if (workbook.sheets.containsKey('Sheet1') && workbook.sheets.length > 1) {
    workbook.delete('Sheet1');
  }

  final bytes = workbook.save();
  return Uint8List.fromList(bytes!);
}

/// يبني ملف Excel ثم يفتح قائمة المشاركة مباشرة من البيانات بالذاكرة (بدون
/// ملف مؤقت على القرص) — يعمل بنفس الطريقة على الجوال والويب.
Future<void> exportReportToExcel({
  required String fileName,
  required List<ReportSummaryRow> summary,
  required List<ReportTableSection> sections,
}) async {
  final bytes = buildReportExcel(summary: summary, sections: sections);
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: '$fileName.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    ],
    text: fileName,
  );
}
