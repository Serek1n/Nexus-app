import 'package:flutter/material.dart';

/// Палитра: строгий тёмный интерфейс, один акцент, неон — только в состоянии «подключено».
class NX {
  static const bg = Color(0xFF0B0B10);
  static const bg2 = Color(0xFF0F0F15);
  static const surface = Color(0xFF15151C);
  static const surface2 = Color(0xFF1D1D26);
  static const stroke = Color(0x12FFFFFF);
  static const strokeStrong = Color(0x22FFFFFF);

  static const violet = Color(0xFF8B7CF6);
  static const indigo = Color(0xFF6E68F0);
  static const cyan = Color(0xFF4FC9E3);
  static const mint = Color(0xFF3DDC97);
  static const pink = Color(0xFFF07AAE);
  static const amber = Color(0xFFF2B544);
  static const red = Color(0xFFF0566E);

  static const text = Color(0xFFECECF1);
  static const text2 = Color(0xFF9C9CAD);
  static const text3 = Color(0xFF62626F);

  static const neon = LinearGradient(
    colors: [violet, indigo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const live = LinearGradient(
    colors: [mint, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const display = 'Manrope';
  static const body = 'Manrope';

  /// Оценка задержки: 3 — хорошо (зелёный), 2 — средне (жёлтый),
  /// 1 — плохо (красный), 0 — нет связи или не измерялась.
  /// Пороги — для «тёплой» задержки через сервер (см. WindowsCore._warmDelay).
  static int pingLevel(int? ping) {
    if (ping == null || ping < 0) return 0;
    if (ping < 200) return 3;
    if (ping < 500) return 2;
    return 1;
  }

  static Color pingColor(int? ping) {
    if (ping == null) return text3;
    return switch (pingLevel(ping)) {
      3 => mint,
      2 => amber,
      _ => red,
    };
  }

  static List<BoxShadow> glow(Color c, {double strength = 1}) => [
        BoxShadow(
            color: c.withValues(alpha: 0.28 * strength),
            blurRadius: 40 * strength,
            spreadRadius: -6),
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
    // Разделители тёмные, но различимые на карточках (в Material 3 по
    // умолчанию они почти белые).
    dividerTheme: const DividerThemeData(
      color: Color(0x1CFFFFFF),
      thickness: 1,
    ),
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
