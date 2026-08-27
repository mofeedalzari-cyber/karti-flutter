// واجهة موحّدة لتنفيذ بروتوكول API الثنائي لروترOS — تختار تلقائياً بين:
// - routeros_api_io.dart: التنفيذ الحقيقي عبر Socket خام (dart:io) للجوال/سطح
//   المكتب، حيث dart:io مدعومة.
// - routeros_api_stub.dart: بديل يرمي خطأ واضح عند البناء لهدف الويب، لأن
//   dart:io (وبالتالي Socket) غير مدعومة إطلاقاً بالمتصفح.
// راجع routeros_api_io.dart للتوثيق الكامل لتنفيذ البروتوكول نفسه.
export 'routeros_api_stub.dart' if (dart.library.io) 'routeros_api_io.dart';
