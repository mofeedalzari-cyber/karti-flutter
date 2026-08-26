// مطابق تماماً لـ src/lib/format.ts → fmtMoney()
import 'package:intl/intl.dart';

String fmtMoney(num n) {
  final formatter = NumberFormat.decimalPattern('en_US')..maximumFractionDigits = 2;
  return '${formatter.format(n)} ﷼';
}
