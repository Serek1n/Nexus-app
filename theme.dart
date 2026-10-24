import 'package:flutter/material.dart';

/// Палитра «тёмный неон».
class NX {
  static const bg = Color(0xFF07060D);
  static const bg2 = Color(0xFF0C0A16);
  static const surface = Color(0xFF12101F);
  static const surface2 = Color(0xFF1A1730);
  static const stroke = Color(0x1FFFFFFF);
  static const strokeStrong = Color(0x33FFFFFF);

  static const violet = Color(0xFFA855F7);
  static const indigo = Color(0xFF6366F1);
  static const cyan = Color(0xFF22D3EE);
  static const mint = Color(0xFF2EF2B5);
  static const pink = Color(0xFFF472B6);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFFF4D6D);

  static const text = Color(0xFFF3F1FF);
  static const text2 = Color(0xFFA9A4C7);
  static const text3 = Color(0xFF6E6993);

  static const neon = LinearGradient(
    colors: [violet, indigo, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const live = LinearGradient(
    colors: [cyan, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const display = 'Unbounded';
  static const body = 'Manrope';

  static Color pingColor(int? ping) {
    if (ping == null) return text3;
    if (ping < 0) return red;
    if (ping < 150) return mint;
    if (ping < 400) return amber;
    return pink;
  }

  static List<BoxShadow> glow(Color c, {double strength = 1}) => [
        BoxShadow(
            color: c.withValues(alpha: 0.45 * strength),
            blurRadius: 28 * strength,
            spreadRadius: -4),
        BoxShadow(
            color: c.withValues(alpha: 0.25 * strength),
            blurRadius: 60 * strength,
            spreadRadius: -8),
      ];
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: NX.violet,
    secondary: NX.cyan,
    surface: NX.surface,
    error: NX.red,
    onPrimary: Colors.white,
    onSurface: NX.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: NX.bg,
    fontFamily: NX.body,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: NX.text,
      displayColor: NX.text,
      fontFamily: NX.body,
    ),
    dividerColor: NX.stroke,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: NX.surface2,
      contentTextStyle:
          const TextStyle(color: NX.text, fontFamily: NX.body, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: NX.strokeStrong),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NX.bg2,
      hintStyle: const TextStyle(color: NX.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NX.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NX.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NX.violet, width: 1.4),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : NX.text3),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? NX.violet : NX.surface2),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: NX.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: NX.stroke),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: NX.violet),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: NX.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NX.stroke),
      ),
      textStyle: const TextStyle(color: NX.text, fontSize: 12),
    ),
  );
}

/// Форматирование байтов и скоростей.
String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} Б';
  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String fmtSpeed(num bps) => '${fmtBytes(bps)}/с';

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${two(h)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}
