import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// Большая неоновая кнопка подключения.
class ConnectButton extends StatefulWidget {
  const ConnectButton(
      {super.key, required this.state, required this.onTap, this.size = 230});
  final ConnState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat(reverse: true);
  bool _pressed = false;

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  bool get _busy =>
      widget.state == ConnState.connecting ||
      widget.state == ConnState.disconnecting;
  bool get _on => widget.state == ConnState.connected;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final accentA = _on ? NX.cyan : NX.violet;
    final accentB = _on ? NX.mint : NX.cyan;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: _busy && widget.state == ConnState.disconnecting
          ? null
          : widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 140),
          child: SizedBox(
            width: s,
            height: s,
            child: AnimatedBuilder(
              animation: Listenable.merge([_spin, _pulse]),
              builder: (_, __) {
                final p = Curves.easeInOut.transform(_pulse.value);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Внешнее свечение.
                    Container(
                      width: s * 0.78,
                      height: s * 0.78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accentA.withValues(
                                alpha: _on ? 0.35 + 0.2 * p : 0.18 + 0.08 * p),
                            blurRadius: _on ? 70 + 30 * p : 50,
                            spreadRadius: _on ? 6 + 10 * p : 0,
                          ),
                        ],
                      ),
                    ),
                    // Кольца.
                    CustomPaint(
                      size: Size(s, s),
                      painter: _RingsPainter(
                        spin: _spin.value,
                        pulse: p,
                        busy: _busy,
                        on: _on,
                        a: accentA,
                        b: accentB,
                      ),
                    ),
                    // Ядро кнопки.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: s * 0.56,
                      height: s * 0.56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: _on
                              ? [
                                  const Color(0xFF0E3B44),
                                  const Color(0xFF0A1C26),
                                ]
                              : [
                                  const Color(0xFF241A45),
                                  const Color(0xFF110D22),
                                ],
                        ),
                        border: Border.all(
                          color: accentA.withValues(alpha: 0.55),
                          width: 1.4,
                        ),
                      ),
                      child: Center(
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => LinearGradient(
                            colors: [accentA, accentB],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(r),
                          child: Icon(Icons.power_settings_new_rounded,
                              size: s * 0.22),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.spin,
    required this.pulse,
    required this.busy,
    required this.on,
    required this.a,
    required this.b,
  });
  final double spin, pulse;
  final bool busy, on;
  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Тонкая внешняя орбита с делениями.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 72; i++) {
      final ang = i * math.pi * 2 / 72;
      final len = i % 6 == 0 ? 7.0 : 3.0;
      final o1 = c + Offset(math.cos(ang), math.sin(ang)) * (r - 2);
      final o2 = c + Offset(math.cos(ang), math.sin(ang)) * (r - 2 - len);
      canvas.drawLine(o1, o2, tick);
    }

    // Основное кольцо.
    final ringR = r * 0.78;
    final rect = Rect.fromCircle(center: c, radius: ringR);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(c, ringR, base);

    final grad = SweepGradient(
      colors: [a.withValues(alpha: 0), a, b, a.withValues(alpha: 0)],
      stops: const [0, 0.45, 0.8, 1],
      transform: GradientRotation(spin * 2 * math.pi),
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = on ? 4 : 3.5
      ..shader = grad.createShader(rect);

    if (busy) {
      final start = spin * 2 * math.pi;
      canvas.drawArc(rect, start, math.pi * 1.2, false, arc);
    } else if (on) {
      final full = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..shader = SweepGradient(
          colors: [a, b, a],
          transform: GradientRotation(spin * 2 * math.pi),
        ).createShader(rect);
      canvas.drawCircle(c, ringR, full);
    } else {
      final idle = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = a.withValues(alpha: 0.35 + 0.25 * pulse);
      canvas.drawArc(rect, -math.pi / 2 + 0.5, math.pi * 2 - 1.0, false, idle);
    }

    // Внутреннее пунктирное кольцо (вращается в обратную сторону).
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = (on ? b : a).withValues(alpha: 0.35);
    final ir = r * 0.66;
    const dashes = 40;
    for (var i = 0; i < dashes; i++) {
      final s0 = i * 2 * math.pi / dashes - spin * math.pi * (busy ? 2 : 0.4);
      canvas.drawArc(Rect.fromCircle(center: c, radius: ir), s0,
          math.pi / dashes, false, inner);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter o) => true;
}
