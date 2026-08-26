// تنفيذ بروتوكول API الثنائي لروترOS (RouterOS API Protocol) مباشرة بـ Dart
// عبر Socket خام — يعمل من الجوال مباشرة، بدون أي حاجة لسيرفر وسيط.
// المرجع الرسمي: https://wiki.mikrotik.com/wiki/Manual:API
//
// ⚠️ ملاحظة صراحة: هذا الكود مكتوب حسب توثيق البروتوكول الرسمي بعناية، لكن
// ما قدرت أختبره ضد جهاز ميكروتك حقيقي من بيئتي (لا شبكة عندي هنا). أول
// اختبار فعلي بيصير عندك — لو طلعت مشكلة اتصال أرسل لي رسالة الخطأ بالضبط.
//
// يدعم تسجيل الدخول الحديث (RouterOS 6.43+ فأعلى) بإرسال name/password
// مباشرة بدون تحدي MD5 — يغطي جميع الإصدارات الحديثة المستخدمة اليوم.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:async/async.dart';

class RouterOSException implements Exception {
  final String message;
  RouterOSException(this.message);
  @override
  String toString() => message;
}

class _Reply {
  final bool isTrap;
  final List<Map<String, String>> rows;
  _Reply(this.isTrap, this.rows);
}

class RouterOSApi {
  Socket? _socket;
  StreamQueue<int>? _byteQueue;

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    bool useTls = false,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final socket = useTls
          ? await SecureSocket.connect(host, port, timeout: timeout, onBadCertificate: (_) => true)
          : await Socket.connect(host, port, timeout: timeout);
      _socket = socket;
      _byteQueue = StreamQueue<int>(socket.expand((chunk) => chunk));
    } on SocketException catch (e) {
      throw RouterOSException(_friendlySocketError(e));
    } on TimeoutException {
      throw RouterOSException('انتهت مهلة الاتصال — تأكد من صحة العنوان والمنفذ، وأن الجهاز يقبل اتصالات من هنا.');
    }

    await _writeSentence(['/login', '=name=$username', '=password=$password']);
    final reply = await _readFullReply();
    if (reply.isTrap) {
      throw RouterOSException(_loginErrorMessage(reply.rows));
    }
  }

  String _friendlySocketError(SocketException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('refused')) {
      return 'الاتصال مرفوض. تأكد أن خدمة api أو api-ssl مفعّلة في IP → Services بالميكروتيك.';
    }
    if (msg.contains('timed out') || msg.contains('timeout')) {
      return 'انتهت المهلة. تأكد أنك على نفس الشبكة، أو أن منفذ API موجّه للإنترنت (Port Forward).';
    }
    if (msg.contains('network is unreachable') || msg.contains('no route')) {
      return 'الشبكة غير متاحة. تأكد من اتصال جوالك بالإنترنت/الشبكة المحلية.';
    }
    return e.message;
  }

  String _loginErrorMessage(List<Map<String, String>> rows) {
    final raw = rows.isNotEmpty ? (rows.first['message'] ?? '') : '';
    if (raw.toLowerCase().contains('invalid') || raw.toLowerCase().contains('cannot log in')) {
      return 'اسم المستخدم أو كلمة المرور غير صحيحة.';
    }
    return raw.isNotEmpty ? raw : 'فشل تسجيل الدخول بالميكروتيك.';
  }

  /// ينفّذ أمراً (مثل /system/resource/print أو /ip/hotspot/user/add مع
  /// معاملات مثل =name=value) ويرجع صفوف النتيجة.
  Future<List<Map<String, String>>> talk(String command, [List<String> params = const []]) async {
    if (_socket == null) throw RouterOSException('لست متصلاً بالميكروتيك');
    await _writeSentence([command, ...params]);
    final reply = await _readFullReply();
    if (reply.isTrap) {
      final msg = reply.rows.isNotEmpty ? (reply.rows.first['message'] ?? 'خطأ غير معروف') : 'خطأ غير معروف';
      throw RouterOSException(msg);
    }
    return reply.rows;
  }

  void close() {
    try {
      _socket?.destroy();
    } catch (_) {
      /* تجاهل */
    }
    _socket = null;
  }

  // ============================================================
  // طبقة البروتوكول الأدنى (ترميز/فك ترميز الطول، الكلمات، الجمل)
  // ============================================================

  Future<void> _writeSentence(List<String> words) async {
    for (final w in words) {
      _writeWord(w);
    }
    _socket!.add(const [0]); // كلمة فارغة تنهي الجملة
    await _socket!.flush();
  }

  void _writeWord(String word) {
    final bytes = utf8.encode(word);
    _socket!.add(_encodeLength(bytes.length));
    _socket!.add(bytes);
  }

  List<int> _encodeLength(int length) {
    if (length < 0x80) {
      return [length];
    } else if (length < 0x4000) {
      final l = length | 0x8000;
      return [(l >> 8) & 0xFF, l & 0xFF];
    } else if (length < 0x200000) {
      final l = length | 0xC00000;
      return [(l >> 16) & 0xFF, (l >> 8) & 0xFF, l & 0xFF];
    } else if (length < 0x10000000) {
      final l = length | 0xE0000000;
      return [(l >> 24) & 0xFF, (l >> 16) & 0xFF, (l >> 8) & 0xFF, l & 0xFF];
    } else {
      return [0xF0, (length >> 24) & 0xFF, (length >> 16) & 0xFF, (length >> 8) & 0xFF, length & 0xFF];
    }
  }

  Future<int> _readByte() async {
    if (!(await _byteQueue!.hasNext)) {
      throw RouterOSException('انقطع الاتصال بالميكروتيك أثناء القراءة.');
    }
    return _byteQueue!.next;
  }

  Future<List<int>> _readBytes(int n) async {
    final result = <int>[];
    for (var i = 0; i < n; i++) {
      result.add(await _readByte());
    }
    return result;
  }

  Future<int> _readLength() async {
    final c = await _readByte();
    if ((c & 0x80) == 0x00) {
      return c;
    } else if ((c & 0xC0) == 0x80) {
      final b2 = await _readByte();
      return ((c & 0x3F) << 8) + b2;
    } else if ((c & 0xE0) == 0xC0) {
      final rest = await _readBytes(2);
      return ((c & 0x1F) << 16) + (rest[0] << 8) + rest[1];
    } else if ((c & 0xF0) == 0xE0) {
      final rest = await _readBytes(3);
      return ((c & 0x0F) << 24) + (rest[0] << 16) + (rest[1] << 8) + rest[2];
    } else {
      final rest = await _readBytes(4);
      return (rest[0] << 24) + (rest[1] << 16) + (rest[2] << 8) + rest[3];
    }
  }

  Future<String> _readWord() async {
    final len = await _readLength();
    if (len == 0) return '';
    final bytes = await _readBytes(len);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<List<String>> _readSentence() async {
    final words = <String>[];
    while (true) {
      final w = await _readWord();
      if (w.isEmpty) break;
      words.add(w);
    }
    return words;
  }

  /// يقرأ كل الجمل حتى !done، يجمع صفوف !re، ويتذكر أول !trap إن وُجد.
  Future<_Reply> _readFullReply() async {
    final rows = <Map<String, String>>[];
    Map<String, String>? trapRow;
    while (true) {
      final sentence = await _readSentence();
      if (sentence.isEmpty) continue;
      final type = sentence.first;
      final row = <String, String>{};
      for (final w in sentence.skip(1)) {
        if (!w.startsWith('=')) continue;
        final eq = w.indexOf('=', 1);
        if (eq > 0) row[w.substring(1, eq)] = w.substring(eq + 1);
      }
      if (type == '!re') {
        rows.add(row);
      } else if (type == '!trap') {
        trapRow ??= row;
      } else if (type == '!done') {
        return _Reply(trapRow != null, trapRow != null ? [trapRow] : rows);
      } else if (type == '!fatal') {
        throw RouterOSException(sentence.length > 1 ? sentence[1] : 'خطأ فادح بالاتصال بالميكروتيك.');
      }
    }
  }
}
