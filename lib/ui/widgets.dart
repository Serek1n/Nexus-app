import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

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
        const ColoredBox(color: NX.bg),
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

/// Карточка: сплошная поверхность и тонкая граница.
class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.active = false,
    this.accent = NX.violet,
    this.radius = 16,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: br,
        splashColor: accent.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        hoverColor: Colors.white.withValues(alpha: 0.02),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: active ? Color.alphaBlend(accent.withValues(alpha: 0.07), NX.surface) : NX.surface,
            border: Border.all(
              color: active ? accent.withValues(alpha: 0.55) : NX.stroke,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Текст с градиентной заливкой (используется точечно).
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

/// Задержка: цветная точка и число.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(txt,
            style: TextStyle(
                color: ping == null ? NX.text3 : NX.text2,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

/// Аватар сервера: флаг или первая буква.
class ServerAvatar extends StatelessWidget {
  const ServerAvatar({super.key, required this.server, this.size = 40});
  final ServerProfile server;
  final double size;

  @override
  Widget build(BuildContext context) {
    var flag = server.flag;
    // В Windows нет цветных флагов-эмодзи: показываем код страны («FI») аккуратным текстом.
    String? code;
    if (flag != null && Platform.isWindows) {
      code = String.fromCharCodes(flag.runes.map((r) => r - 0x1F1E6 + 65));
      flag = null;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: NX.surface2,
      ),
      child: flag != null
          ? Text(flag, style: TextStyle(fontSize: size * 0.5))
          : Text(
              code ?? server.cleanName.characters.first.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: code != null ? size * 0.32 : size * 0.4,
                letterSpacing: code != null ? 0.5 : 0,
                color: NX.text2,
              ),
            ),
    );
  }
}

/// Небольшая метка (протокол, статус).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = NX.text2});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color.withValues(alpha: 0.12),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 10.5,
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
    final fg = secondary ? NX.text : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: secondary ? NX.surface2 : NX.violet,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
                        color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
              ],
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
                style: const TextStyle(
                  color: NX.text2,
                  fontSize: 13,
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
                          fontSize: 26,
                          letterSpacing: -0.4,
                          height: 1.15)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!,
                        style: const TextStyle(color: NX.text2, fontSize: 13.5)),
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
                      fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 6),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NX.text2, height: 1.45)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}
