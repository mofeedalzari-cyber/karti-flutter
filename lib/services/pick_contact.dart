// نفس منطق src/lib/pick-contact.ts — اختيار جهة اتصال من الجهاز عبر
// flutter_contacts (بديل حديث لـ @capacitor-community/contacts المستخدمة
// بالنسخة الأصلية).
import 'package:flutter_contacts/flutter_contacts.dart';

class PickedContact {
  final String name;
  final String phone;
  const PickedContact({required this.name, required this.phone});
}

enum PickContactError { permissionDenied, cancelled, failed }

class PickContactResult {
  final bool ok;
  final PickedContact? contact;
  final PickContactError? error;
  final String? message;
  const PickContactResult({required this.ok, this.contact, this.error, this.message});
}

Future<PickContactResult> pickContact() async {
  try {
    final granted = await FlutterContacts.requestPermission();
    if (!granted) {
      return const PickContactResult(ok: false, error: PickContactError.permissionDenied, message: 'لم يتم منح صلاحية الوصول لجهات الاتصال');
    }

    final selected = await FlutterContacts.openExternalPick();
    if (selected == null) {
      return const PickContactResult(ok: false, error: PickContactError.cancelled);
    }

    // نجيب التفاصيل الكاملة (أرقام الهاتف) بما إن openExternalPick قد يرجع بيانات مختصرة
    final full = await FlutterContacts.getContact(selected.id) ?? selected;
    final name = full.displayName.trim();
    final phone = full.phones.isNotEmpty ? full.phones.first.number.trim() : '';

    if (name.isEmpty && phone.isEmpty) {
      return const PickContactResult(ok: false, error: PickContactError.cancelled);
    }
    return PickContactResult(ok: true, contact: PickedContact(name: name, phone: phone));
  } catch (e) {
    return PickContactResult(ok: false, error: PickContactError.failed, message: 'فشل الوصول لجهات الاتصال: $e');
  }
}
