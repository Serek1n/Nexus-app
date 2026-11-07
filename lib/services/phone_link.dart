import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../l10n.dart';

/// «Отправить с телефона» для Android TV: на телевизоре нет камеры и
/// удобной клавиатуры, а ссылку на подписку из бота на него не скопировать.
///
/// Nexus на телевизоре поднимает в домашней сети временную страницу и
/// показывает QR-код с её адресом. Телефон сканирует код, открывает
/// страницу, вставляет ссылку — она приходит на телевизор.
///
/// Защита:
/// * в адресе случайный одноразовый путь; ключ — только в части после «#»,
///   которую браузер на сервер не отправляет;
/// * страница шифрует ссылку этим ключом и подписывает (HMAC-SHA256),
///   так что в сети ссылка не видна, а подделать отправку без ключа
///   нельзя;
/// * страница работает, только пока открыто окно добавления, принимает
///   одну ссылку и закрывается после неё, через 10 минут или после
///   серии неверных запросов.
class PhoneLink {
  PhoneLink._(this._srv, this.url, this._token, this._key);

  final HttpServer _srv;

  /// Адрес для QR-кода.
  final String url;
  final String _token;
  final List<int> _key;
  final _got = Completer<String>();
  Timer? _ttl;
  int _bad = 0;
  bool _stopped = false;

  /// Пришедшая с телефона ссылка (или ключ).
  Future<String> get received => _got.future;

  static Future<PhoneLink?> start({String? host}) async {
    final ip = host ?? await lanAddress();
    if (ip == null) return null;
    final HttpServer srv;
    try {
      srv = await HttpServer.bind(ip, 0);
    } catch (_) {
      return null;
    }
    final r = Random.secure();
    final token = _hex(List<int>.generate(16, (_) => r.nextInt(256)));
    final key = List<int>.generate(32, (_) => r.nextInt(256));
    final url =
        'http://$ip:${srv.port}/$token#${base64Url.encode(key).replaceAll('=', '')}';
    final link = PhoneLink._(srv, url, token, key);
    link._ttl = Timer(const Duration(minutes: 10), link.stop);
    srv.listen(link._handle, onError: (_) {});
    return link;
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _ttl?.cancel();
    unawaited(_srv.close(force: true));
  }

  /// IPv4-адрес в домашней сети (Wi-Fi или кабель).
  static Future<String?> lanAddress() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      String? best;
      for (final i in list) {
        final n = i.name.toLowerCase();
        if (n.startsWith('tun') || n.startsWith('ppp') || n.startsWith('rmnet')) {
          continue;
        }
        for (final a in i.addresses) {
          if (!isPrivate(a.address)) continue;
          if (n.startsWith('wlan') || n.startsWith('eth')) return a.address;
          best ??= a.address;
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  static bool isPrivate(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((x) => x == null || x < 0 || x > 255)) {
      return false;
    }
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Cache-Control', 'no-store')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Content-Security-Policy',
          "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'none'; base-uri 'none'");
    try {
      if (req.uri.path != '/$_token' || _got.isCompleted) {
        _strike();
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (req.method == 'GET') {
        res.headers.contentType = ContentType.html;
        res.write(page());
        return;
      }
      if (req.method != 'POST') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final body = await _readLimited(req, 64 * 1024);
      final text = body == null ? null : open(_key, body);
      if (text == null) {
        _strike();
        res.statusCode = HttpStatus.badRequest;
        return;
      }
      res.write('ok');
      if (!_got.isCompleted) _got.complete(text);
      Timer(const Duration(seconds: 1), stop);
    } catch (_) {
      res.statusCode = HttpStatus.badRequest;
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  /// Перебор адресов или подделка отправки — закрываем страницу.
  void _strike() {
    if (++_bad >= 20) stop();
  }

  static Future<String?> _readLimited(HttpRequest req, int max) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in req) {
      b.add(chunk);
      if (b.length > max) return null;
    }
    try {
      return utf8.decode(b.takeBytes());
    } catch (_) {
      return null;
    }
  }

  /// Проверяет подпись и расшифровывает «n=…&c=…&t=…». null — подделка.
  static String? open(List<int> key, String body) {
    final Map<String, String> q;
    try {
      q = Uri.splitQueryString(body.trim());
    } catch (_) {
      return null;
    }
    final n = _unhex(q['n']), c = _unhex(q['c']), t = _unhex(q['t']);
    if (n == null || c == null || t == null) return null;
    if (n.length != 16 || t.length != 32 || c.isEmpty || c.length > 16000) {
      return null;
    }
    final ek = sha256.convert([...utf8.encode('nexus-enc'), ...key]).bytes;
    final mk = sha256.convert([...utf8.encode('nexus-mac'), ...key]).bytes;
    final want = Hmac(sha256, mk).convert([...n, ...c]).bytes;
    var diff = 0;
    for (var i = 0; i < 32; i++) {
      diff |= want[i] ^ t[i];
    }
    if (diff != 0) return null;
    final p = Uint8List(c.length);
    for (var i = 0; i < c.length; i += 32) {
      final ctr = ByteData(4)..setUint32(0, i ~/ 32);
      final ks =
          sha256.convert([...ek, ...n, ...ctr.buffer.asUint8List()]).bytes;
      for (var j = 0; j < 32 && i + j < c.length; j++) {
        p[i + j] = c[i + j] ^ ks[j];
      }
    }
    try {
      final s = utf8.decode(p).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static List<int>? _unhex(String? s) {
    if (s == null || s.length.isOdd || s.length > 40000) return null;
    final r = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      final v = int.tryParse(s.substring(i, i + 2), radix: 16);
      if (v == null) return null;
      r.add(v);
    }
    return r;
  }

  static String _esc(String s) => const HtmlEscape().convert(s);

  static String _js(String s) => jsonEncode(s).replaceAll('<', r'<');

  /// Страница для телефона: без внешних файлов, шифрование — на месте.
  static String page() => '''<!doctype html>
<html lang="${_esc(L10n.lang)}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nexus</title>
<style>
:root{color-scheme:dark}
body{margin:0;background:#0d0d12;color:#ececf1;font:16px/1.45 system-ui,sans-serif;display:flex;justify-content:center}
main{width:100%;max-width:520px;padding:28px 20px}
h1{font-size:22px;margin:0 0 6px}
p{color:#9c9cad;margin:0 0 18px}
textarea{box-sizing:border-box;width:100%;min-height:120px;padding:14px;border-radius:14px;border:1px solid #2a2a35;background:#16161d;color:#ececf1;font:15px/1.4 ui-monospace,monospace;resize:vertical}
button{margin-top:14px;width:100%;padding:15px;border:0;border-radius:14px;background:#8b7cf6;color:#fff;font-weight:700;font-size:16px}
button:disabled{opacity:.5}
#s{margin-top:14px;min-height:22px}
.ok{color:#3ddc97}.err{color:#f0566e}
</style></head><body><main>
<h1>${_esc(tr('Отправить на телевизор'))}</h1>
<p>${_esc(tr('Вставьте ссылку на подписку или ключ сервера — она откроется в Nexus на телевизоре.'))}</p>
<textarea id="t" placeholder="https://… / vless://…" autofocus></textarea>
<button id="b">${_esc(tr('Отправить'))}</button>
<div id="s"></div>
</main><script>
function ror(x,n){return (x>>>n)|(x<<(32-n));}
function sha256(m){const K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];let H=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];const l=m.length,n=((l+9+63)>>6)<<6,b=new Uint8Array(n);b.set(m);b[l]=0x80;const v=new DataView(b.buffer);v.setUint32(n-4,(l*8)>>>0);v.setUint32(n-8,Math.floor(l/536870912));const w=new Uint32Array(64);for(let o=0;o<n;o+=64){for(let i=0;i<16;i++)w[i]=v.getUint32(o+i*4);for(let i=16;i<64;i++){const a=w[i-15],c=w[i-2];w[i]=w[i-16]+(ror(a,7)^ror(a,18)^(a>>>3))+w[i-7]+(ror(c,17)^ror(c,19)^(c>>>10));}let [a,bb,c,d,e,f,g,h]=H;for(let i=0;i<64;i++){const t1=(h+(ror(e,6)^ror(e,11)^ror(e,25))+((e&f)^(~e&g))+K[i]+w[i])|0,t2=((ror(a,2)^ror(a,13)^ror(a,22))+((a&bb)^(a&c)^(bb&c)))|0;h=g;g=f;f=e;e=(d+t1)|0;d=c;c=bb;bb=a;a=(t1+t2)|0;}H=[H[0]+a,H[1]+bb,H[2]+c,H[3]+d,H[4]+e,H[5]+f,H[6]+g,H[7]+h].map(x=>x|0);}const r=new Uint8Array(32),rv=new DataView(r.buffer);H.forEach((x,i)=>rv.setUint32(i*4,x>>>0));return r;}
function cat(...a){const r=new Uint8Array(a.reduce((s,x)=>s+x.length,0));let o=0;for(const x of a){r.set(x,o);o+=x.length;}return r;}
function hmac(k,m){const kb=new Uint8Array(64);kb.set(k);const i=kb.map(x=>x^0x36),o=kb.map(x=>x^0x5c);return sha256(cat(o,sha256(cat(i,m))));}
function hex(b){return Array.from(b,x=>x.toString(16).padStart(2,'0')).join('');}
function seal(key,text,nonce){const te=new TextEncoder(),ek=sha256(cat(te.encode('nexus-enc'),key)),mk=sha256(cat(te.encode('nexus-mac'),key)),p=te.encode(text),c=new Uint8Array(p.length);for(let i=0;i<p.length;i+=32){const ctr=new Uint8Array(4);new DataView(ctr.buffer).setUint32(0,i/32);const ks=sha256(cat(ek,nonce,ctr));for(let j=0;j<32&&i+j<p.length;j++)c[i+j]=p[i+j]^ks[j];}return 'n='+hex(nonce)+'&c='+hex(c)+'&t='+hex(hmac(mk,cat(nonce,c)));}
const S=document.getElementById('s'),B=document.getElementById('b');
function msg(t,c){S.textContent=t;S.className=c;}
function key(){try{const h=location.hash.slice(1).replace(/-/g,'+').replace(/_/g,'/');const b=atob(h+'='.repeat((4-h.length%4)%4));return Uint8Array.from(b,c=>c.charCodeAt(0));}catch(e){return null;}}
B.onclick=async()=>{const t=document.getElementById('t').value.trim(),k=key();
if(!t)return;if(!k||k.length!==32){msg(${_js(tr('Откройте страницу заново по QR-коду с телевизора'))},'err');return;}
B.disabled=true;msg('…','');
try{const r=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'text/plain'},body:seal(k,t,crypto.getRandomValues(new Uint8Array(16)))});
if(!r.ok)throw 0;msg(${_js(tr('Готово — смотрите на телевизор'))},'ok');document.getElementById('t').value='';}
catch(e){B.disabled=false;msg(${_js(tr('Не удалось отправить. Окно добавления на телевизоре должно быть открыто, а телефон — в той же сети Wi-Fi.'))},'err');}};
</script></body></html>''';
}
