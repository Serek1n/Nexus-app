import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Окно добавления подписки / сервера.
Future<void> showAddSheet(BuildContext context) async {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  if (wide) {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.all(24),
        child: SizedBox(width: 480, child: _AddForm()),
      ),
    );
  } else {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: NX.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: NX.strokeStrong)),
          ),
          child: const SafeArea(top: false, child: _AddForm(sheet: true)),
        ),
      ),
    );
  }
}

class _AddForm extends StatefulWidget {
  const _AddForm({this.sheet = false});
  final bool sheet;

  @override
  State<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends State<_AddForm> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isEmpty) {
      setState(() => _error = 'Буфер обмена пуст');
      return;
    }
    _ctrl.text = t;
    await _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msg = await AppScope.read(context).importText(_ctrl.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, msg);
    } catch (e) {
      final s = e.toString();
      setState(() =>
          _error = s.startsWith('Exception: ') ? s.substring(11) : s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, widget.sheet ? 12 : 24, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.sheet)
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
          const Text('Добавить',
              style: TextStyle(
                  fontFamily: NX.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          const SizedBox(height: 6),
          const Text(
            'Ссылка на подписку (https://…) или ключ сервера '
            '(vless://, vmess://, trojan://, ss://)',
            style: TextStyle(color: NX.text2, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          // Большая кнопка «из буфера» — основной сценарий.
          NeonCard(
            onTap: _loading ? null : _paste,
            active: true,
            accent: NX.violet,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: const Row(
              children: [
                Icon(Icons.content_paste_go_rounded, color: NX.violet),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Вставить из буфера обмена',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Скопируйте ссылку из бота и нажмите сюда',
                          style: TextStyle(color: NX.text2, fontSize: 12.5)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: NX.text3),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Row(children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('или вручную',
                  style: TextStyle(color: NX.text3, fontSize: 12)),
            ),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'https://… или vless://…',
              prefixIcon: Icon(Icons.link_rounded, color: NX.text3),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NX.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NX.red.withValues(alpha: 0.4)),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: NX.red, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 18),
          NeonButton(
            label: 'Добавить',
            icon: Icons.add_rounded,
            expand: true,
            loading: _loading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
