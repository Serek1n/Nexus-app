// ignore_for_file: invalid_use_of_visible_for_testing_member
// Снимки экранов Nexus для проверки дизайна (не входит в обычные тесты).
// Запуск: flutter test tool/screens/screens_test.dart --update-goldens
// Картинки появляются в tool/screens/out/.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexus/core/vpn_core.dart';
import 'package:nexus/l10n.dart';
import 'package:nexus/main.dart';
import 'package:nexus/models.dart';
import 'package:nexus/state/app_state.dart';
import 'package:nexus/ui/add_sheet.dart';

class FakeCore extends VpnCore {
  final _st = StreamController<ConnState>.broadcast();
  final _stats = StreamController<ConnStats>.broadcast();
  @override
  final List<String> logs = [];
  @override
  Stream<ConnState> get states => _st.stream;
  @override
  Stream<ConnStats> get stats => _stats.stream;
  @override
  Future<void> init() async {}
  @override
  Future<void> connect(
      {required String remark,
      required String config,
      required AppSettings settings}) async {
    _st.add(ConnState.connected);
    _stats.add(const ConnStats(
        downloadSpeed: 2400000,
        uploadSpeed: 180000,
        download: 1830000000,
        upload: 96000000));
  }

  @override
  Future<void> disconnect() async => _st.add(ConnState.disconnected);
  @override
  Future<int> ping(ServerProfile server, String config) async => 42;
  @override
  Future<String> coreVersion() async => 'Xray 26.10.31';
  @override
  Future<int> connectedDelay(ServerProfile server) async => 48;
  @override
  String? get activeProxy => null;
}

Future<void> _loadFonts() async {
  final m = FontLoader('Manrope');
  for (final w in [400, 500, 600, 700, 800]) {
    m.addFont(rootBundle.load('assets/fonts/Manrope-$w.ttf'));
  }
  await m.load();
  final dir = Platform.environment['MATERIAL_FONTS'];
  if (dir != null) {
    final f = File('$dir/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final i = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await i.load();
    }
  }
}

final _subs = [
  Subscription(
    id: 's1',
    url: 'https://nexuskvn.duckdns.org:2096/sub/demo',
    title: 'Nexus VPN',
    download: 182 * (1 << 30),
    upload: 12 * (1 << 30),
    total: 500 * (1 << 30),
    expire: DateTime.now().add(const Duration(days: 23)),
    updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  ),
  Subscription(
    id: 's2',
    url: 'https://nexorakvn.duckdns.org/sub/demo',
    title: 'Nexora VPN',
    download: 10 * (1 << 30),
    updatedAt: DateTime.now().subtract(const Duration(days: 2)),
  )..error = 'Сервер не отвечает',
];

ServerProfile _srv(String id, String name, String proto, int? ping,
        [String sub = 's1']) =>
    ServerProfile(
      id: id,
      link: 'vless://00000000-0000-0000-0000-000000000000@203.0.113.$id:443'
          '?security=reality&type=xhttp#$name',
      name: name,
      protocol: proto,
      host: '203.0.113.$id',
      port: 443,
      subscriptionId: sub,
      ping: ping,
    );

final _servers = [
  _srv('1', '🇫🇮 Финляндия', 'VLESS', 41),
  _srv('2', '🇳🇱 Нидерланды', 'VLESS', 63),
  _srv('3', '🇩🇪 Германия', 'Hysteria2', 58),
  _srv('4', '🇺🇸 США', 'VLESS', 148),
  _srv('5', '🇯🇵 Япония', 'Trojan', -1),
  _srv('6', '🇸🇪 Швеция', 'VLESS', 77, 's2'),
  _srv('7', '🇹🇷 Турция', 'VLESS', null, 's2'),
];

Future<AppState> _state({bool fresh = false, bool desktop = false}) async {
  SharedPreferences.setMockInitialValues({
    'settings':
        '{"language":"ru","onboarded":${!fresh},"autoUpdateOnStart":false,"autoConnectOnStart":false,'
            '"favorites":["🇳🇱 Нидерланды|203.0.113.2:443","🇩🇪 Германия|203.0.113.3:443"]}',
  });
  AppState.debugDesktop = desktop;
  final app = AppState.withCore(FakeCore());
  await app.init();
  if (!fresh) {
    app.subscriptions.addAll(_subs);
    app.servers.addAll(_servers);
    app.selectedId = '1';
  }
  return app;
}

Future<void> _shot(WidgetTester t, String name) async {
  // Картинки (флаги) декодируются асинхронно — даём им время.
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pump();
  }
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
}

void _size(WidgetTester t, double w, double h, [double dpr = 2]) {
  t.view.physicalSize = Size(w * dpr, h * dpr);
  t.view.devicePixelRatio = dpr;
}

Future<void> _tab(WidgetTester t, String label) async {
  await t.tap(find.text(label).last);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  for (final lang in ['ru']) {
    testWidgets('phone $lang', (t) async {
      L10n.apply(lang, lang);
      _size(t, 412, 915);
      final app = await t.runAsync(() => _state());
      await t.pumpWidget(NexusApp(state: app!));
      await _shot(t, 'phone_1_home');
      await t.runAsync(() => app.connect());
      await _shot(t, 'phone_2_home_connected');
      await _tab(t, tr('Серверы'));
      await _shot(t, 'phone_3_servers');
      await _tab(t, tr('Подписки'));
      await _shot(t, 'phone_4_subscriptions');
      await _tab(t, tr('Настройки'));
      _size(t, 412, 5200);
      await _shot(t, 'phone_5_settings');
      _size(t, 412, 915);
      await _tab(t, tr('Главная'));
      await t.runAsync(() => app.disconnect());
      await t.pumpWidget(const SizedBox());
      app.dispose();
    });
  }

  testWidgets('light', (t) async {
    _size(t, 412, 915);
    final app = await t.runAsync(() => _state());
    app!.setTheme('light');
    await t.pumpWidget(NexusApp(state: app));
    await t.runAsync(() => app.connect());
    await _shot(t, 'light_1_home');
    await _tab(t, tr('Серверы'));
    await _shot(t, 'light_2_servers');
    await _tab(t, tr('Настройки'));
    _size(t, 412, 5600);
    await _shot(t, 'light_3_settings');
    _size(t, 412, 915);
    await _tab(t, tr('Подписки'));
    await _shot(t, 'light_4_subscriptions');
    showAddSheet(t.element(find.byType(Scaffold).first));
    await _shot(t, 'light_5_add_sheet');
    await t.runAsync(() => app.disconnect());
    app.setTheme('dark');
    await t.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('lock', (t) async {
    _size(t, 412, 915);
    final app = await t.runAsync(() => _state());
    await t.runAsync(() => app!.setPin('2580'));
    app!.locked = true;
    await t.pumpWidget(NexusApp(state: app));
    await _shot(t, 'phone_6_lock');
    await t.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('tablet', (t) async {
    _size(t, 1280, 800);
    final app = await t.runAsync(() => _state());
    await t.pumpWidget(NexusApp(state: app!));
    await t.runAsync(() => app.connect());
    await _shot(t, 'tablet_1_home');
    await t.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('onboarding', (t) async {
    _size(t, 412, 915);
    final app = await t.runAsync(() => _state(fresh: true));
    await t.pumpWidget(NexusApp(state: app!));
    await _shot(t, 'phone_0_onboarding');
    app.setTheme('light');
    await _shot(t, 'light_0_onboarding');
    app.setTheme('dark');
    await t.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('tv', (t) async {
    // Android TV: 1920×1080 при плотности 2 — 960×540 точек.
    _size(t, 960, 540);
    final app = await t.runAsync(() => _state());
    app!.isTv = true;
    debugPhoneLinkUrl =
        'http://192.168.1.42:41873/6d50d53856c64ad66c72fec4df875b64#NRuacqRli1MdiWRqw-zS47b2y0TNpwRmtD2uPG-AWbE';
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await t.pumpWidget(NexusApp(state: app));
    await t.pump(const Duration(milliseconds: 400));
    await _shot(t, 'tv_1_home');
    await t.runAsync(() => app.connect());
    await t.pump(const Duration(milliseconds: 400));
    await _shot(t, 'tv_2_home_connected');
    await _tab(t, tr('Серверы'));
    // Пультом: вниз несколько раз — выбор уходит на список серверов.
    for (var i = 0; i < 6; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(const Duration(milliseconds: 60));
    }
    await t.pump(const Duration(milliseconds: 300));
    await _shot(t, 'tv_3_servers_focus');
    await _tab(t, tr('Настройки'));
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump(const Duration(milliseconds: 60));
    }
    await t.pump(const Duration(milliseconds: 300));
    await _shot(t, 'tv_4_settings_focus');
    await _tab(t, tr('Подписки'));
    showAddSheet(t.element(find.byType(Scaffold).first));
    await t.pump(const Duration(milliseconds: 500));
    await _shot(t, 'tv_5_add_from_phone');
    await t.runAsync(() => app.disconnect());
    debugPhoneLinkUrl = null;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await t.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('desktop', (t) async {
    _size(t, 1180, 760, 1.25);
    final app = await t.runAsync(() => _state(desktop: true));
    await t.pumpWidget(NexusApp(state: app!));
    await t.runAsync(() => app.connect());
    await _shot(t, 'pc_1_home');
    await _tab(t, tr('Серверы'));
    await _shot(t, 'pc_2_servers');
    await _tab(t, tr('Настройки'));
    _size(t, 1180, 4200, 1.25);
    await _shot(t, 'pc_3_settings');
    await t.runAsync(() => app.disconnect());
    await t.pumpWidget(const SizedBox());
    app.dispose();
  });
}
