import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// Анимированный фон: тёмная сетка + плавающие неоновые пятна.
class NeonBackground extends StatefulWidget {
  const NeonBackground({super.key, required this.child, this.live = false});
  final Widget child;
  final bool live;

  @override
  State<NeonBackground> createState() => _NeonBackgroundState();
}

class _NeonBackgroundState extends State<NeonBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: NX.bg),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _OrbsPainter(_c.value, widget.live),
            ),
          ),
        ),
        const RepaintBoundary(child: CustomPaint(painter: _GridPainter())),
        widget.child,
      ],
    );
  }
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter(this.t, this.live);
  final double t;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    void orb(Offset c, double r, Color col, double op) {
      final p = Paint()
        ..shader = RadialGradient(colors: [
          col.withValues(alpha: op),
          col.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }

    final w = size.width, h = size.height;
    final r = math.max(w, h) * 0.55;
    orb(Offset(w * (0.15 + 0.08 * math.sin(a)), h * (0.12 + 0.05 * math.cos(a))),
        r, NX.violet, 0.22);
    orb(
        Offset(w * (0.9 + 0.06 * math.cos(a * 1.3)),
            h * (0.55 + 0.08 * math.sin(a))),
        r * 0.9,
        live ? NX.mint : NX.cyan,
        live ? 0.16 : 0.12);
    orb(Offset(w * (0.3 + 0.1 * math.cos(a)), h * (1.0 + 0.04 * math.sin(a))),
        r * 0.8, NX.indigo, 0.14);
  }

  @override
  bool shouldRepaint(covariant _OrbsPainter old) =>
      old.t != t || old.live != live;
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    const step = 36.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Полупрозрачная карточка с тонкой неоновой обводкой.
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.active = false,
    this.accent = NX.violet,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;
  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: active ? NX.glow(accent, strength: 0.6) : null,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: br,
              splashColor: accent.withValues(alpha: 0.12),
              highlightColor: accent.withValues(alpha: 0.06),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: br,
                  color: active
                      ? accent.withValues(alpha: 0.10)
                      : NX.surface.withValues(alpha: 0.78),
                  border: Border.all(
                    color: active
                        ? accent.withValues(alpha: 0.7)
                        : NX.stroke,
                    width: active ? 1.3 : 1,
                  ),
                ),
                child: child,
              ),
            ),
          ),
      ),
    );
  }
}

/// Текст с градиентной заливкой.
class GradientText extends StatelessWidget {
  const GradientText(this.text,
      {super.key, required this.style, this.gradient = NX.neon});
  final String text;
  final TextStyle style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => gradient.createShader(r),
        child: Text(text, style: style),
      );
}

/// Логотип Nexus: шестиугольник + надпись.
class NexusLogo extends StatelessWidget {
  const NexusLogo({super.key, this.size = 30, this.showText = true});
  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icon/logo_mark.png',
              width: size, height: size, filterQuality: FilterQuality.medium),
          if (showText) ...[
            const SizedBox(width: 10),
            GradientText('NEXUS',
                style: TextStyle(
                  fontFamily: NX.display,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.62,
                  letterSpacing: 3,
                )),
          ],
        ],
      );
}

/// Бейдж задержки.
class PingBadge extends StatelessWidget {
  const PingBadge({super.key, required this.ping, this.loading = false});
  final int? ping;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: NX.text3),
      );
    }
    final c = NX.pingColor(ping);
    final txt = ping == null ? '— мс' : (ping! < 0 ? 'нет связи' : '$ping мс');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(txt,
          style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// Аватар сервера: флаг или первая буква на неоновом фоне.
class ServerAvatar extends StatelessWidget {
  const ServerAvatar({super.key, required this.server, this.size = 42});
  final ServerProfile server;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flag = server.flag;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(colors: [
          NX.violet.withValues(alpha: 0.25),
          NX.cyan.withValues(alpha: 0.18),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: NX.strokeStrong),
      ),
      child: flag != null
          ? Text(flag, style: TextStyle(fontSize: size * 0.5))
          : Text(
              server.cleanName.characters.first.toUpperCase(),
              style: TextStyle(
                fontFamily: NX.display,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
                color: NX.text,
              ),
            ),
    );
  }
}

/// Маленькая «таблетка» с текстом (протокол, метки).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = NX.text2});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.1),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );
}

/// Кнопка с неоновым градиентом.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.secondary = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: 18, color: Colors.white),
        if (loading || icon != null) const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14.5)),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: secondary ? null : NX.neon,
          color: secondary ? NX.surface2 : null,
          border: secondary ? Border.all(color: NX.strokeStrong) : null,
          boxShadow:
              secondary || !enabled ? null : NX.glow(NX.violet, strength: 0.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Заголовок раздела.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(
          children: [
            Text(text.toUpperCase(),
                style: const TextStyle(
                  color: NX.text3,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
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
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: NX.display,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                          height: 1.1)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!,
                        style: const TextStyle(color: NX.text2, fontSize: 13.5)),
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
      );
}

/// Круглая иконка-кнопка в стиле Nexus.
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
      color: NX.surface.withValues(alpha: 0.7),
      shape: const CircleBorder(side: BorderSide(color: NX.stroke)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: spinning ? null : onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: spinning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 19, color: NX.text),
          ),
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
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NX.violet.withValues(alpha: 0.1),
                  border: Border.all(color: NX.violet.withValues(alpha: 0.4)),
                  boxShadow: NX.glow(NX.violet, strength: 0.4),
                ),
                child: Icon(icon, color: NX.violet, size: 30),
              ),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: NX.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 17)),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NX.text2, height: 1.45)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}
