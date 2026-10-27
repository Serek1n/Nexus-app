import 'dart:convert';
import 'dart:math' as math;

/// Генератор QR-кода: байтовый режим, уровень коррекции M, версии 1–40.
/// Перенос алгоритма «QR Code generator» Project Nayuki (MIT) —
/// без сторонних пакетов.
class QrCode {
  QrCode._(this.size, this._m);

  final int size;
  final List<List<bool>> _m;

  /// Тёмный ли модуль (x — столбец, y — строка).
  bool dark(int x, int y) => _m[y][x];

  static const _ecc = [
    -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, //
    26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, //
    28, 28, 28, 28, 28,
  ];
  static const _blocks = [
    -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, //
    17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, //
    47, 49,
  ];

  static int _rawModules(int ver) {
    var r = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      final na = ver ~/ 7 + 2;
      r -= (25 * na - 10) * na - 55;
      if (ver >= 7) r -= 36;
    }
    return r;
  }

  static int _dataCodewords(int ver) =>
      _rawModules(ver) ~/ 8 - _ecc[ver] * _blocks[ver];

  /// QR-код для текста (UTF-8). Бросает [ArgumentError], если не влезает.
  factory QrCode.text(String text) {
    final data = utf8.encode(text);
    var ver = 1;
    for (;; ver++) {
      if (ver > 40) throw ArgumentError('Текст слишком длинный для QR-кода');
      final ccBits = ver <= 9 ? 8 : 16;
      if (4 + ccBits + data.length * 8 <= _dataCodewords(ver) * 8) break;
    }
    final ccBits = ver <= 9 ? 8 : 16;

    final bits = <int>[];
    void put(int val, int len) {
      for (var i = len - 1; i >= 0; i--) {
        bits.add((val >> i) & 1);
      }
    }

    put(4, 4); // байтовый режим
    put(data.length, ccBits);
    for (final b in data) {
      put(b, 8);
    }
    final cap = _dataCodewords(ver) * 8;
    put(0, math.min(4, cap - bits.length));
    put(0, (8 - bits.length % 8) % 8);
    for (var pad = 0xEC; bits.length < cap; pad ^= 0xEC ^ 0x11) {
      put(pad, 8);
    }
    final codewords = List<int>.filled(bits.length ~/ 8, 0);
    for (var i = 0; i < bits.length; i++) {
      codewords[i >> 3] |= bits[i] << (7 - (i & 7));
    }

    final q = _Builder(ver);
    q.drawFunctions();
    q.drawCodewords(_addEcc(codewords, ver));
    q.chooseMask();
    return QrCode._(q.size, q.m);
  }

  static List<int> _addEcc(List<int> data, int ver) {
    final numBlocks = _blocks[ver];
    final eccLen = _ecc[ver];
    final raw = _rawModules(ver) ~/ 8;
    final numShort = numBlocks - raw % numBlocks;
    final shortLen = raw ~/ numBlocks;
    final div = _rsDivisor(eccLen);
    final blocks = <List<int>>[];
    var k = 0;
    for (var i = 0; i < numBlocks; i++) {
      final len = shortLen - eccLen + (i < numShort ? 0 : 1);
      final dat = data.sublist(k, k + len);
      k += len;
      final ecc = _rsRemainder(dat, div);
      final block = [...dat];
      if (i < numShort) block.add(0);
      block.addAll(ecc);
      blocks.add(block);
    }
    final out = <int>[];
    for (var i = 0; i < blocks[0].length; i++) {
      for (var j = 0; j < blocks.length; j++) {
        if (i != shortLen - eccLen || j >= numShort) out.add(blocks[j][i]);
      }
    }
    return out;
  }

  static int _mul(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      z ^= ((y >> i) & 1) * x;
    }
    return z & 0xFF;
  }

  static List<int> _rsDivisor(int degree) {
    final r = List<int>.filled(degree, 0);
    r[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < r.length; j++) {
        r[j] = _mul(r[j], root);
        if (j + 1 < r.length) r[j] ^= r[j + 1];
      }
      root = _mul(root, 0x02);
    }
    return r;
  }

  static List<int> _rsRemainder(List<int> data, List<int> div) {
    final r = List<int>.filled(div.length, 0);
    for (final b in data) {
      final factor = b ^ r.removeAt(0);
      r.add(0);
      for (var i = 0; i < r.length; i++) {
        r[i] ^= _mul(div[i], factor);
      }
    }
    return r;
  }
}

class _Builder {
  _Builder(this.ver)
      : size = ver * 4 + 17,
        m = List.generate(ver * 4 + 17, (_) => List.filled(ver * 4 + 17, false)),
        fn = List.generate(ver * 4 + 17, (_) => List.filled(ver * 4 + 17, false));

  final int ver;
  final int size;
  final List<List<bool>> m;
  final List<List<bool>> fn;

  void _set(int x, int y, bool dark) {
    m[y][x] = dark;
    fn[y][x] = true;
  }

  void drawFunctions() {
    for (var i = 0; i < size; i++) {
      _set(6, i, i % 2 == 0);
      _set(i, 6, i % 2 == 0);
    }
    _finder(3, 3);
    _finder(size - 4, 3);
    _finder(3, size - 4);
    final pos = _alignPositions();
    final n = pos.length;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if ((i == 0 && j == 0) ||
            (i == 0 && j == n - 1) ||
            (i == n - 1 && j == 0)) {
          continue;
        }
        _alignment(pos[i], pos[j]);
      }
    }
    drawFormat(0);
    _version();
  }

  void _finder(int x, int y) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final d = math.max(dx.abs(), dy.abs());
        final xx = x + dx, yy = y + dy;
        if (xx >= 0 && xx < size && yy >= 0 && yy < size) {
          _set(xx, yy, d != 2 && d != 4);
        }
      }
    }
  }

  void _alignment(int x, int y) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        _set(x + dx, y + dy, math.max(dx.abs(), dy.abs()) != 1);
      }
    }
  }

  List<int> _alignPositions() {
    if (ver == 1) return const [];
    final n = ver ~/ 7 + 2;
    final step = ver == 32 ? 26 : ((ver * 4 + n * 2 + 1) ~/ (n * 2 - 2)) * 2;
    final r = <int>[6];
    for (var p = size - 7; r.length < n; p -= step) {
      r.insert(1, p);
    }
    return r;
  }

  void drawFormat(int mask) {
    final data = (0 << 3) | mask; // уровень M = 00
    var rem = data;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    final bits = ((data << 10) | rem) ^ 0x5412;
    bool b(int i) => ((bits >> i) & 1) != 0;
    for (var i = 0; i <= 5; i++) {
      _set(8, i, b(i));
    }
    _set(8, 7, b(6));
    _set(8, 8, b(7));
    _set(7, 8, b(8));
    for (var i = 9; i < 15; i++) {
      _set(14 - i, 8, b(i));
    }
    for (var i = 0; i < 8; i++) {
      _set(size - 1 - i, 8, b(i));
    }
    for (var i = 8; i < 15; i++) {
      _set(8, size - 15 + i, b(i));
    }
    _set(8, size - 8, true);
  }

  void _version() {
    if (ver < 7) return;
    var rem = ver;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    }
    final bits = (ver << 12) | rem;
    for (var i = 0; i < 18; i++) {
      final bit = ((bits >> i) & 1) != 0;
      final a = size - 11 + i % 3, c = i ~/ 3;
      _set(a, c, bit);
      _set(c, a, bit);
    }
  }

  void drawCodewords(List<int> data) {
    var i = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final x = right - j;
          final upward = ((right + 1) & 2) == 0;
          final y = upward ? size - 1 - vert : vert;
          if (!fn[y][x] && i < data.length * 8) {
            m[y][x] = ((data[i >> 3] >> (7 - (i & 7))) & 1) != 0;
            i++;
          }
        }
      }
    }
  }

  void _applyMask(int mask) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final inv = switch (mask) {
          0 => (x + y) % 2 == 0,
          1 => y % 2 == 0,
          2 => x % 3 == 0,
          3 => (x + y) % 3 == 0,
          4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
          5 => x * y % 2 + x * y % 3 == 0,
          6 => (x * y % 2 + x * y % 3) % 2 == 0,
          _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
        };
        if (inv && !fn[y][x]) m[y][x] = !m[y][x];
      }
    }
  }

  void chooseMask() {
    var best = 0, bestPenalty = 1 << 30;
    for (var mask = 0; mask < 8; mask++) {
      _applyMask(mask);
      drawFormat(mask);
      final p = _penalty();
      if (p < bestPenalty) {
        best = mask;
        bestPenalty = p;
      }
      _applyMask(mask); // XOR — повторное наложение снимает маску
    }
    _applyMask(best);
    drawFormat(best);
  }

  int _penalty() {
    var r = 0;
    bool at(int x, int y) => m[y][x];
    // 1: длинные одноцветные серии
    for (var line = 0; line < 2; line++) {
      for (var a = 0; a < size; a++) {
        var run = 1;
        for (var b = 1; b < size; b++) {
          final cur = line == 0 ? at(b, a) : at(a, b);
          final prev = line == 0 ? at(b - 1, a) : at(a, b - 1);
          if (cur == prev) {
            run++;
            if (run == 5) {
              r += 3;
            } else if (run > 5) {
              r++;
            }
          } else {
            run = 1;
          }
        }
      }
    }
    // 2: блоки 2×2
    for (var y = 0; y < size - 1; y++) {
      for (var x = 0; x < size - 1; x++) {
        final c = at(x, y);
        if (c == at(x + 1, y) && c == at(x, y + 1) && c == at(x + 1, y + 1)) {
          r += 3;
        }
      }
    }
    // 3: узоры, похожие на поисковые квадраты
    const pat = [true, false, true, true, true, false, true];
    for (var line = 0; line < 2; line++) {
      for (var a = 0; a < size; a++) {
        for (var b = 0; b + 7 <= size; b++) {
          var ok = true;
          for (var k = 0; k < 7 && ok; k++) {
            final v = line == 0 ? at(b + k, a) : at(a, b + k);
            ok = v == pat[k];
          }
          if (!ok) continue;
          bool light(int from, int to) {
            for (var k = from; k < to; k++) {
              if (k < 0 || k >= size) continue;
              if (line == 0 ? at(k, a) : at(a, k)) return false;
            }
            return true;
          }

          if (light(b - 4, b) || light(b + 7, b + 11)) r += 40;
        }
      }
    }
    // 4: баланс тёмных и светлых
    var darkCount = 0;
    for (final row in m) {
      for (final v in row) {
        if (v) darkCount++;
      }
    }
    final total = size * size;
    final k = ((darkCount * 20 - total * 10).abs() + total - 1) ~/ total - 1;
    r += k * 10;
    return r;
  }
}
