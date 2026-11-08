"""Достаёт из большой гео-базы runetfreedom (geosite.dat, ~90 МБ) только
категорию ru-blocked — список заблокированных в России сайтов — и пишет её
в маленький файл nexus-blocked.dat для режима «Только заблокированное».

Формат geosite.dat — protobuf GeoSiteList { repeated GeoSite entry = 1; },
GeoSite { string country_code = 1; ... }. Записи копируются байт в байт.

Запуск: python3 tool/make_blocked_dat.py geosite.dat nexus-blocked.dat

Третий аргумент — свой список категорий через запятую (подходит и для
geoip.dat: формат GeoIPList тот же). Так для iOS собираются маленькие
базы только с нужными Nexus категориями — память VPN-расширения на
iPhone ограничена:
  python3 tool/make_blocked_dat.py geoip.dat out/geoip.dat ru,telegram,private
"""
import sys

# В консоли Windows кодировка cp1252 — русский текст в print() ронял сборку.
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except AttributeError:
    pass

WANT = {b"RU-BLOCKED"}


def varint(buf, i):
    shift = n = 0
    while True:
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        if b < 0x80:
            return n, i
        shift += 7


def main():
    src, dst = sys.argv[1], sys.argv[2]
    want = WANT
    if len(sys.argv) > 3:
        want = {c.strip().upper().encode() for c in sys.argv[3].split(",") if c.strip()}
    data = open(src, "rb").read()
    out = bytearray()
    found = []
    i = 0
    while i < len(data):
        start = i
        key, i = varint(data, i)
        if key != 0x0A:  # поле 1, длина
            raise SystemExit(f"неожиданный формат geosite.dat (ключ {key})")
        ln, i = varint(data, i)
        entry = data[i:i + ln]
        i += ln
        # Внутри GeoSite первое поле — country_code.
        if entry[:1] == b"\x0a":
            cl, j = varint(entry, 1)
            code = bytes(entry[j:j + cl]).upper()
            if code in want:
                out += data[start:i]
                found.append(code.decode())
    missing = {w.decode() for w in want} - set(found)
    if not found or (len(sys.argv) > 3 and missing):
        raise SystemExit(f"нет категорий: {', '.join(sorted(missing))}")
    open(dst, "wb").write(out)
    print(f"{dst}: {', '.join(found)} — {len(out)} байт")


if __name__ == "__main__":
    main()
