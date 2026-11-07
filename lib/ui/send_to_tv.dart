import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../platform/android_system.dart';
import '../services/phone_link.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Сканирует QR-код телевизора камерой и открывает окно отправки.
/// [sub] — подписка, выбранная заранее (из меню подписки).
Future<void> scanAndSendToTv(BuildContext context, {Subscription? sub}) async {
  if (!Platform.isAndroid) return;
  String? code;
  try {
    code = (await AndroidSystem.scanQr())?.trim();
  } catch (e) {
    if (context.mounted) toast(context, _msg(e), error: true);
    return;
  }
  if (code == null || !context.mounted) return; // сканер закрыли
  final t = PhoneLink.parseTarget(code);
  if (t == null) {
    toast(
        context,
        tr('Это не QR-код телевизора. На телевизоре откройте Nexus → «Добавить» и отсканируйте код с экрана.'),
        error: true);
    return;
  }
  await sendToTv(context, t, preselect: sub);
}

/// Окно «Отправить на телевизор»: выбор подписки и отправка.
/// true — отправлено.
Future<bool> sendToTv(BuildContext context, TvTarget target,
    {Subscription? preselect}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: NX.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: NX.strokeStrong)),
      ),
      child: SafeArea(
        top: false,
        child: _SendToTv(target: target, preselect: preselect),
      ),
    ),
  );
  if (sent == true && context.mounted) {
    toast(context, tr('Отправлено — подписка появится на телевизоре'));
  }
  return sent == true;
}

String _msg(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

class _SendToTv extends StatefulWidget {
  const _SendToTv({required this.target, this.preselect});
  final TvTarget target;
  final Subscription? preselect;

  @override
  State<_SendToTv> createState() => _SendToTvState();
}

class _SendToTvState extends State<_SendToTv> {
  String? _subId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subId = widget.preselect?.id;
  }

  /// Ссылка для телевизора: с запасными адресами — в виде nexus://add,
  /// чтобы они тоже доехали; без них — просто адрес подписки.
  String _payload(Subscription s) {
    if (s.mirrors.isEmpty) return s.url;
    return Uri(scheme: 'nexus', host: 'add', queryParameters: {
      'url': s.url,
      'mirror': s.mirrors.take(5).toList(),
    }).toString();
  }

  Future<void> _send(Subscription s) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PhoneLink.send(widget.target, _payload(s));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final subs = app.subscriptions;
    // Сразу выбрана подписка текущего сервера (или первая) — обычно
    // остаётся только нажать «Отправить».
    final chosen = subs.where((s) => s.id == _subId).firstOrNull ??
        subs.where((s) => s.id == app.selected?.subscriptionId).firstOrNull ??
        subs.firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                  color: NX.strokeStrong,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Row(children: [
            Icon(Icons.tv_rounded, color: NX.violet, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('Отправить на телевизор'),
                  style: TextStyle(
                      fontFamily: NX.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 20)),
            ),
          ]),
          const SizedBox(height: 6),
          // Адрес телевизора на виду — видно, куда уходит подписка.
          Text(tr('Телевизор в вашей сети: {0}', [widget.target.host]),
              style: TextStyle(color: NX.text3, fontSize: 13)),
          const SizedBox(height: 16),
          if (subs.isEmpty)
            Text(
              tr('На этом телефоне ещё нет подписок. Добавьте подписку в Nexus на телефоне — и отправьте её на телевизор.'),
              style: TextStyle(color: NX.text2, height: 1.4),
            )
          else ...[
            Text(tr('Какую подписку отправить?'),
                style: TextStyle(color: NX.text2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: subs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final s = subs[i];
                  final on = chosen?.id == s.id;
                  return NeonCard(
                    active: on,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    onTap: _busy ? null : () => setState(() => _subId = s.id),
                    child: Row(children: [
                      Icon(
                          on
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: on ? NX.violet : NX.text3),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                                tr('{0} серв.', [app.serversOf(s.id).length]),
                                style: TextStyle(color: NX.text3, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: NX.red, height: 1.35)),
          ],
          const SizedBox(height: 18),
          NeonButton(
            label: _busy ? tr('Отправляю…') : tr('Отправить'),
            icon: Icons.send_rounded,
            expand: true,
            onPressed: (_busy || chosen == null) ? null : () => _send(chosen),
          ),
        ],
      ),
    );
  }
}
