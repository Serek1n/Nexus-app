import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n.dart';
import '../../platform/android_system.dart';
import '../add_sheet.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Первый запуск: что такое Nexus → добавить подписку → (Android) работа
/// в фоне. Показывается, пока нет ни одного сервера и экран не пропущен.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  int get _count => Platform.isAndroid ? 3 : 2;

  void _go(int i) => _pages.animateToPage(i,
      duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  void _finish() =>
      AppScope.read(context).updateSettings((s) => s.onboarded = true);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _bullet(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: NX.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: NX.violet, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 15, height: 1.35)),
          ),
        ]),
      );

  Widget _step(String n, String title, String text, List<Widget> body,
          {Widget? top}) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (top != null) ...[top, const SizedBox(height: 28)],
              Text(n,
                  style: const TextStyle(
                      color: NX.violet,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 13)),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 27, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 10),
              Text(text,
                  style: const TextStyle(
                      color: NX.text2, fontSize: 14.5, height: 1.4)),
              const SizedBox(height: 26),
              ...body,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final added = app.servers.isNotEmpty;

    final pages = <Widget>[
      _step('NEXUS', tr('VPN, который думает за вас'),
          tr('Пара минут — и всё настроено. Вот что вы получаете:'), [
        _bullet(Icons.alt_route_rounded,
            tr('Банки и Госуслуги работают напрямую, остальное — через VPN')),
        _bullet(Icons.bolt_rounded,
            tr('Самый быстрый сервер и переподключение — сами')),
        _bullet(Icons.shield_rounded,
            tr('Ключи зашифрованы, реклама и трекеры блокируются')),
        const SizedBox(height: 28),
        NeonButton(
          label: tr('Начать'),
          icon: Icons.arrow_forward_rounded,
          expand: true,
          onPressed: () => _go(1),
        ),
      ],
          // Знак Nexus с мягким свечением — первый экран не пустой сверху.
          top: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: NX.glow(NX.violet, strength: 1.4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/icon/logo_mark.png',
                  filterQuality: FilterQuality.medium),
            ),
          )),
      _step('1 / ${_count - 1}', tr('Добавьте подписку'),
          tr('Ссылку на подписку выдаёт бот NEXUS_VPN. Скопируйте её и нажмите кнопку — или отсканируйте QR-код.'),
          [
        if (added)
          NeonCard(
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: NX.mint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    tr('Готово: серверов — {0}', [app.servers.length]),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          )
        else
          NeonButton(
            label: tr('Добавить подписку'),
            icon: Icons.add_link_rounded,
            expand: true,
            onPressed: () async {
              await showAddSheet(context);
              if (!mounted) return;
              if (AppScope.read(context).servers.isNotEmpty) {
                Platform.isAndroid ? _go(2) : _finish();
              }
            },
          ),
        const SizedBox(height: 12),
        if (added)
          NeonButton(
            label: Platform.isAndroid ? tr('Дальше') : tr('Готово'),
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () => Platform.isAndroid ? _go(2) : _finish(),
          ),
      ]),
      if (Platform.isAndroid)
        _step('2 / 2', tr('Чтобы VPN не обрывался'),
            tr('Android любит экономить батарею и останавливать приложения в фоне. Разрешите Nexus работать без ограничений и показывать уведомление о подключении.'),
            [
          NeonButton(
            label: tr('Разрешить работу в фоне'),
            icon: Icons.battery_charging_full_rounded,
            secondary: true,
            expand: true,
            onPressed: () async {
              await AndroidSystem.requestIgnoreBattery();
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) await AppScope.read(context).refreshBattery();
            },
          ),
          const SizedBox(height: 10),
          NeonButton(
            label: tr('Разрешить уведомления'),
            icon: Icons.notifications_active_rounded,
            secondary: true,
            expand: true,
            onPressed: AndroidSystem.requestNotifications,
          ),
          const SizedBox(height: 22),
          NeonButton(
            label: tr('Готово'),
            icon: Icons.check_rounded,
            expand: true,
            onPressed: _finish,
          ),
        ]),
    ];

    return Scaffold(
      backgroundColor: NX.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(children: [
                const NexusLogo(size: 26),
                const Spacer(),
                TextButton(
                  onPressed: _finish,
                  child: Text(tr('Пропустить'),
                      style: const TextStyle(color: NX.text2)),
                ),
              ]),
            ),
            Expanded(
              child: Center(
                child: PageView(
                  controller: _pages,
                  // Листать вперёд можно только кнопками: без подписки
                  // следующий шаг бессмысленен.
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [for (final p in pages) Center(child: p)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page ? NX.violet : NX.strokeStrong,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
