// يُنفَّذ عبر: node build_flutter_web.mjs
// يبني نسخة ويب من التطبيق (flutter build web) لمعاينة سريعة بالمتصفح —
// مخصص أصلاً ليكون أمر البناء (buildCommand) باستضافة استاتيكية مثل Render
// (راجع render.yaml بجذر المشروع)، لكن يشتغل محلياً كمان بنفس الطريقة.
//
//   1) يتأكد من وجود Flutter SDK — لو غير موجود بالـ PATH (حالة سيرفر بناء
//      نظيف مثل Render)، يحمّله تلقائياً (git clone ضحل لفرع stable)
//   2) ينشئ مشروع Flutter (flutter create) إن لم يكن موجوداً
//   3) ينسخ lib/ وpubspec.yaml من هذا المجلد فوق المشروع الجديد
//   4) يشغّل flutter pub get
//   5) يبني نسخة الويب (flutter build web --release)
//
// ⚠️ ملاحظة مهمة: هذي نسخة "معاينة" وليست الإصدار الرسمي — ميزة الاتصال
// المباشر بالميكروتيك (Socket) غير مدعومة على الويب أصلاً (راجع
// lib/services/routeros_api_stub.dart)، وتحتاج تعبئة lib/config.dart
// بقيمة supabaseAnonKey الحقيقية قبل أي اختبار فعلي لتسجيل الدخول.

import { existsSync, cpSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

const cwd = process.cwd();
const projectDir = join(cwd, "karti_app");
const sdkDir = join(cwd, ".flutter_sdk");

function step(title, fn) {
  console.log("");
  console.log("========================================");
  console.log(title);
  console.log("========================================");
  fn();
}

function run(cmd, options = {}) {
  execSync(cmd, { stdio: "inherit", shell: true, ...options });
}

function commandExists(cmd) {
  try {
    execSync(`${cmd} --version`, { stdio: "ignore", shell: true });
    return true;
  } catch {
    return false;
  }
}

try {
  let FLUTTER = "flutter";

  step("0/5 — التحقق من تثبيت Flutter", () => {
    if (commandExists("flutter")) {
      console.log("✅ Flutter موجود بالـ PATH.");
      return;
    }
    const localFlutter = join(sdkDir, "bin", "flutter");
    if (existsSync(localFlutter)) {
      console.log("✅ نسخة Flutter محلية موجودة مسبقاً (.flutter_sdk) — إعادة استخدامها.");
      FLUTTER = `"${localFlutter}"`;
      return;
    }
    console.log("⬇️  Flutter غير موجود — تحميل نسخة stable تلقائياً (سيرفر بناء نظيف)...");
    run(`git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${sdkDir}"`);
    FLUTTER = `"${localFlutter}"`;
  });

  step("0.5/5 — تفعيل دعم الويب", () => {
    run(`${FLUTTER} config --enable-web`);
  });

  step("1/5 — إنشاء مشروع Flutter (karti_app)", () => {
    if (existsSync(projectDir)) {
      console.log("مجلد karti_app موجود مسبقاً — تخطي الإنشاء.");
    } else {
      run(`${FLUTTER} create --org com.mofeed --project-name karti karti_app`);
    }
  });

  step("2/5 — نسخ ملفات كرتي (lib/ و pubspec.yaml)", () => {
    cpSync(join(cwd, "lib"), join(projectDir, "lib"), { recursive: true });
    cpSync(join(cwd, "pubspec.yaml"), join(projectDir, "pubspec.yaml"));
    console.log("✅ تم نسخ lib/ و pubspec.yaml فوق المشروع الجديد.");
  });

  step("3/5 — تثبيت الحزم (flutter pub get)", () => {
    run(`${FLUTTER} pub get`, { cwd: projectDir });
  });

  step("4/5 — بناء نسخة الويب (flutter build web --release)", () => {
    run(`${FLUTTER} build web --release`, { cwd: projectDir });
  });

  console.log("");
  console.log("========================================");
  console.log("✅ تم بناء نسخة الويب بنجاح!");
  console.log("========================================");
  console.log("الملفات الناتجة: karti_app/build/web");
} catch (err) {
  console.error("");
  console.error("❌ فشل تنفيذ إحدى الخطوات أعلاه. راجع رسالة الخطأ للتفاصيل.");
  process.exit(1);
}
