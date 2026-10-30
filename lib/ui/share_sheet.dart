import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/android_system.dart';
import '../services/qr.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Окно «Поделиться»: QR-код, копирование и системное меню «Отправить».
/// QR можно отсканировать в Nexus на другом устройстве (Добавить →
/// Сканировать QR-код) или в любом другом клиенте.
Future<void> showShareSheet(
  BuildContext context, {
  required String title,
  required String text,
  required String warning,
}) {
  QrCode? qr;
  try {
    qr = QrCode.text(text);
  } catch (_) {}
  final body = _ShareBody(title: title, text: text, warning: warning, qr: qr);
  if (MediaQuery.sizeOf(context).width >= 760) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(width: 420, child: body),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: NX.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: NX.strokeStrong)),
      ),
      child: SafeArea(top: false, child: SingleChildScrollView(child: body)),
    ),
  );
}

class _ShareBody extends StatelessWidget {
  const _ShareBody({
    required this.title,
    required this.text,
    required this.warning,
    required this.qr,
  });
  final String title;
  final String text;
  final String warning;
  final QrCode? qr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          if (qr != null)
            Center(
              child: Container(
                width: 260,
                height: 260,
                // Белая рамка ≈ 4 модуля — «тихая зона», нужная сканерам.
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: CustomPaint(painter: _QrPainter(qr!)),
              ),
            )
          else
            Text(
                text.length > 2000
                    ? tr('Ссылка слишком длинная для QR-кода — скопируйте её')
                    : tr('Не удалось построить QR-код — скопируйте ссылку'),
                textAlign: TextAlign.center,
                style: TextStyle(color: NX.text2)),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.info_outline_rounded, color: NX.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(warning,
                  style: const TextStyle(
                      color: NX.text2, fontSize: 12.5, height: 1.35)),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: NeonButton(
                label: tr('Скопировать'),
                icon: Icons.copy_rounded,
                secondary: true,
                expand: true,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) toast(context, tr('Скопировано'));
                },
              ),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(width: 10),
              Expanded(
                child: NeonButton(
                  label: tr('Отправить'),
                  icon: Icons.ios_share_rounded,
                  expand: true,
                  onPressed: () => AndroidSystem.shareText(text),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);
  final QrCode qr;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / qr.size;
    final p = Paint()
      ..color = const Color(0xFF0B0B10)
      ..isAntiAlias = false;
    for (var y = 0; y < qr.size; y++) {
      for (var x = 0; x < qr.size; x++) {
        if (qr.dark(x, y)) {
          // Чуть внахлёст, чтобы между модулями не было светлых швов.
          canvas.drawRect(
              Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.qr != qr;
}
