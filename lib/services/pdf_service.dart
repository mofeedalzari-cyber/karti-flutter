// خدمة PDF مشتركة — تحميل خط Cairo وقت التشغيل عبر PdfGoogleFonts (من حزمة
// printing الرسمية)، بدل تضمين ملف خط بالمشروع أو الاعتماد على روابط ثابتة
// قد تتغيّر — هذي الطريقة الموثوقة والمُدعومة رسمياً لخطوط Google Fonts
// بمستندات PDF بفلاتر.
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Font? _cairoRegular;
pw.Font? _cairoBold;

/// يحمّل خط Cairo (عادي وعريض) مرة واحدة ويخزّنه للاستخدام بكل مستندات PDF
/// اللاحقة بنفس الجلسة.
Future<(pw.Font, pw.Font)> loadCairoFonts() async {
  if (_cairoRegular != null && _cairoBold != null) {
    return (_cairoRegular!, _cairoBold!);
  }
  _cairoRegular = await PdfGoogleFonts.cairoRegular();
  _cairoBold = await PdfGoogleFonts.cairoBold();
  return (_cairoRegular!, _cairoBold!);
}

/// يبني ثيم PDF جاهز (خط عربي + اتجاه RTL) لاستخدامه بـ pw.Document.
Future<pw.ThemeData> buildArabicPdfTheme() async {
  final (regular, bold) = await loadCairoFonts();
  return pw.ThemeData.withFont(base: regular, bold: bold);
}
