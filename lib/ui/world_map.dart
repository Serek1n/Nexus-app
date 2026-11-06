import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

// Точечная карта мира для главного экрана: где находится сервер.
// Суша — по данным Natural Earth (общественное достояние), сетка 3°×3°,
// широты от 80° с. ш. до 56° ю. ш. Каждая строка — 120 бит в hex.
const _cols = 120, _rows = 45;
const _land = <String>[
  '0000000feffffc00f000000e000000',
  '0000173f80fffc000001807fc03000',
  '00003fbbe07ff800000617fffe3c00',
  '07ffffdffc3ff0003f00ffffffffff',
  'e7ffffffbe3f8e00ffffffffffffff',
  '07fffffdbc1c0603ffffffffffffff',
  '07fffff8380c0003dfffffffffff78',
  '0181fffc3e000023dfffffffffe0c0',
  '0000ffffbf800073ffffffffffe0c0',
  '00007fffffc0003ffffffffffff080',
  '00003ffffec0001ffffffffffff000',
  '00003fffff00001ffdf7ffffffd000',
  '00003ffff8000079fd77ffffff1000',
  '00001fffe000007057fbfffff62000',
  '00001fffe000003f07fffffff26000',
  '00000fffc000007f00fffffff18000',
  '000007ff8000007ffffffffff80000',
  '000003f0800001fffffffffff00000',
  '000000f0000001fffffe3ffff80000',
  '00000072600003ffff7f1fdf800000',
  '0000007e080003ffffbe0f1f080000',
  '00000007000003fffff80e0f080000',
  '00000001080003ffffe80607840000',
  '00000000ff0001fffff80600040000',
  '000000003fc000fffff00004200000',
  '000000003fe00001fff0000e600000',
  '000000007ff00001ffe00006f80000',
  '000000007ffe0001ffc0000268f000',
  '000000007fff0000ff800001003800',
  '000000003fff0000ff800000001400',
  '000000003fff0000ffc00000009000',
  '000000001ffe0000ffd8000007d000',
  '000000000ffe0000ff98000007f800',
  '000000000ffe0000ff3000003ffc00',
  '000000000ff800007f3000003ffe00',
  '000000000ff000007e0000003ffe00',
  '000000000fe000003c0000003ffe00',
  '000000000fe00000380000003c7e00',
  '000000001f80000000000000003c00',
  '000000001f00000000000000000002',
  '000000001e00000000000000000c04',
  '000000001c00000000000000000008',
  '000000001c00000000000000000000',
  '000000001800000000000000000000',
  '000000000c00000000000000000000',
];

bool _isLand(int r, int c) {
  final hex = _land[r];
  final nib = int.parse(hex[c ~/ 4], radix: 16);
  return (nib >> (3 - c % 4)) & 1 == 1;
}

/// Примерные координаты (широта, долгота) сервера по коду страны —
/// столица или крупный узел дата-центров.
const kCountryPoint = <String, (double, double)>{
  'ru': (55.8, 37.6), 'fi': (60.2, 24.9), 'it': (45.5, 9.2), 'nl': (52.4, 4.9),
  'de': (50.1, 8.7), 'se': (59.3, 18.1), 'no': (59.9, 10.8), 'dk': (55.7, 12.6),
  'pl': (52.2, 21.0), 'lt': (54.7, 25.3), 'lv': (56.9, 24.1), 'ee': (59.4, 24.8),
  'fr': (48.9, 2.35), 'gb': (51.5, -0.1), 'ie': (53.3, -6.3), 'es': (40.4, -3.7),
  'pt': (38.7, -9.1), 'ch': (47.4, 8.5), 'at': (48.2, 16.4), 'cz': (50.1, 14.4),
  'sk': (48.1, 17.1), 'hu': (47.5, 19.0), 'ro': (44.4, 26.1), 'bg': (42.7, 23.3),
  'gr': (38.0, 23.7), 'rs': (44.8, 20.5), 'md': (47.0, 28.9), 'ua': (50.4, 30.5),
  'by': (53.9, 27.6), 'tr': (41.0, 29.0), 'ge': (41.7, 44.8), 'am': (40.2, 44.5),
  'az': (40.4, 49.9), 'kz': (43.2, 76.9), 'uz': (41.3, 69.2), 'kg': (42.9, 74.6),
  'us': (39.0, -77.5), 'ca': (43.7, -79.4), 'mx': (19.4, -99.1), 'br': (-23.5, -46.6),
  'ar': (-34.6, -58.4), 'cl': (-33.4, -70.6), 'jp': (35.7, 139.7), 'kr': (37.6, 127.0),
  'hk': (22.3, 114.2), 'tw': (25.0, 121.5), 'sg': (1.35, 103.8), 'in': (19.1, 72.9),
  'ae': (25.2, 55.3), 'il': (32.1, 34.8), 'au': (-33.9, 151.2), 'nz': (-36.8, 174.8),
  'za': (-26.2, 28.0), 'eg': (30.0, 31.2), 'id': (-6.2, 106.8), 'my': (3.1, 101.7),
  'th': (13.8, 100.5), 'vn': (21.0, 105.8), 'ph': (14.6, 121.0), 'cy': (35.2, 33.4),
  'is': (64.1, -21.9), 'lu': (49.6, 6.1), 'be': (50.8, 4.4), 'hr': (45.8, 16.0),
  'si': (46.1, 14.5), 'al': (41.3, 19.8), 'mk': (42.0, 21.4), 'ba': (43.9, 18.4),
  'me': (42.4, 19.3), 'cn': (31.2, 121.5), 'sa': (24.7, 46.7), 'qa': (25.3, 51.5),
};

Offset? _pos((double, double)? p, Size size) {
  if (p == null) return null;
  final x = (p.$2 + 180) / 360 * size.width;
  final y = (80 - p.$1) / 136 * size.height;
  return Offset(x, y);
}

/// Карта с отмеченными серверами. [active] — подключено (точка «дышит»).
class WorldMap extends StatefulWidget {
  const WorldMap({super.key, required this.codes, this.active = false});

  /// Коды стран серверов (первый — текущий).
  final List<String> codes;
  final bool active;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WorldMap old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // Анимация только при подключении — в покое карта не тратит батарею.
    if (widget.active && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: _cols / (_rows * 1.0),
        child: CustomPaint(
          painter: _MapPainter(
            codes: widget.codes,
            active: widget.active,
            pulse: _pulse,
            dot: NX.text3.withValues(alpha: NX.light ? 0.35 : 0.28),
            accent: widget.active ? NX.mint : NX.violet,
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.codes,
    required this.active,
    required this.pulse,
    required this.dot,
    required this.accent,
  }) : super(repaint: pulse);

  final List<String> codes;
  final bool active;
  final Animation<double> pulse;
  final Color dot;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / _cols, ch = size.height / _rows;
    final r = math.min(cw, ch) * 0.28;
    final p = Paint()..color = dot;
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        if (_isLand(y, x)) {
          canvas.drawCircle(Offset((x + 0.5) * cw, (y + 0.5) * ch), r, p);
        }
      }
    }
    // Серверы: остальные из пула — маленькие точки, текущий — крупная
    // с ореолом (при подключении ореол расходится волной).
    for (var i = codes.length - 1; i >= 0; i--) {
      final o = _pos(kCountryPoint[codes[i]], size);
      if (o == null) continue;
      final main = i == 0;
      if (main) {
        final t = active ? pulse.value : 0.0;
        canvas.drawCircle(
            o,
            r * (4 + 10 * t),
            Paint()..color = accent.withValues(alpha: 0.35 * (1 - t)));
        canvas.drawCircle(o, r * 3.2,
            Paint()..color = accent.withValues(alpha: 0.25));
      }
      canvas.drawCircle(o, main ? r * 2 : r * 1.4,
          Paint()..color = main ? accent : accent.withValues(alpha: 0.6));
    }
  }

  @override
  bool shouldRepaint(_MapPainter o) =>
      o.active != active || o.dot != dot || o.accent != accent ||
      o.codes.join() != codes.join();
}
