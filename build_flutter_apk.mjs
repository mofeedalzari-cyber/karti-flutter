// يُنفَّذ عبر: node build_flutter_apk.mjs
// يجهّز مشروع Flutter بالكامل تلقائياً ثم يبني APK — بضغطة واحدة:
//   1) ينشئ مشروع Flutter (flutter create) إن لم يكن موجوداً
//   2) ينسخ lib/ وpubspec.yaml من هذا المجلد فوق المشروع الجديد
//   3) يشغّل flutter pub get
//   4) يضيف أذونات Android المطلوبة لـ AndroidManifest.xml
//   5) ينسخ google-services.json ويربط Firebase بملفات Gradle
//   6) يتأكد من minSdkVersion 24
//   7) يبني APK فعلي (flutter build apk --release)
//
// ⚠️ يتطلب: Flutter SDK مثبّت مسبقاً (flutter --version يعمل بالطرفية).

import { existsSync, readFileSync, writeFileSync, cpSync, mkdirSync } from "node:fs";
import { execSync } from "node:child_process";
import { join } from "node:path";

const cwd = process.cwd();
const projectDir = join(cwd, "karti_app");
const androidRoot = join(projectDir, "android");

// لو أمر flutter غير موجود بـ PATH، مرّر مسار flutter.bat/flutter كوسيطة:
//   node build_flutter_apk.mjs "C:\flutter\bin\flutter.bat"
const FLUTTER = process.argv[2] ? `"${process.argv[2]}"` : "flutter";

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

function read(path) {
  return readFileSync(path, "utf8");
}
function write(path, content) {
  writeFileSync(path, content, "utf8");
}

try {
  step("0/7 — التحقق من تثبيت Flutter", () => {
    try {
      run(`${FLUTTER} --version`);
    } catch {
      console.log("");
      console.log("❌ الأمر flutter غير موجود. ثبّت Flutter SDK أولاً من:");
      console.log("   https://docs.flutter.dev/get-started/install");
      process.exit(1);
    }
  });

  step("1/7 — إنشاء مشروع Flutter (karti_app)", () => {
    if (existsSync(projectDir)) {
      console.log("مجلد karti_app موجود مسبقاً — تخطي الإنشاء.");
    } else {
      run(`${FLUTTER} create --org com.mofeed --project-name karti karti_app`);
    }
  });

  step("2/7 — نسخ ملفات كرتي (lib/ و pubspec.yaml)", () => {
    cpSync(join(cwd, "lib"), join(projectDir, "lib"), { recursive: true });
    cpSync(join(cwd, "pubspec.yaml"), join(projectDir, "pubspec.yaml"));
    console.log("✅ تم نسخ lib/ و pubspec.yaml فوق المشروع الجديد.");
  });

  step("3/7 — تثبيت الحزم (flutter pub get)", () => {
    run(`${FLUTTER} pub get`, { cwd: projectDir });
  });

  step("4/7 — إضافة أذونات Android لـ AndroidManifest.xml", () => {
    const manifestPath = join(androidRoot, "app", "src", "main", "AndroidManifest.xml");
    if (!existsSync(manifestPath)) {
      console.log("⚠️  لم يتم العثور على AndroidManifest.xml — تخطي.");
      return;
    }
    let manifest = read(manifestPath);
    const permissions = [
      "android.permission.INTERNET",
      "android.permission.ACCESS_NETWORK_STATE",
      "android.permission.POST_NOTIFICATIONS",
      "android.permission.WAKE_LOCK",
      "android.permission.READ_CONTACTS",
      "android.permission.WRITE_CONTACTS",
    ];
    let added = 0;
    for (const perm of permissions) {
      if (manifest.includes(perm)) continue;
      const tag = `    <uses-permission android:name="${perm}" />\n`;
      manifest = manifest.replace(/<application/, `${tag}\n    <application`);
      added++;
    }
    if (!manifest.includes("<queries>")) {
      const queriesBlock = `    <queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW" />\n            <data android:scheme="https" />\n        </intent>\n    </queries>\n\n    <application`;
      manifest = manifest.replace(/<application/, queriesBlock);
      added++;
    }
    write(manifestPath, manifest);
    console.log(added > 0 ? `✅ تمت إضافة ${added} عنصر جديد لملف الأذونات.` : "✅ كل الأذونات موجودة مسبقاً.");
  });

  step("5/7 — ربط Firebase (google-services.json + Gradle)", () => {
    const stagedJson = join(cwd, "firebase", "google-services.json");
    const targetJson = join(androidRoot, "app", "google-services.json");
    if (existsSync(stagedJson)) {
      cpSync(stagedJson, targetJson);
      console.log("✅ تم نسخ google-services.json.");
    } else {
      console.log("⚠️  لم يتم العثور على firebase/google-services.json المُجهَّز مسبقاً.");
    }

    const projectGradle = join(androidRoot, "build.gradle");
    const projectGradleKts = join(androidRoot, "build.gradle.kts");
    const CLASSPATH = "com.google.gms:google-services:4.4.2";
    if (existsSync(projectGradle)) {
      let gradle = read(projectGradle);
      if (!gradle.includes("google-services")) {
        if (/dependencies\s*\{/.test(gradle)) {
          gradle = gradle.replace(/dependencies\s*\{/, `dependencies {\n        classpath '${CLASSPATH}'`);
          write(projectGradle, gradle);
          console.log("✅ تمت إضافة classpath لـ android/build.gradle.");
        } else {
          console.log("⚠️  لم يتم العثور على كتلة dependencies بـ android/build.gradle — أضفها يدوياً:");
          console.log(`   classpath '${CLASSPATH}'`);
        }
      } else {
        console.log("✅ classpath موجود مسبقاً.");
      }
    } else if (existsSync(projectGradleKts)) {
      console.log("⚠️  مشروعك يستخدم صيغة Kotlin DSL الحديثة (build.gradle.kts) — أضف يدوياً بقسم dependencies:");
      console.log(`   classpath("${CLASSPATH}")`);
    } else {
      console.log("⚠️  لم يتم العثور على android/build.gradle أو android/build.gradle.kts.");
    }

    const appGradle = join(androidRoot, "app", "build.gradle");
    const appGradleKts = join(androidRoot, "app", "build.gradle.kts");
    const PLUGIN = "com.google.gms.google-services";
    if (existsSync(appGradle)) {
      let content = read(appGradle);
      if (!content.includes(PLUGIN)) {
        content = content.trimEnd() + `\n\napply plugin: '${PLUGIN}'\n`;
        write(appGradle, content);
        console.log("✅ تمت إضافة apply plugin لـ android/app/build.gradle.");
      } else {
        console.log("✅ apply plugin موجود مسبقاً.");
      }
    } else if (existsSync(appGradleKts)) {
      console.log("⚠️  مشروعك يستخدم صيغة Kotlin DSL الحديثة (build.gradle.kts) — أضف يدوياً بأعلى الملف بقسم plugins { ... }:");
      console.log(`   id("com.google.gms.google-services")`);
    }
  });

  step("6/7 — التأكد من minSdkVersion 24", () => {
    const appGradle = join(androidRoot, "app", "build.gradle");
    const appGradleKts = join(androidRoot, "app", "build.gradle.kts");
    if (existsSync(appGradle)) {
      let content = read(appGradle);
      const before = content;
      content = content.replace(/minSdkVersion\s+flutter\.minSdkVersion/, "minSdkVersion 24");
      content = content.replace(/minSdkVersion\s+(\d+)/, (match, num) => (Number(num) < 24 ? "minSdkVersion 24" : match));
      if (content !== before) {
        write(appGradle, content);
        console.log("✅ تم ضبط minSdkVersion إلى 24.");
      } else {
        console.log("✅ minSdkVersion مضبوط مسبقاً (24 أو أعلى)، أو يحتاج تحقق يدوي بسيط.");
      }
    } else if (existsSync(appGradleKts)) {
      let content = read(appGradleKts);
      const before = content;
      content = content.replace(/minSdk\s*=\s*flutter\.minSdkVersion/, "minSdk = 24");
      content = content.replace(/minSdk\s*=\s*(\d+)/, (match, num) => (Number(num) < 24 ? "minSdk = 24" : match));
      if (content !== before) {
        write(appGradleKts, content);
        console.log("✅ تم ضبط minSdk إلى 24 (صيغة Kotlin DSL).");
      } else {
        console.log("⚠️  تحقق يدوياً من قيمة minSdk بملف android/app/build.gradle.kts (يجب أن تكون 24 فأعلى).");
      }
    }
  });

  step("7/7 — بناء APK (flutter build apk --release)", () => {
    run(`${FLUTTER} build apk --release`, { cwd: projectDir });
  });

  console.log("");
  console.log("========================================");
  console.log("✅ تم بناء APK بنجاح!");
  console.log("========================================");
  console.log("الملف الناتج:");
  console.log("  karti_app/build/app/outputs/flutter-apk/app-release.apk");
  console.log("");
  console.log("انسخه لهاتفك وثبّته، وابدأ باختبار القائمة الكاملة بملف PHASE9_BUILD_GUIDE.md");
} catch (err) {
  console.error("");
  console.error("❌ فشل تنفيذ إحدى الخطوات أعلاه. راجع رسالة الخطأ للتفاصيل، وأرسلها لي إذا احتجت مساعدة.");
  process.exit(1);
}
