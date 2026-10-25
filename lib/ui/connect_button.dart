import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// Кнопка подключения: спокойный круг; при подключении — зелёная заливка
/// и мягкое свечение, во время подключения — бегущая дуга.
class ConnectButton extends StatefulWidget {
  const ConnectButton(
      {super.key,
      required this.state,
      required this.onTap,
      this.size = 200,
      this.blocked = false});
  final ConnState state;

  /// Kill switch сработал — кнопка красная.
  final bool blocked;
  final VoidCallback onTap;
  final double size;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  bool _pressed = false;

  bool get _busy =>
      widget.state == ConnState.connecting ||
      widget.state == ConnState.disconnecting;
  bool get _on => widget.state == ConnState.connected && !widget.blocked;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ConnectButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_busy && !_spin.isAnimating) _spin.repeat();
    if (!_busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final fill = _on ? NX.mint : NX.surface2;
    final iconColor = widget.blocked
        ? NX.red
        : _on
            ? const Color(0xFF06261A)
            : (_busy ? NX.text : NX.text2);

    return Semantics(
      button: true,
      label: _on ? 'Отключить' : 'Подключить',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.state == ConnState.disconnecting ? null : widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: const Duration(milliseconds: 120),
            child: SizedBox(
              width: s,
              height: s,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Внешнее кольцо.
                  Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.blocked
                            ? NX.red.withValues(alpha: 0.3)
                            : _on
                                ? NX.mint.withValues(alpha: 0.25)
                                : NX.stroke,
                        width: 1,
                      ),
                    ),
                  ),
                  if (_busy)
                    AnimatedBuilder(
                      animation: _spin,
                      builder: (_, __) => CustomPaint(
                        size: Size(s, s),
                        painter: _ArcPainter(_spin.value),
                      ),
                    ),
                  // Основной круг.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: s * 0.74,
                    height: s * 0.74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: fill,
                      border: Border.all(
                        color: widget.blocked
                            ? NX.red.withValues(alpha: 0.6)
                            : _on
                                ? Colors.transparent
                                : NX.strokeStrong,
                      ),
                      boxShadow: _on ? NX.glow(NX.mint, strength: 1.2) : null,
                    ),
                    child: Icon(Icons.power_settings_new_rounded,
                        size: s * 0.24, color: iconColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = NX.violet;
    canvas.drawArc(rect.deflate(1.5), t * 2 * math.pi - math.pi / 2,
        math.pi * 0.6, false, p);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.t != t;
}
