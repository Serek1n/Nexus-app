import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

// Точечная карта для главного экрана: где находится сервер.
// Суша — по данным Natural Earth (общественное достояние), сетка 1,5°,
// широты от 80° с. ш. до 58° ю. ш. Каждая строка — 240 бит в hex.
const _cols = 240, _rows = 92;
const _step = 1.5, _lat0 = 80.0;
const _land = <String>[
  '00000000000030fffe3ffffffff00001fe000000000003f8000000000000',
  '0000000000040187f0ffffffffe00000730000000000000c000000000000',
  '0000000001f90effe07fffffffe0000000000000fc0003fff0000c000000',
  '00000000000f04ffe0007fffffe000000000000700003fffe0000f000000',
  '0000000007f0ceeff8001fffffc000000000001c0003ffffff3c02000000',
  '800000000f7fc7cffe001fffff80000000000038077ffffffffcaff00000',
  '000ffe80703ff1e7ffe01fffff80000007f800000fffffffffffffffe000',
  '807ffffffffff379c7e007fffe0000001fffc013ffffffffffffffffffff',
  'e03fffffffffffffc5fc0fffc00000007fffe6ffffffffffffffffffffff',
  'fcfffffffffffffe03ec0fff00fe0000fffe1fffffffffffffffffffffff',
  '081ffffffffffffbcff807f8007c0003fdfffffffffffffffffffffffffe',
  '003fffffffffffe0807803f00000000ff3ffffffffffffffffffffffffff',
  '007fffffffffffc00f8001f00000001ff3ffffffffffffffffffffffbff0',
  '001fd87fffffff800fc800000000001ff1fffffffffffffffffffffe1e00',
  '0001c00fffffffc00ffc000000000c0de0fffffffffffffffffffc007000',
  '00064001fffffff807fe000000000e06e3fffffffffffffffffff800f800',
  '00180000ffffffff8fff800000001e0783ffffffffffffffffffe000f000',
  '000000017fffffff9fffe0000000370ffffffffffffffffffffffc00e000',
  '000000003fffffffdfffe0000000379fffffffffffffffffffffff00c000',
  '000000001fffffffffffe000000007fffffffffffffffffffffffd000000',
  '000000000ffffffffff87000000001fffffffffffffffffffffffd000000',
  '0000000007fffffffff87800000007fffffffffffffffffffffff8000000',
  '0000000007ffffffffff0000000001ffffff7f9ffffffffffffff0000000',
  '0000000007ffffffffee0000000001ff3ff37e3fffffffffffffe3000000',
  '0000000007ffffffff80000000003ff99fe01f3fffffffffffffc7800000',
  '0000000007ffffffff80000000003fc0e7e71f9ffffffffffffe04000000',
  '0000000007fffffffe00000000003f06377fff9ffffffffffffc06000000',
  '0000000003fffffffc00000000003f00237fff8ffffffffffe1c06000000',
  '0000000003fffffffc00000000003e0a433fffcfffffffffff8c1c000000',
  '0000000001fffffffc000000000009fe0002ffffffffffffff0c7c000000',
  '0000000000fffffff000000000001ffe0000ffffffffffffff01f0000000',
  '00000000003fffffe000000000003fffc201ffffffffffffff8300000000',
  '00000000003fffffc000000000007fffe7ffffffffffffffff8000000000',
  '000000000017fff9c000000000007fffffffffffffffffffff8000000000',
  '00000000000fff00400000000000ffffffffffbfffffffffff8000000000',
  '00000000000dfe00600000000001fffffffeff9fffffffffff0000000000',
  '000000000005fe00000000000003fffffffe7fe5ffffffffff0000000000',
  '0000000000027e00000000000007ffffffff7ffe07fffffffe8000000000',
  '0000000000007e00f00000000007ffffffffbfff03fffffff00000000000',
  '0000000000003e0c0c0000000007ffffffffbffe01ffc7fe400000000000',
  '0000800000003f1c01c000000007ffffffff9ffe00ff83fec00000000000',
  '0000000000000ff8080000000007ffffffffcff8007f01fe00c000000000',
  '00000000000003f8000000000007ffffffffcfe0007e01ff00c000000000',
  '000000000000003f80000000000fffffffffefc0007c007f808000000000',
  '000000000000000f800000000007fffffffffe00003c007f80a000000000',
  '000000000000000301c000000007fffffffff8400038002f801000000000',
  '000000000000000187fe00000003ffffffffffc000180047016000000000',
  '0000000000000000ffff00000001ffffffffffc000140060003000000000',
  '00000000000000000fff80000000ffffffffff8000060020003000000000',
  '00000000000000000ffff80000007f9fffffff8000000018061000000000',
  '00000000000000000ffffc000000200fffffff00000000d80e0000000000',
  '00000000000000000ffffc0000000003fffffe00000000783e0000000000',
  '00000000000000001ffffe0000000003fffffc00000000387ea400000000',
  '00000000000000003fffff0000000003fffff800000000387e0480000000',
  '00000000000000003fffffc000000003fffff0000000001c7dc0d8000000',
  '00000000000000003ffffffc00000001ffffe0000000000e3dc2ff000000',
  '00000000000000003fffffff00000000ffffc0000000000600403f840000',
  '00000000000000003fffffff80000000ffffc0000000000300000fd90000',
  '00000000000000001fffffff80000000ffffc00000000001f8000fe00000',
  '00000000000000001fffffff800000007fffe00000000000009002300000',
  '00000000000000000fffffff000000007fffe00000000000000000000000',
  '00000000000000000ffffffe000000007fffe000000000000001e3000000',
  '000000000000000007fffffc00000000ffffe0c000000000000be3000000',
  '000000000000000003fffffc00000000ffffe1c000000000001fe3800000',
  '000000000000000001fffffc00000000ffffc78000000000003ffb800000',
  '0000000000000000007ffffc00000000ffff878000000000007fffc00002',
  '0000000000000000007ffffc00000000ffff07800000000000ffffe00000',
  '0000000000000000007ffff8000000007fff07000000000007fffff00200',
  '0000000000000000007ffff0000000007fff0700000000000ffffff80000',
  '0000000000000000007fff80000000007fff0700000000000ffffff80000',
  '0000000000000000007fff00000000003ffc0000000000000ffffffc0000',
  '0000000000000000007fff00000000003ffc0000000000000ffffffc0000',
  '000000000000000000fffe00000000001ffc0000000000000ffffffe0000',
  '000000000000000000fffe00000000001ff800000000000007fffffc0000',
  '000000000000000000fffc00000000000ff000000000000007fffffc0000',
  '000000000000000000fff800000000000fe000000000000007e03ff80000',
  '000000000000000000fff00000000000040000000000000006002ff80000',
  '000000000000000001ffc000000000000000000000000000000007f00008',
  '000000000000000001ffc000000000000000000000000000000007f0000e',
  '000000000000000001fe000000000000000000000000000000000000000e',
  '000000000000000001fc000000000000000000000000000000000020001c',
  '000000000000000003f80000000000000000000000000000000000600030',
  '000000000000000001f800000000000000000000000000000000000000e0',
  '000000000000000003f000000000000000000000000000000000000001c0',
  '000000000000000003f00000000000000000000000000000000000000080',
  '000000000000000003f00000000000000000000000000000000000000000',
  '000000000000000007e00000000000000000000002000000000000000000',
  '000000000000000003c08000000000000000000000000000000000000000',
  '000000000000000003e00000000000000000000000000000000000000000',
  '000000000000000001f00000000000000000000000000000000000000000',
  '000000000000000000000000000000000000000000000000000000000000',
  '000000000000000000000000000000000000000000000000000000000000',
];

final _bits = () {
  final b = List<List<bool>>.generate(_rows, (_) => List.filled(_cols, false));
  for (var r = 0; r < _rows; r++) {
    final hex = _land[r];
    for (var c = 0; c < _cols; c++) {
      final nib = int.parse(hex[c ~/ 4], radix: 16);
      b[r][c] = (nib >> (3 - c % 4)) & 1 == 1;
    }
  }
  return b;
}();

/// Город сервера по коду страны: столица или крупный узел дата-центров.
/// (широта, долгота, по-русски, по-английски).
const kCountryCity = <String, (double, double, String, String)>{
  'ru': (55.75, 37.62, 'Москва', 'Moscow'),
  'fi': (60.17, 24.94, 'Хельсинки', 'Helsinki'),
  'it': (45.46, 9.19, 'Милан', 'Milan'),
  'nl': (52.37, 4.9, 'Амстердам', 'Amsterdam'),
  'de': (50.11, 8.68, 'Франкфурт', 'Frankfurt'),
  'se': (59.33, 18.07, 'Стокгольм', 'Stockholm'),
  'no': (59.91, 10.75, 'Осло', 'Oslo'),
  'dk': (55.68, 12.57, 'Копенгаген', 'Copenhagen'),
  'pl': (52.23, 21.01, 'Варшава', 'Warsaw'),
  'lt': (54.69, 25.28, 'Вильнюс', 'Vilnius'),
  'lv': (56.95, 24.11, 'Рига', 'Riga'),
  'ee': (59.44, 24.75, 'Таллин', 'Tallinn'),
  'fr': (48.86, 2.35, 'Париж', 'Paris'),
  'gb': (51.51, -0.13, 'Лондон', 'London'),
  'ie': (53.35, -6.26, 'Дублин', 'Dublin'),
  'es': (40.42, -3.7, 'Мадрид', 'Madrid'),
  'pt': (38.72, -9.14, 'Лиссабон', 'Lisbon'),
  'ch': (47.38, 8.54, 'Цюрих', 'Zurich'),
  'at': (48.21, 16.37, 'Вена', 'Vienna'),
  'cz': (50.08, 14.44, 'Прага', 'Prague'),
  'sk': (48.15, 17.11, 'Братислава', 'Bratislava'),
  'hu': (47.5, 19.04, 'Будапешт', 'Budapest'),
  'ro': (44.43, 26.1, 'Бухарест', 'Bucharest'),
  'bg': (42.7, 23.32, 'София', 'Sofia'),
  'gr': (37.98, 23.73, 'Афины', 'Athens'),
  'rs': (44.79, 20.45, 'Белград', 'Belgrade'),
  'md': (47.01, 28.86, 'Кишинёв', 'Chisinau'),
  'ua': (50.45, 30.52, 'Киев', 'Kyiv'),
  'by': (53.9, 27.56, 'Минск', 'Minsk'),
  'tr': (41.01, 28.98, 'Стамбул', 'Istanbul'),
  'ge': (41.72, 44.79, 'Тбилиси', 'Tbilisi'),
  'am': (40.18, 44.51, 'Ереван', 'Yerevan'),
  'az': (40.41, 49.87, 'Баку', 'Baku'),
  'kz': (43.24, 76.89, 'Алматы', 'Almaty'),
  'uz': (41.3, 69.24, 'Ташкент', 'Tashkent'),
  'kg': (42.87, 74.59, 'Бишкек', 'Bishkek'),
  'us': (39.04, -77.49, 'Эшберн', 'Ashburn'),
  'ca': (43.65, -79.38, 'Торонто', 'Toronto'),
  'mx': (19.43, -99.13, 'Мехико', 'Mexico City'),
  'br': (-23.55, -46.63, 'Сан-Паулу', 'São Paulo'),
  'ar': (-34.6, -58.38, 'Буэнос-Айрес', 'Buenos Aires'),
  'cl': (-33.45, -70.67, 'Сантьяго', 'Santiago'),
  'jp': (35.68, 139.69, 'Токио', 'Tokyo'),
  'kr': (37.57, 126.98, 'Сеул', 'Seoul'),
  'hk': (22.32, 114.17, 'Гонконг', 'Hong Kong'),
  'tw': (25.03, 121.57, 'Тайбэй', 'Taipei'),
  'sg': (1.35, 103.82, 'Сингапур', 'Singapore'),
  'in': (19.08, 72.88, 'Мумбаи', 'Mumbai'),
  'ae': (25.2, 55.27, 'Дубай', 'Dubai'),
  'il': (32.09, 34.78, 'Тель-Авив', 'Tel Aviv'),
  'au': (-33.87, 151.21, 'Сидней', 'Sydney'),
  'nz': (-36.85, 174.76, 'Окленд', 'Auckland'),
  'za': (-26.2, 28.05, 'Йоханнесбург', 'Johannesburg'),
  'eg': (30.04, 31.24, 'Каир', 'Cairo'),
  'id': (-6.21, 106.85, 'Джакарта', 'Jakarta'),
  'my': (3.14, 101.69, 'Куала-Лумпур', 'Kuala Lumpur'),
  'th': (13.76, 100.5, 'Бангкок', 'Bangkok'),
  'vn': (21.03, 105.85, 'Ханой', 'Hanoi'),
  'ph': (14.6, 120.98, 'Манила', 'Manila'),
  'cy': (35.17, 33.36, 'Никосия', 'Nicosia'),
  'is': (64.15, -21.94, 'Рейкьявик', 'Reykjavik'),
  'lu': (49.61, 6.13, 'Люксембург', 'Luxembourg'),
  'be': (50.85, 4.35, 'Брюссель', 'Brussels'),
  'hr': (45.81, 15.98, 'Загреб', 'Zagreb'),
  'si': (46.06, 14.51, 'Любляна', 'Ljubljana'),
  'al': (41.33, 19.82, 'Тирана', 'Tirana'),
  'mk': (41.99, 21.43, 'Скопье', 'Skopje'),
  'ba': (43.86, 18.41, 'Сараево', 'Sarajevo'),
  'me': (42.44, 19.26, 'Подгорица', 'Podgorica'),
  'cn': (31.23, 121.47, 'Шанхай', 'Shanghai'),
  'sa': (24.71, 46.68, 'Эр-Рияд', 'Riyadh'),
  'qa': (25.29, 51.53, 'Доха', 'Doha'),
};

/// Карта вокруг сервера. [codes] — коды стран: первый — текущий сервер,
/// остальные — другие серверы (маленькие точки). [active] — подключено:
/// точка сервера расходится волнами.
class WorldMap extends StatefulWidget {
  const WorldMap({super.key, required this.codes, this.active = false});

  final List<String> codes;
  final bool active;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

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
    // Волны только при подключении — в покое карта не тратит батарею.
    // «Уменьшить движение» в системе — точка без бегущих волн.
    final still = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.active && !still && !_pulse.isAnimating) {
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
    final p = kCountryCity[widget.codes.isEmpty ? '' : widget.codes.first];
    // Центр карты — сервер; при смене сервера карта плавно переезжает.
    final target = Offset(p?.$2 ?? 20, (p?.$1 ?? 40).clamp(-35, 58).toDouble());
    return RepaintBoundary(
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: target),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
        // Два слоя: суша (≈1000 точек) перерисовывается только при сдвиге
        // карты, а волны — каждый кадр, но это пара кругов.
        builder: (_, center, __) => Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _MapPainter(
                land: true,
                codes: widget.codes,
                center: center,
                pulse: null,
                active: widget.active,
                dot: NX.text3,
                accent: widget.active ? NX.mint : NX.violet,
                other: NX.text2,
              ),
            ),
          ),
          CustomPaint(
            painter: _MapPainter(
              land: false,
              codes: widget.codes,
              center: center,
              pulse: _pulse,
              active: widget.active,
              dot: NX.text3,
              accent: widget.active ? NX.mint : NX.violet,
              other: NX.text2,
            ),
          ),
        ]),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.land,
    required this.codes,
    required this.center,
    required this.pulse,
    required this.active,
    required this.dot,
    required this.accent,
    required this.other,
  }) : super(repaint: pulse);

  /// true — слой суши, false — слой серверов и волн.
  final bool land;
  final List<String> codes;

  /// Центр вида: (долгота, широта).
  final Offset center;
  final Animation<double>? pulse;
  final bool active;
  final Color dot, accent, other;

  /// Сколько градусов долготы помещается в ширину карты.
  static const _spanLon = 72.0;

  @override
  void paint(Canvas canvas, Size size) {
    final ppd = size.width / _spanLon; // пикселей на градус
    final lon0 = center.dx - size.width / 2 / ppd;
    final lat0 = center.dy + size.height / 2 / ppd;
    Offset toPx(double lat, double lon) {
      var dl = lon - lon0;
      dl = ((dl % 360) + 360) % 360; // переход через 180°
      return Offset(dl * ppd, (lat0 - lat) * ppd);
    }

    final sp = codes.isEmpty ? null : kCountryCity[codes.first];
    final focus = sp == null ? null : toPx(sp.$1, sp.$2);
    final cell = _step * ppd;
    final r = cell * 0.3;
    if (!land) {
      _markers(canvas, toPx, focus, r);
      return;
    }
    final paint = Paint();
    // Суша: точки; рядом с сервером — ярче и в цвет сервера.
    final c0 = ((lon0 + 180) / _step).floor();
    final cn = (size.width / cell).ceil() + 1;
    for (var row = 0; row < _rows; row++) {
      final lat = _lat0 - (row + 0.5) * _step;
      final y = (lat0 - lat) * ppd;
      if (y < -cell || y > size.height + cell) continue;
      for (var k = 0; k < cn; k++) {
        final col = ((c0 + k) % _cols + _cols) % _cols;
        if (!_bits[row][col]) continue;
        final lon = -180 + (col + 0.5) * _step;
        final o = toPx(lat, lon);
        if (o.dx < -cell || o.dx > size.width + cell) continue;
        var t = 0.0;
        if (focus != null) {
          final d = (o - focus).distance / (size.shortestSide * 0.7);
          t = (1 - d).clamp(0.0, 1.0);
          t = t * t;
        }
        paint.color = Color.lerp(dot.withValues(alpha: 0.30), accent.withValues(alpha: 0.75), t * 0.6)!;
        canvas.drawCircle(o, r, paint);
      }
    }
  }

  void _markers(Canvas canvas, Offset Function(double, double) toPx,
      Offset? focus, double r) {
    // Другие серверы — маленькие точки.
    for (final code in codes.skip(1)) {
      final p = kCountryCity[code];
      if (p == null) continue;
      final o = toPx(p.$1, p.$2);
      canvas.drawCircle(o, r * 2.2, Paint()..color = other.withValues(alpha: 0.18));
      canvas.drawCircle(o, r * 1.3, Paint()..color = other.withValues(alpha: 0.75));
    }

    if (focus == null) return;
    // Текущий сервер: мягкое свечение, две волны и яркая точка.
    canvas.drawCircle(
        focus,
        r * 9,
        Paint()
          ..shader = RadialGradient(colors: [
            accent.withValues(alpha: 0.30),
            accent.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: focus, radius: r * 9)));
    if (active) {
      for (final ph in const [0.0, 0.5]) {
        final t = ((pulse?.value ?? 0) + ph) % 1.0;
        canvas.drawCircle(
            focus,
            r * (2.5 + 9 * t),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1.0, r * 0.5)
              ..color = accent.withValues(alpha: 0.55 * (1 - t)));
      }
    }
    canvas.drawCircle(focus, r * 2.6, Paint()..color = accent.withValues(alpha: 0.25));
    canvas.drawCircle(focus, r * 1.7, Paint()..color = accent);
    canvas.drawCircle(focus, r * 0.7, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_MapPainter o) =>
      o.land != land ||
      o.center != center || o.active != active || o.dot != dot ||
      o.accent != accent || o.codes.join() != codes.join();
}
