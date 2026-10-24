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
      child: KeyedSubtree(key: ValueKey(_tab), child: _page(wide)),
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
        : Stack(
            children: [
              Positioned.fill(child: page),
              Positioned(
                left: 16,
                right: 16,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 14),
                  child: _BottomBar(
                    current: _tab,
                    items: _items,
                    live: live,
                    onTap: (i) => setState(() => _tab = i),
                  ),
                ),
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
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: NX.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NX.strokeStrong),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: current == i
                        ? LinearGradient(colors: [
                            NX.violet.withValues(alpha: 0.3),
                            NX.cyan.withValues(alpha: 0.15),
                          ])
                        : null,
                  ),
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
                              top: -2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: NX.mint,
                                  shape: BoxShape.circle,
                                  boxShadow: NX.glow(NX.mint, strength: 0.4),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(items[i].$2,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: current == i ? NX.text : NX.text3,
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
      width: 236,
      margin: const EdgeInsets.fromLTRB(14, 6, 0, 14),
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
      decoration: BoxDecoration(
        color: NX.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: NX.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: NexusLogo(size: 32),
          ),
          const SizedBox(height: 30),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SideItem(
                icon: items[i].$1,
                label: items[i].$2,
                active: current == i,
                onTap: () => onTap(i),
              ),
            ),
          const Spacer(),
          NeonCard(
            padding: const EdgeInsets.all(12),
            active: live,
            accent: NX.mint,
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? NX.mint : NX.text3,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    live
                        ? (app.selected?.cleanName ?? 'Подключено')
                        : 'Не подключено',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: active
                  ? LinearGradient(colors: [
                      NX.violet.withValues(alpha: 0.32),
                      NX.cyan.withValues(alpha: 0.08),
                    ])
                  : null,
              border: Border.all(
                  color: active
                      ? NX.violet.withValues(alpha: 0.5)
                      : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: active ? NX.text : NX.text3),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
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
