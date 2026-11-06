import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'responsive.dart';

/// Tokens del portal Arypsa (`frontend/tailwind.config.js`), los mismos que usa
/// la app del scanner. Si el portal cambia de paleta, se cambia aquí.
class Brand {
  static const c50 = Color(0xFFFDECEC);
  static const c100 = Color(0xFFFAD2D2);
  static const c300 = Color(0xFFF07E80);
  static const c400 = Color(0xFFEA5457);
  static const c500 = Color(0xFFE12E31);
  static const c600 = Color(0xFFC11F22);
  static const c700 = Color(0xFF9A171A);

  static const ink950 = Color(0xFF080A0D);
  static const ink900 = Color(0xFF0D1117);
  static const ink800 = Color(0xFF171E29);
  static const ink700 = Color(0xFF212A38);
  static const ink600 = Color(0xFF2E3A4A);

  static const sand50 = Color(0xFFFAF8F5);
  static const sand100 = Color(0xFFF3EFE9);
  static const sand200 = Color(0xFFE9E2D8);

  static const slate900 = Color(0xFF0F172A);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate100 = Color(0xFFF1F5F9);
}

class AppRadius {
  static const card = 22.0;
  static const field = 14.0;
  static const pill = 999.0;
}

class AppFont {
  static const display = 'Sora';
  static const sans = 'Inter';
}

/// Colores semánticos que no caben en un ColorScheme.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.ok,
    required this.warn,
    required this.danger,
    required this.info,
    required this.onStatus,
    required this.muted,
    required this.field,
    required this.border,
    required this.elevated,
  });

  final Color ok;
  final Color warn;
  final Color danger;
  final Color info;
  final Color onStatus;
  final Color muted;
  final Color field;
  final Color border;
  final bool elevated;

  List<BoxShadow> get shadows => elevated
      ? [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 2.r, offset: Offset(0, 1.r)),
          BoxShadow(color: Color(0x0F0F172A), blurRadius: 24.r, offset: Offset(0, 8.r)),
        ]
      : [];

  static const light = AppColors(
    ok: Color(0xFF059669),
    warn: Color(0xFFD97706),
    danger: Brand.c600,
    info: Color(0xFF2563EB),
    onStatus: Colors.white,
    muted: Brand.slate500,
    field: Brand.sand100,
    border: Color(0xFFE7E1D8),
    elevated: true,
  );

  static const dark = AppColors(
    ok: Color(0xFF34D399),
    warn: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
    onStatus: Brand.ink950,
    muted: Brand.slate400,
    field: Brand.ink800,
    border: Brand.ink700,
    elevated: false,
  );

  @override
  AppColors copyWith({
    Color? ok,
    Color? warn,
    Color? danger,
    Color? info,
    Color? onStatus,
    Color? muted,
    Color? field,
    Color? border,
    bool? elevated,
  }) {
    return AppColors(
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      onStatus: onStatus ?? this.onStatus,
      muted: muted ?? this.muted,
      field: field ?? this.field,
      border: border ?? this.border,
      elevated: elevated ?? this.elevated,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      field: Color.lerp(field, other.field, t)!,
      border: Color.lerp(border, other.border, t)!,
      elevated: t < 0.5 ? elevated : other.elevated,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.c500,
      brightness: Brightness.light,
    ).copyWith(
      primary: Brand.c500,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: Brand.slate900,
    );
    return _base(scheme, Brand.sand100, AppColors.light);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.c500,
      brightness: Brightness.dark,
    ).copyWith(
      primary: Brand.c400,
      onPrimary: Colors.white,
      surface: Brand.ink900,
      onSurface: Brand.slate100,
    );
    return _base(scheme, Brand.ink950, AppColors.dark);
  }

  static ThemeData _base(ColorScheme scheme, Color bg, AppColors colors) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field.r),
      borderSide: BorderSide(color: colors.border),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: AppFont.sans,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFont.display,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.field,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 14.r),
        labelStyle: TextStyle(color: colors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(64.r, 52.r),
          shape: StadiumBorder(),
          textStyle: TextStyle(
            fontFamily: AppFont.sans,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(64.r, 48.r),
          shape: StadiumBorder(),
          side: BorderSide(color: colors.border, width: 1.4),
          textStyle: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card.r)),
        titleTextStyle: TextStyle(
          fontFamily: AppFont.display,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(fontSize: 15, height: 1.45, color: colors.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card.r)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// Claro por defecto, igual que el portal. La preferencia se guarda en el equipo.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString(_key) == 'dark') _mode = ThemeMode.dark;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, isDark ? 'dark' : 'light');
    } catch (_) {}
  }
}

final themeController = ThemeController();
