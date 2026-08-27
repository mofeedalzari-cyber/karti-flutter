// نسخة بديلة (stub) تُستخدم فقط عند البناء لهدف الويب (Flutter Web) — بروتوكول
// API الثنائي للميكروتك يعتمد على Socket خام من dart:io، وهذا غير مدعوم على
// المتصفح إطلاقاً. راجع routeros_api_io.dart للتنفيذ الحقيقي (أندرويد/iOS/سطح
// المكتب)، وroutero_api.dart لآلية الاختيار التلقائي بينهما (conditional export).
class RouterOSException implements Exception {
  final String message;
  RouterOSException(this.message);
  @override
  String toString() => message;
}

class RouterOSApi {
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    bool useTls = false,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    throw RouterOSException('ميزة الاتصال بالميكروتيك غير مدعومة على نسخة الويب — استخدم تطبيق الجوال (Android).');
  }

  Future<List<Map<String, String>>> talk(String command, [List<String> params = const []]) async {
    throw RouterOSException('ميزة الاتصال بالميكروتيك غير مدعومة على نسخة الويب — استخدم تطبيق الجوال (Android).');
  }

  void close() {}
}
