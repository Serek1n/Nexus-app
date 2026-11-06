import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Экран PIN-кода поверх всего приложения (включается в «Защите»).
/// Подключение, плитка и виджет работают и без ввода PIN — закрыт только
/// интерфейс с ключами и подписками.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.app, required this.child});
  final AppState app;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      child: child,
      builder: (context, child) => Stack(
        children: [
          // Пока экран заблокирован, интерфейс под ним недоступен ни
          // касанием, ни клавиатурой, ни для программ чтения экрана.
          ExcludeSemantics(
            excluding: app.locked,
            child: IgnorePointer(
              ignoring: app.locked,
              child: ExcludeFocus(excluding: app.locked, child: child!),
            ),
          ),
          if (app.locked) Positioned.fill(child: _LockScreen(app: app)),
        ],
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.app});
  final AppState app;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String _pin = '';
  bool _busy = false;
  bool _wrong = false;
  Timer? _tick;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Обратный отсчёт после серии неверных попыток.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.app.pinBlockedUntil != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _focus.dispose();
    super.dispose();
  }

  int get _waitSec {
    final u = widget.app.pinBlockedUntil;
    if (u == null) return 0;
    final s = u.difference(DateTime.now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  void _press(String d) {
    if (_busy || _waitSec > 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _wrong = false;
      if (d == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += d;
      }
    });
  }

  Future<void> _submit() async {
    if (_busy || _pin.length < 4 || _waitSec > 0) return;
    setState(() => _busy = true);
    final ok = await widget.app.unlock(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _wrong = true;
        _pin = '';
        HapticFeedback.heavyImpact();
      }
    });
  }

  /// Забытый PIN не восстановить: можно только стереть всё и добавить
  /// подписку заново. Подтверждение — прямо на этом экране (он выше
  /// навигатора, обычные окна появились бы под ним).
  bool _confirmReset = false;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _press(ch);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _press('<');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, {IconData? icon, VoidCallback? onTap}) {
    return SizedBox(
      width: 76,
      height: 64,
      child: Material(
        color: NX.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: NX.stroke),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap ?? () => _press(label),
          child: Center(
            child: icon != null
                ? Icon(icon, color: NX.text2, size: 24)
                : Text(label,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wait = _waitSec;
    final msg = wait > 0
        ? tr('Слишком много попыток. Подождите {0} с', [wait])
        : _wrong
            ? tr('Неверный PIN-код')
            : tr('Введите PIN-код');
    return Focus(
      autofocus: true,
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Material(
        color: NX.bg,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NexusLogo(size: 30),
                  const SizedBox(height: 28),
                  Text(msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: (_wrong || wait > 0) ? NX.red : NX.text)),
                  const SizedBox(height: 18),
                  // Точки вместо цифр: длина PIN-кода видна, сами цифры — нет.
                  SizedBox(
                    height: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length ? NX.violet : Colors.transparent,
                              border: Border.all(
                                  color: i < _pin.length ? NX.violet : NX.text3,
                                  width: 1.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ]) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final d in row) ...[
                          _key(d),
                          if (d != row.last) const SizedBox(width: 14),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _key('', icon: Icons.backspace_outlined, onTap: () => _press('<')),
                      const SizedBox(width: 14),
                      _key('0'),
                      const SizedBox(width: 14),
                      _key('',
                          icon: _busy ? Icons.hourglass_top_rounded : Icons.check_rounded,
                          onTap: _submit),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (!_confirmReset)
                    TextButton(
                      onPressed: () => setState(() => _confirmReset = true),
                      style: TextButton.styleFrom(foregroundColor: NX.text3),
                      child: Text(tr('Забыли PIN-код?')),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Column(children: [
                        Text(
                          tr('PIN-код не восстановить. Можно стереть все подписки, серверы и настройки — потом добавьте подписку заново (ссылка есть у вашего VPN-сервиса).'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: NX.text2, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          TextButton(
                            onPressed: () => setState(() => _confirmReset = false),
                            child: Text(tr('Отмена')),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => widget.app.resetAll(),
                            style: TextButton.styleFrom(foregroundColor: NX.red),
                            child: Text(tr('Стереть всё')),
                          ),
                        ]),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
