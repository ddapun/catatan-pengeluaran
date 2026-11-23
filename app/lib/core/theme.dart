import 'package:flutter/material.dart';

/// Token warna dari berkas desain (mode terang & gelap).
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.warn,
    required this.soft,
    required this.series,
  });

  final Color bg;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color warn;
  final Color soft;
  final List<Color> series;

  static const light = AppColors(
    bg: Color(0xFFEEF0F3),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF12161C),
    muted: Color(0xFF6B7480),
    line: Color(0xFFE3E6EB),
    accent: Color(0xFF1F6F5C),
    accentInk: Color(0xFFFFFFFF),
    warn: Color(0xFFC2410C),
    soft: Color(0xFFF3F5F7),
    series: [
      Color(0xFF1F6F5C),
      Color(0xFF3B6FD4),
      Color(0xFFB7791F),
      Color(0xFF8B5CF6),
      Color(0xFF9AA3AF),
    ],
  );

  static const dark = AppColors(
    bg: Color(0xFF0B0E12),
    surface: Color(0xFF151A21),
    ink: Color(0xFFEEF1F4),
    muted: Color(0xFF939CA8),
    line: Color(0xFF242B34),
    accent: Color(0xFF5BC3A6),
    accentInk: Color(0xFF0B0E12),
    warn: Color(0xFFFB923C),
    soft: Color(0xFF1C222B),
    series: [
      Color(0xFF5BC3A6),
      Color(0xFF7AA2F0),
      Color(0xFFE0A94A),
      Color(0xFFA78BFA),
      Color(0xFF6B7480),
    ],
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? accentInk,
    Color? warn,
    Color? soft,
    List<Color>? series,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      warn: warn ?? this.warn,
      soft: soft ?? this.soft,
      series: series ?? this.series,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      accent: mix(accent, other.accent),
      accentInk: mix(accentInk, other.accentInk),
      warn: mix(warn, other.warn),
      soft: mix(soft, other.soft),
      series: List.generate(series.length, (i) => mix(series[i], other.series[i])),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

const tabularFigures = [FontFeature.tabularFigures()];

ThemeData buildAppTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? AppColors.light : AppColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.accentInk,
    secondary: c.accent,
    onSecondary: c.accentInk,
    error: c.warn,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    outline: c.line,
    surfaceContainerHighest: c.soft,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'PlusJakartaSans',
    extensions: [c],
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: c.ink, displayColor: c.ink)
        .copyWith(
          displayLarge: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFeatures: tabularFigures,
            color: c.ink,
          ),
          titleMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
          bodySmall: TextStyle(fontSize: 12, color: c.muted),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: c.ink,
        fontFamily: 'PlusJakartaSans',
      ),
      iconTheme: IconThemeData(color: c.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.surface, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.soft,
      hintStyle: TextStyle(color: c.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.accent),
    ),
  );
}
