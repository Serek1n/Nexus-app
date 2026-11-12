import 'package:flutter/material.dart';
import '../l10n.dart';

/// Палитра: строгий тёмный интерфейс, один акцент, неон — только в состоянии «подключено».
class NX {
  /// Светлая тема включена (меняется только при перестройке интерфейса).
  static bool light = false;

  // Нейтральные цвета — свои для тёмной и светлой темы.
  static Color get bg => light ? const Color(0xFFF4F4F8) : const Color(0xFF0B0B10);
  static Color get bg2 => light ? const Color(0xFFEDEDF3) : const Color(0xFF0F0F15);
  static Color get surface => light ? const Color(0xFFFFFFFF) : const Color(0xFF15151C);
  static Color get surface2 => light ? const Color(0xFFF0F0F5) : const Color(0xFF1D1D26);
  /// Выбранный чип: фиолетовый оттенок поверх фона.
  static Color get chipSelected =>
      light ? const Color(0xFFE6E1FF) : const Color(0xFF2A2547);

  /// Лёгкая подсветка при наведении/нажатии (белая на тёмном, чёрная на светлом).
  static Color get hover => light ? const Color(0x0A000000) : const Color(0x08FFFFFF);
  static Color get stroke => light ? const Color(0x14000000) : const Color(0x12FFFFFF);
  static Color get strokeStrong => light ? const Color(0x24000000) : const Color(0x22FFFFFF);

  static const violet = Color(0xFF8B7CF6);
  static const indigo = Color(0xFF6E68F0);
  static const cyan = Color(0xFF4FC9E3);
  static const mint = Color(0xFF3DDC97);
  static const pink = Color(0xFFF07AAE);
  static const amber = Color(0xFFF2B544);
  static const red = Color(0xFFF0566E);

  static Color get text => light ? const Color(0xFF16161D) : const Color(0xFFECECF1);
  static Color get text2 => light ? const Color(0xFF5A5A6A) : const Color(0xFF9C9CAD);
  // Третичный текст (подсказки, неактивные вкладки): контраст с фоном
  // не ниже 4,5:1 в обеих темах.
  static Color get text3 => light ? const Color(0xFF666675) : const Color(0xFF8A8A99);

  /// Заливка основной кнопки: белый текст на ней читается (4,8:1).
  static const action = Color(0xFF6E5CE6);

  /// Цвет для текста и значков: на светлом фоне яркие оттенки (мятный,
  /// жёлтый, бирюзовый) затемняются до контраста 4,5:1, на тёмном — как есть.
  static Color ink(Color c) {
    if (!light) return c;
    return _ink[c.toARGB32()] ??= () {
      var h = HSLColor.fromColor(c);
      while (h.lightness > 0.1 && _contrastOnWhite(h.toColor()) < 4.9) {
        h = h.withLightness(h.lightness - 0.02);
      }
      return h.toColor();
    }();
  }

  static final _ink = <int, Color>{};
  static double _contrastOnWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

  /// Предупреждение и «всё хорошо» — для текста и значков.
  static Color get warn => ink(amber);
  static Color get ok => ink(mint);

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
  /// Пороги — для «тёплой» задержки через сервер (см. DesktopCore._warmDelay).
  static int pingLevel(int? ping) {
    if (ping == null || ping < 0) return 0;
    if (ping < 350) return 3;
    if (ping < 700) return 2;
    return 1;
  }

  static Color pingColor(int? ping) {
    if (ping == null) return text3;
    return ink(switch (pingLevel(ping)) {
      3 => mint,
      2 => amber,
      _ => red,
    });
  }

  static List<BoxShadow> glow(Color c, {double strength = 1}) => [
        BoxShadow(
            color: c.withValues(alpha: 0.28 * strength),
            blurRadius: 40 * strength,
            spreadRadius: -6),
      ];
}

ThemeData buildTheme() {
  final scheme = (NX.light ? ColorScheme.light : ColorScheme.dark)(
    primary: NX.violet,
    secondary: NX.cyan,
    surface: NX.surface,
    error: NX.red,
    onPrimary: Colors.white,
    onSurface: NX.text,
    // Выбранные чипы (DNS, язык, таймер) — фиолетовый оттенок, а не голубая
    // заливка по умолчанию.
    secondaryContainer: NX.chipSelected,
    onSecondaryContainer: NX.text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: NX.light ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: NX.bg,
    fontFamily: NX.body,
    splashFactory: InkRipple.splashFactory,
    // Выбранный пультом/клавиатурой элемент хорошо виден (Android TV).
    focusColor: NX.violet.withValues(alpha: 0.24),
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
    dividerTheme: DividerThemeData(
      color: NX.light ? const Color(0x14000000) : const Color(0x1CFFFFFF),
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: NX.surface2,
      contentTextStyle:
          TextStyle(color: NX.text, fontFamily: NX.body, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: NX.strokeStrong),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NX.bg2,
      hintStyle: TextStyle(color: NX.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: NX.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: NX.stroke),
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
      // Выключенный переключатель — с тонкой обводкой, чтобы его было видно
      // на тёмной карточке.
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.transparent
              : NX.strokeStrong),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: NX.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: NX.stroke),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
    ),
    // Чипы в общем стиле: тёмная плашка и тонкая граница вместо белой
    // рамки Material по умолчанию.
    chipTheme: ChipThemeData(
      backgroundColor: NX.surface2,
      selectedColor: NX.chipSelected,
      checkmarkColor: NX.violet,
      deleteIconColor: NX.text2,
      labelStyle: TextStyle(
          color: NX.text,
          fontFamily: NX.body,
          fontWeight: FontWeight.w600,
          fontSize: 13.5),
      side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
          color: s.contains(WidgetState.selected)
              ? NX.violet.withValues(alpha: 0.6)
              : NX.strokeStrong)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      iconTheme: IconThemeData(color: NX.text2, size: 18),
      showCheckmark: true,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: NX.violet),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: NX.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NX.stroke),
      ),
      textStyle: TextStyle(color: NX.text, fontSize: 12),
    ),
  );
}

/// Форматирование байтов и скоростей.
String fmtBytes(num b) {
  if (b < 1024) return tr('{0} Б', [b.toInt()]);
  final units = [tr('КБ'), tr('МБ'), tr('ГБ'), tr('ТБ')];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String fmtSpeed(num bps) => tr('{0}/с', [fmtBytes(bps)]);

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return '${two(h)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String plural(int n, String one, String few, String many) {
  // По-английски форм две: 1 day / 2 days.
  if (L10n.en) return n == 1 ? one : many;
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}
