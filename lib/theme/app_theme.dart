// ثيم التطبيق — نفس ألوان النسخة الحالية (React) بالضبط، منقولة من src/styles.css
// اللون الأساسي: #009688 (teal) — نفس القيمة المُستخدمة بالنسخة الويب الحالية.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // منقولة حرفياً من src/styles.css (الوضع الفاتح)
  static const primary = Color(0xFF009688); // --primary
  static const primaryGlow = Color(0xFF14B8A6); // --primary-glow
  static const background = Color(0xFFF8FAFC); // --background
  static const foreground = Color(0xFF0F172A); // --foreground
  static const destructive = Color(0xFFEF4444); // --destructive
  static const success = Color(0xFF22C55E); // --success
  static const warning = Color(0xFFF59E0B); // --warning
  static const border = Color(0xFFE7EAF0); // تقريب من --border

  // الوضع الداكن
  static const primaryDark = Color(0xFF1FB6A6); // من oklch(0.68 0.13 185)
  static const backgroundDark = Color(0xFF0B1220);
  static const foregroundDark = Color(0xFFF1F5F9);
}

class AppTheme {
  static const double radius = 12; // --radius: 0.75rem

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      error: AppColors.destructive,
    );
    return _base(scheme, AppColors.background, AppColors.foreground);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryDark,
      brightness: Brightness.dark,
      primary: AppColors.primaryDark,
      error: AppColors.destructive,
    );
    return _base(scheme, AppColors.backgroundDark, AppColors.foregroundDark);
  }

  static ThemeData _base(ColorScheme scheme, Color bg, Color fg) {
    final textTheme = GoogleFonts.cairoTextTheme().apply(
      bodyColor: fg,
      displayColor: fg,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      fontFamily: GoogleFonts.cairo().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 4),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
