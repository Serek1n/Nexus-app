import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';
import '../l10n.dart';

/// Фон: ровный тёмный цвет и едва заметный свет сверху.
/// Когда соединение активно, свет становится зелёным.
class NeonBackground extends StatelessWidget {
  const NeonBackground({super.key, required this.child, this.live = false});
  final Widget child;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: NX.bg),
        // Сезон: закатное небо, солнце, горизонт и пальмы — за интерфейсом.
        if (NX.season)
          const RepaintBoundary(child: CustomPaint(painter: _SunsetPainter())),
        AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.1),
              radius: 1.1,
              colors: [
                (live ? NX.mint : NX.violet).withValues(alpha: 0.07),
                Colors.transparent,
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Фон сезонного оформления «Неоновый закат». Рисуется один раз, без
/// анимации: интерфейс поверх него остаётся читаемым (всё приглушено).
class _SunsetPainter extends CustomPainter {
  const _SunsetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.74;

    // Небо: ночь сверху, малиновое зарево к горизонту.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF130A20),
            Color(0xFF1E0C30),
            Color(0xFF3A1240),
            Color(0xFF1A0B26),
          ],
          stops: [0, 0.45, 0.74, 1],
        ).createShader(Offset.zero & size),
    );

    // Солнце с прорезями — ретро-закат.
    final r = (w < h ? w : h * 0.8) * 0.3;
    final sun = Rect.fromCircle(center: Offset(w / 2, horizon), radius: r);
    canvas.saveLayer(sun.inflate(2), Paint());
    canvas.drawCircle(
      sun.center,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66FFD25E), Color(0x66FF7A3D), Color(0x55FF3E8E)],
        ).createShader(sun),
    );
    final cut = Paint()..blendMode = BlendMode.clear;
    for (var i = 0; i < 6; i++) {
      final y = horizon - r * 0.55 + i * r * 0.11;
      canvas.drawRect(
          Rect.fromLTWH(sun.left, y, sun.width, 2.0 + i * 1.6), cut);
    }
    canvas.restore();

    // Ночное море: ниже горизонта темнее, с отблеском.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()..color = const Color(0xE6120820),
    );
    for (var i = 0; i < 7; i++) {
      final y = horizon + 8 + i * i * 2.6;
      final half = r * (0.9 - i * 0.1);
      canvas.drawLine(
        Offset(w / 2 - half, y),
        Offset(w / 2 + half, y),
        Paint()
          ..color = Color.fromARGB(70 - i * 8, 0xFF, 0x6A, 0x9E)
          ..strokeWidth = 1.4,
      );
    }

    // Неоновая линия горизонта.
    final line = Paint()
      ..color = const Color(0x99FF5FA2)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, horizon), Offset(w, horizon), line);
    canvas.drawLine(
      Offset(0, horizon),
      Offset(w, horizon),
      Paint()
        ..color = const Color(0x40FF5FA2)
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Пальмы по краям — силуэты.
    final s = (h * 0.42).clamp(160.0, 420.0);
    _palm(canvas, Offset(w * 0.06, h), s, 0.18);
    _palm(canvas, Offset(w * 0.94, h), s * 0.86, -0.22);
    if (w > 700) _palm(canvas, Offset(w * 0.16, h), s * 0.62, 0.05);
  }

  /// Пальма: изогнутый ствол и веер листьев из основания [base].
  void _palm(Canvas c, Offset base, double size, double lean) {
    final dark = Paint()
      ..color = const Color(0xFF0A0512)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final top = base + Offset(size * lean * 1.4, -size);
    final trunk = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(base.dx + size * lean * 0.2, base.dy - size * 0.55,
          top.dx, top.dy);
    c.drawPath(trunk, dark..strokeWidth = size * 0.045);
    final leaf = Paint()..color = const Color(0xFF0A0512);
    for (final a in [-2.7, -2.25, -1.8, -1.35, -0.9, -0.45, -0.05]) {
      final len = size * (0.42 + 0.06 * (a.abs() % 1));
      final tip = top + Offset(len * _cos(a), len * _sin(a) + len * 0.35);
      final mid = top + Offset(len * 0.55 * _cos(a), len * 0.55 * _sin(a) - len * 0.08);
      final n = Offset(-_sin(a), _cos(a)) * (size * 0.035);
      c.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(mid.dx + n.dx, mid.dy + n.dy, tip.dx, tip.dy)
          ..quadraticBezierTo(mid.dx - n.dx, mid.dy - n.dy, top.dx, top.dy),
        leaf,
      );
    }
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(covariant _SunsetPainter old) => false;
}

/// Карточка: сплошная поверхность и тонкая граница.
/// Кольцо вокруг элемента, выбранного пультом телевизора или клавиатурой.
/// Подсветка InkWell у карточек скрыта их фоном, а у фиолетовых кнопок
/// сливается с цветом — поэтому рисуем рамку поверх.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.radius = 16});
  final Widget child;
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final show = _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: show ? NX.violet : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.active = false,
    Color? accent,
    this.radius = 16,
  }) : _accent = accent;

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;
  final Color? _accent;
  Color get accent => _accent ?? NX.violet;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    // Фон и рамку рисует сам Material: подсветка выбора (пульт, мышь)
    // у этой карточки и у строк внутри неё видна поверх фона, а не под ним.
    // Смену цвета Material анимирует сам.
    final card = Material(
      color: active
          ? Color.alphaBlend(accent.withValues(alpha: 0.07), NX.surface)
          : NX.surface,
      shape: RoundedRectangleBorder(
        borderRadius: br,
        side: BorderSide(
            color: active ? accent.withValues(alpha: 0.55) : NX.stroke),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: br,
        splashColor: accent.withValues(alpha: 0.08),
        highlightColor: NX.hover,
        hoverColor: NX.hover,
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null && onLongPress == null
        ? card
        : FocusRing(radius: radius, child: card);
  }
}

/// Текст с градиентной заливкой (используется точечно).
class GradientText extends StatelessWidget {
  const GradientText(this.text,
      {super.key, required this.style, Gradient? gradient})
      : _gradient = gradient;
  final String text;
  final TextStyle style;
  final Gradient? _gradient;
  Gradient get gradient => _gradient ?? NX.neon;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => gradient.createShader(r),
        child: Text(text, style: style),
      );
}

/// Логотип: знак + спокойная надпись.
class NexusLogo extends StatelessWidget {
  const NexusLogo({super.key, this.size = 28, this.showText = true});
  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icon/logo_mark.png',
              width: size, height: size, filterQuality: FilterQuality.medium),
          if (showText) ...[
            const SizedBox(width: 8),
            Text('Nexus',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.68,
                  letterSpacing: -0.2,
                  color: NX.text,
                )),
          ],
        ],
      );
}

/// Задержка: индикатор-«антенна» (3 деления) и число.
class PingBadge extends StatelessWidget {
  const PingBadge({super.key, required this.ping, this.loading = false});
  final int? ping;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: NX.text3),
      );
    }
    final p = ping;
    final c = NX.pingColor(p);
    final bars = NX.pingLevel(p);
    final txt = p == null ? tr('— мс') : (p < 0 ? tr('нет связи') : tr('{0} мс', [p]));
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++) ...[
          Container(
            width: 3,
            height: 4.0 + i * 3,
            decoration: BoxDecoration(
              color: i < bars ? c : NX.text3.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 2) const SizedBox(width: 1.5),
        ],
        const SizedBox(width: 7),
        Text(txt,
            style: TextStyle(
                color: p == null ? NX.text3 : c,
                fontSize: NXFont.sub,
                height: 1,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

/// Аватар сервера: флаг страны (картинкой — одинаково на Android и Windows,
/// где нет цветных флагов-эмодзи) или первая буква названия.
class ServerAvatar extends StatelessWidget {
  const ServerAvatar({super.key, required this.server, this.size = 40});
  final ServerProfile server;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = server.countryCode;
    final radius = BorderRadius.circular(size * 0.3);

    Widget letters(String text, Color color) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: code != null ? color.withValues(alpha: 0.16) : NX.surface2,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: code != null ? size * 0.32 : size * 0.4,
              letterSpacing: code != null ? 0.5 : 0,
              color: color,
            ),
          ),
        );

    if (code == null) {
      // Название — просто номер («0863»): буква «0» ничего не говорит,
      // показываем значок сервера.
      if (server.nameIsBare) {
        return Container(
          width: size,
          height: size,
          decoration:
              BoxDecoration(borderRadius: radius, color: NX.surface2),
          child: Icon(Icons.public_rounded,
              size: size * 0.5, color: NX.text3),
        );
      }
      return letters(server.cleanName.characters.first.toUpperCase(), NX.text2);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: NX.strokeStrong),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          'assets/flags/$code.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          // Нет картинки для этого кода — показываем буквы.
          errorBuilder: (_, __, ___) =>
              letters(code.toUpperCase(), _tint(code.toUpperCase())),
        ),
      ),
    );
  }
}

/// Устойчивый цвет для кода страны — каждая страна своим оттенком палитры.
Color _tint(String code) {
  final palette = [NX.violet, NX.cyan, NX.mint, NX.amber, NX.pink, NX.indigo];
  final h = code.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
  return palette[h % palette.length];
}

/// Небольшая метка (протокол, статус).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, Color? color}) : _color = color;
  final String text;
  final Color? _color;
  Color get color => _color ?? NX.text2;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.12),
        ),
        child: Text(text,
            style: TextStyle(
                // На светлом фоне яркие оттенки (бирюзовый, мятный) почти
                // сливаются с подложкой — текст метки делаем темнее.
                color: NX.ink(color),
                fontSize: NXFont.micro,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      );
}

/// Основная кнопка: сплошной акцент, без свечения.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.secondary = false,
    this.danger = false,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback? onPressed;

  /// Выбрана сразу (пульт телевизора).
  final bool autofocus;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final bool secondary;

  /// Опасное действие (сброс, удаление) — красный текст на тёмной плашке.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final fg = danger
        ? NX.red
        : secondary
            ? NX.text
            : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: FocusRing(
      radius: 12,
      child: Material(
        color: danger
            ? NX.red.withValues(alpha: 0.1)
            : secondary
                ? NX.surface2
                : NX.action,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          autofocus: autofocus,
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: fg))
                else if (icon != null)
                  Icon(icon, size: 18, color: fg),
                if (loading || icon != null) const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w700, fontSize: NXFont.title)),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Подпись раздела.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Text(text,
                style: TextStyle(
                  color: NX.text2,
                  fontSize: NXFont.body,
                  fontWeight: FontWeight.w700,
                )),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Заголовок страницы.
class PageHeader extends StatelessWidget {
  const PageHeader(
      {super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: NXFont.h1,
                          letterSpacing: -0.4,
                          height: 1.15)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!,
                        style: TextStyle(color: NX.text2, fontSize: NXFont.body)),
                  ],
                ],
              ),
            ),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              actions[i],
            ],
          ],
        ),
      );
}

/// Кнопка-иконка.
class NxIconButton extends StatelessWidget {
  const NxIconButton(
      {super.key,
      required this.icon,
      required this.onPressed,
      this.tooltip,
      this.spinning = false});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: NX.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: spinning ? null : onPressed,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NX.stroke),
          ),
          alignment: Alignment.center,
          child: spinning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon,
                  size: 19, color: onPressed == null ? NX.text3 : NX.text),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Пустое состояние.
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.text,
      this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: NX.surface2,
                ),
                child: Icon(icon, color: NX.text2, size: 26),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: NXFont.h3)),
              const SizedBox(height: 6),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NX.text2, height: 1.45)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}
