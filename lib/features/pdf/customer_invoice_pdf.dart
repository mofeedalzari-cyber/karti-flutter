// نفس محتوى src/lib/customer-invoice-pdf.ts — فاتورة رسمية للزبون: بنود
// الشراء، سجل التسديد/الشحن، الإجمالي، تحويل المبلغ لكلمات عربية (نفس دوال
// numberToArabicWords/currencyWord حرفياً)، رقم فاتورة تسلسلي محفوظ محلياً.
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/pdf_service.dart';
import '../../utils/format.dart';

// ============================================================
// تحويل الأرقام لكلمات عربية — نفس المصفوفات والمنطق الأصلي حرفياً
// ============================================================

const _ones = ['', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر'];
const _tens = ['', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون'];
const _hundreds = ['', 'مائة', 'مئتان', 'ثلاثمائة', 'أربعمائة', 'خمسمائة', 'ستمائة', 'سبعمائة', 'ثمانمائة', 'تسعمائة'];

String _under1000(int n) {
  final parts = <String>[];
  final h = n ~/ 100;
  final rem = n % 100;
  if (h > 0) parts.add(_hundreds[h]);
  if (rem < 20) {
    if (rem > 0) parts.add(_ones[rem]);
  } else {
    final o = rem % 10, t = rem ~/ 10;
    parts.add(o > 0 ? '${_ones[o]} و${_tens[t]}' : _tens[t]);
  }
  return parts.join(' و');
}

String numberToArabicWords(num value) {
  var n = value.abs().floor();
  if (n == 0) return 'صفر';
  final parts = <String>[];
  final mil = n ~/ 1000000;
  final th = (n % 1000000) ~/ 1000;
  final rest = n % 1000;
  if (mil > 0) {
    if (mil == 1) {
      parts.add('مليون');
    } else if (mil == 2) {
      parts.add('مليونان');
    } else if (mil <= 10) {
      parts.add('${_ones[mil]} ملايين');
    } else {
      parts.add('${_under1000(mil)} مليون');
    }
  }
  if (th > 0) {
    if (th == 1) {
      parts.add('ألف');
    } else if (th == 2) {
      parts.add('ألفان');
    } else if (th <= 10) {
      parts.add('${_ones[th]} آلاف');
    } else {
      parts.add('${_under1000(th)} ألف');
    }
  }
  if (rest > 0) parts.add(_under1000(rest));
  return parts.join(' و');
}

String currencyWord(String currency) {
  final c = currency.trim();
  if (c.isEmpty) return 'ريال سعودي';
  if (RegExp('سعودي|SAR|ر.س', caseSensitive: false).hasMatch(c)) return 'ريال سعودي';
  if (RegExp('يمني|YER', caseSensitive: false).hasMatch(c)) return 'ريال يمني';
  if (RegExp('دولار|USD', caseSensitive: false).hasMatch(c)) return 'دولار أمريكي';
  return c;
}

/// رقم فاتورة تسلسلي محفوظ محلياً على الجهاز — نفس فكرة localStorage
/// بالنسخة الأصلية (عداد يبدأ من 1595).
Future<int> nextInvoiceNumber() async {
  final prefs = await SharedPreferences.getInstance();
  final cur = prefs.getInt('karti_invoice_counter') ?? 1595;
  final next = cur + 1;
  await prefs.setInt('karti_invoice_counter', next);
  return next;
}

// ============================================================
// نموذج البيانات
// ============================================================

class InvoiceItem {
  final String packageName;
  final String? networkName;
  final String? cardNumber;
  final String? dateStr;
  final int qty;
  final num price;
  const InvoiceItem({required this.packageName, this.networkName, this.cardNumber, this.dateStr, required this.qty, required this.price});
  num get total => price * qty;
}

class LedgerEntry {
  final num amount; // موجب = تسديد، سالب = مبلغ مضاف
  final String? note;
  final String? dateStr;
  const LedgerEntry({required this.amount, this.note, this.dateStr});
}

class CustomerInvoiceInput {
  final String networkName;
  final String? networkPhone;
  final String adminName;
  final String customerName;
  final List<InvoiceItem> items;
  final List<LedgerEntry> ledger;
  final String currency;
  final String dateStr;

  const CustomerInvoiceInput({
    required this.networkName,
    this.networkPhone,
    required this.adminName,
    required this.customerName,
    required this.items,
    this.ledger = const [],
    required this.currency,
    required this.dateStr,
  });
}

// ============================================================
// البناء
// ============================================================

Future<Uint8List> buildCustomerInvoicePdf(CustomerInvoiceInput input) async {
  final theme = await buildArabicPdfTheme();
  final doc = pw.Document(theme: theme);
  final invoiceNo = await nextInvoiceNumber();

  final itemsTotal = input.items.fold<num>(0, (s, i) => s + i.total);
  final paid = input.ledger.where((l) => l.amount > 0).fold<num>(0, (s, l) => s + l.amount);
  final charges = input.ledger.where((l) => l.amount < 0).fold<num>(0, (s, l) => s + l.amount.abs());
  final grandTotal = itemsTotal + charges;
  final remaining = (grandTotal - paid).clamp(0, double.infinity);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(input.networkName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('فاتورة رقم $invoiceNo', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          if (input.networkPhone != null) pw.Text(input.networkPhone!, textDirection: pw.TextDirection.ltr, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Divider(),
        ],
      ),
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
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('العميل: ${input.customerName}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text(input.dateStr, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.SizedBox(height: 16),

        // جدول البنود
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.5), 4: pw.FlexColumnWidth(1.5)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              _cell('الباقة', bold: true),
              _cell('الشبكة', bold: true),
              _cell('الكمية', bold: true),
              _cell('السعر', bold: true),
              _cell('الإجمالي', bold: true),
            ]),
            ...input.items.map((it) => pw.TableRow(children: [
                  _cell(it.packageName),
                  _cell(it.networkName ?? '—'),
                  _cell('${it.qty}'),
                  _cell(fmtMoney(it.price)),
                  _cell(fmtMoney(it.total)),
                ])),
          ],
        ),
        pw.SizedBox(height: 16),

        // ملخص الإجمالي
        pw.Align(
          alignment: pw.AlignmentDirectional.centerEnd,
          child: pw.Container(
            width: 220,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              _summaryRow('إجمالي البنود', fmtMoney(itemsTotal)),
              if (charges > 0) _summaryRow('مبالغ إضافية', fmtMoney(charges)),
              _summaryRow('الإجمالي الكلي', fmtMoney(grandTotal), bold: true),
              _summaryRow('المدفوع', fmtMoney(paid), color: PdfColors.green700),
              _summaryRow('المتبقي', fmtMoney(remaining), color: PdfColors.orange700, bold: true),
            ]),
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'فقط لا غير: ${numberToArabicWords(grandTotal)} ${currencyWord(input.currency)}',
          style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
        ),

        if (input.ledger.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text('سجل التسديد', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
                _cell('التاريخ', bold: true),
                _cell('النوع', bold: true),
                _cell('المبلغ', bold: true),
                _cell('ملاحظة', bold: true),
              ]),
              ...input.ledger.map((l) => pw.TableRow(children: [
                    _cell(l.dateStr ?? '—'),
                    _cell(l.amount < 0 ? 'شحن يدوي' : 'تسديد'),
                    _cell(fmtMoney(l.amount.abs())),
                    _cell(l.note ?? '—'),
                  ])),
            ],
          ),
        ],

        pw.SizedBox(height: 40),
        pw.Text(input.adminName, style: const pw.TextStyle(fontSize: 11)),
        pw.Text('مدير ${input.networkName}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

pw.Widget _summaryRow(String label, String value, {bool bold = false, PdfColor? color}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
        ],
      ),
    );

Future<void> printCustomerInvoicePdf(CustomerInvoiceInput input) async {
  final bytes = await buildCustomerInvoicePdf(input);
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'فاتورة-${input.customerName}.pdf');
}
