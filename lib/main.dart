import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'state/app_state.dart';
import 'ui/add_sheet.dart';
import 'ui/app_scope.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/servers_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/subscriptions_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1120, 720),
      minimumSize: Size(420, 640),
      center: true,
      title: 'Nexus',
      backgroundColor: NX.bg,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
  } else {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: NX.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  final state = AppState();
  runApp(NexusApp(state: state));
  await state.init();
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Nexus',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WindowListener {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  /// Закрытие окна: сначала гасим ядро и системный прокси.
  @override
  void onWindowClose() async {
    final app = AppScope.read(context);
    try {
      if (app.state != ConnState.disconnected) await app.core.disconnect();
    } catch (_) {}
    await windowManager.destroy();
  }

  static const _items = [
    (Icons.power_settings_new_rounded, 'Главная'),
    (Icons.dns_rounded, 'Серверы'),
    (Icons.workspace_premium_rounded, 'Подписки'),
    (Icons.tune_rounded, 'Настройки'),
  ];

  Widget _page(bool wide) => switch (_tab) {
        0 => HomeScreen(
            wide: wide,
            onOpenServers: () => setState(() => _tab = 1),
          ),
        1 => ServersScreen(
            onSelected: wide ? null : () => setState(() => _tab = 0)),
        2 => const SubscriptionsScreen(),
        _ => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final live = app.state == ConnState.connected;
    final wide = MediaQuery.sizeOf(context).width >= 860;

    final page = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_tab),
        child: wide && _tab != 0
            ? Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _page(wide),
                  ),
                ),
              )
            : _page(wide),
      ),
    );

    final body = wide
        ? Row(
            children: [
              _Sidebar(
                current: _tab,
                items: _items,
                onTap: (i) => setState(() => _tab = i),
              ),
              Expanded(child: page),
            ],
          )
        : Column(
            children: [
              Expanded(child: page),
              _BottomBar(
                current: _tab,
                items: _items,
                live: live,
                onTap: (i) => setState(() => _tab = i),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: NX.bg,
      body: NeonBackground(
        live: live,
        child: Column(
          children: [
            if (Platform.isWindows) const _TitleBar(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.current,
    required this.items,
    required this.onTap,
    required this.live,
  });
  final int current;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NX.bg2,
        border: Border(top: BorderSide(color: NX.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(items[i].$1,
                                size: 22,
                                color: current == i ? NX.text : NX.text3),
                            if (i == 0 && live)
                              Positioned(
                                right: -3,
                                top: -1,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                      color: NX.mint, shape: BoxShape.circle),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(items[i].$2,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: current == i ? NX.text : NX.text3,
                            )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar(
      {required this.current, required this.items, required this.onTap});
  final int current;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final live = app.state == ConnState.connected;
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: NX.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 24),
            child: NexusLogo(size: 28),
          ),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _SideItem(
                icon: items[i].$1,
                label: items[i].$2,
                active: current == i,
                onTap: () => onTap(i),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? NX.mint : NX.text3,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    live
                        ? (app.selected?.cleanName ?? 'Подключено')
                        : 'Не подключено',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: live ? NX.text : NX.text2,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          NeonButton(
            label: 'Добавить',
            icon: Icons.add_rounded,
            expand: true,
            onPressed: () => showAddSheet(context),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: active ? NX.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: active ? NX.text : NX.text3),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: active ? NX.text : NX.text2,
                    )),
              ],
            ),
          ),
        ),
      );
}

/// Собственная шапка окна на Windows (перетаскивание + кнопки).
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap, {bool close = false}) =>
        _TitleButton(icon: icon, onTap: onTap, close: close);
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          btn(Icons.remove_rounded, () => windowManager.minimize()),
          btn(Icons.crop_square_rounded, () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          }),
          btn(Icons.close_rounded, () => windowManager.close(), close: true),
        ],
      ),
    );
  }
}

class _TitleButton extends StatefulWidget {
  const _TitleButton(
      {required this.icon, required this.onTap, this.close = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool close;

  @override
  State<_TitleButton> createState() => _TitleButtonState();
}

class _TitleButtonState extends State<_TitleButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 38,
            color: _hover
                ? (widget.close ? NX.red : Colors.white.withValues(alpha: 0.08))
                : Colors.transparent,
            child: Icon(widget.icon,
                size: 16, color: _hover ? Colors.white : NX.text2),
          ),
        ),
      );
}
