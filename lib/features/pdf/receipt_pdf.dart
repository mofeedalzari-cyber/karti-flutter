// نفس محتوى src/lib/receipt-pdf.ts (إيصال قبض رسمي لدفعة مندوب) — تصميم
// مبسّط باستخدام pdf/widgets بدل pdfmake، لكن بنفس البيانات والمعنى:
// اسم الشبكة، المندوب، المبلغ، البيان، التوقيعات.
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/pdf_service.dart';
import '../../utils/format.dart';

class CreditReceiptInput {
  final String networkName;
  final String networkPhone;
  final String agentName;
  final num amount;
  final String statement; // البيان
  final String dateStr;
  final String adminName;

  CreditReceiptInput({
    required this.networkName,
    required this.networkPhone,
    required this.agentName,
    required this.amount,
    required this.statement,
    required this.dateStr,
    required this.adminName,
  });
}

Future<Uint8List> buildCreditReceiptPdf(CreditReceiptInput input) async {
  final theme = await buildArabicPdfTheme();
  final doc = pw.Document(theme: theme);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(input.networkName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text(input.networkPhone, textDirection: pw.TextDirection.ltr, style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('إيصال قبض', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(input.dateStr, style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(height: 20),
          pw.Text('استلمت من الأخ الفاضل / ${input.agentName}', style: const pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 10),
          pw.Text('نود اشعاركم اننا قيدنا إلى حسابكم لدينا حسب التفاصيل التالية:', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
            children: [
              pw.TableRow(children: [
                _cell('البيان', bold: true),
                _cell('المبلغ', bold: true),
              ]),
              pw.TableRow(children: [
                _cell(input.statement),
                _cell(fmtMoney(input.amount)),
              ]),
            ],
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(children: [
                pw.Text(input.adminName, style: const pw.TextStyle(fontSize: 11)),
                pw.SizedBox(height: 4),
                pw.Text('مستلم الكروت', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ]),
              pw.Column(children: [
                pw.SizedBox(height: 15),
                pw.Text('مندوب', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ]),
            ],
          ),
          pw.Spacer(),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('© كرتي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text('برمجة وتصميم مفيد الزري', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(text, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

/// يبني الإيصال ثم يفتح معاينة الطباعة/المشاركة مباشرة (نفس سلوك
/// printReceiptPDF بالنسخة الأصلية).
Future<void> printReceiptPdf(CreditReceiptInput input) async {
  final bytes = await buildCreditReceiptPdf(input);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'إيصال-${input.agentName}.pdf');
}
