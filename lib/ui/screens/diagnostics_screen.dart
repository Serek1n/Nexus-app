import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n.dart';
import '../../models.dart';
import '../../services/diagnostics.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// «Проверка связи»: по шагам показывает, где именно не работает.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<DiagItem> _items = const [];
  bool _running = false;

  Future<void> _run() async {
    final app = AppScope.read(context);
    final s = app.selected;
    setState(() {
      _running = true;
      _items = const [];
    });
    final res = await Diagnostics.run(
      server: s,
      subscription: s == null ? null : app.subscriptionOf(s),
      proxy: app.state == ConnState.connected ? app.core.activeProxy : null,
      onUpdate: (l) {
        if (mounted) setState(() => _items = [...l]);
      },
    );
    app.lastDiagnostics = res.map((e) => '$e').join('\n');
    if (mounted) setState(() => _running = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// Короткий вывод по результатам: что делать клиенту.
  String? _advice() {
    if (_running || _items.isEmpty) return null;
    bool bad(String id) => _items.any((e) => e.id == id && e.ok == false);
    if (bad('net')) {
      return tr('Нет интернета даже без VPN — проверьте Wi-Fi или мобильные данные.');
    }
    if (bad('dns')) {
      return tr('Интернет есть, но имена сайтов не находятся — переподключите Wi-Fi или перезагрузите роутер.');
    }
    if (bad('server')) {
      return tr('Сервер не отвечает — выберите другой сервер или включите «Маскировку соединения» (Настройки → «Про»).');
    }
    final via = _items.where((e) => e.id == 'site' && e.ok != null);
    if (via.isNotEmpty && via.every((e) => e.ok == false)) {
      return tr('VPN подключён, но сайты не открываются — переподключитесь или выберите другой сервер.');
    }
    if (via.any((e) => e.ok == false)) {
      return tr('Часть сайтов не открывается через этот сервер — попробуйте другой.');
    }
    if (bad('ip')) {
      return tr('Сайты видят российский IP — трафик идёт мимо VPN. Переподключитесь или выберите другой сервер.');
    }
    if (_items.every((e) => e.ok != false)) return tr('Всё работает.');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final advice = _advice();
    return Scaffold(
      backgroundColor: NX.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 32),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(tr('Проверка связи'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20)),
              ),
              IconButton(
                tooltip: tr('Скопировать'),
                onPressed: _items.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(
                            text: _items.map((e) => '$e').join('\n')));
                        toast(context, tr('Скопировано'));
                      },
                icon: Icon(Icons.copy_rounded, color: NX.text2),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (advice != null) ...[
                    NeonCard(
                      child: Row(children: [
                        Icon(
                            advice == tr('Всё работает.')
                                ? Icons.check_circle_rounded
                                : Icons.lightbulb_rounded,
                            color: advice == tr('Всё работает.')
                                ? NX.mint
                                : NX.warn),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(advice,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, height: 1.35)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],
                  NeonCard(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                    child: Column(
                      children: [
                        for (var i = 0; i < _items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _Row(_items[i],
                              busy: _running && i == _items.length - 1),
                        ],
                        if (_items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  NeonButton(
                    label: _running ? tr('Проверяю…') : tr('Проверить ещё раз'),
                    icon: Icons.refresh_rounded,
                    loading: _running,
                    expand: true,
                    onPressed: _running ? null : _run,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr('Результат проверки попадает в «Отчёт для поддержки».'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NX.text3, fontSize: 12.5),
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

class _Row extends StatelessWidget {
  const _Row(this.item, {required this.busy});
  final DiagItem item;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Widget icon = busy && item.ok == null && item.detail.isEmpty
        ? const SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(
            item.ok == null
                ? Icons.remove_circle_outline_rounded
                : item.ok!
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
            size: 21,
            color: item.ok == null
                ? NX.text3
                : item.ok!
                    ? NX.mint
                    : NX.red);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                if (item.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(item.detail,
                      style: TextStyle(color: NX.text2, fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
