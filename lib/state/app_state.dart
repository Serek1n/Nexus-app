import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/vpn_core.dart';
import '../services/app_updater.dart';
import '../models.dart';
import '../platform/android_system.dart';
import '../platform/win_dpapi.dart';
import '../services/config_builder.dart';
import '../services/ru_apps.dart';
import '../services/subscription_service.dart';

/// Состояние приложения: подписки, серверы, подключение, настройки.
class AppState extends ChangeNotifier {
  AppState() : core = VpnCore.create();

  final VpnCore core;
  late SharedPreferences _prefs;

  final List<Subscription> subscriptions = [];
  final List<ServerProfile> servers = [];
  AppSettings settings = AppSettings();

  String? selectedId;
  ConnState state = ConnState.disconnected;
  /// Статистика обновляется каждую секунду — держим её отдельно,
  /// чтобы не перерисовывать весь интерфейс.
  final statsNotifier = ValueNotifier<ConnStats>(const ConnStats());
  ConnStats get stats => statsNotifier.value;
  bool windowVisible = true;
  DateTime? connectedAt;
  String? lastError;
  bool pingingAll = false;
  final Set<String> refreshing = {};
  String coreVersion = '…';
  bool coreUpdating = false;
  String? coreUpdateStatus;

  // ─── обновление приложения ───
  AppUpdate? appUpdate;
  File? updateFile;
  double? updateProgress;
  bool checkingUpdate = false;
  String? updateStatus;

  /// Закрытие приложения (Windows задаёт его, чтобы установщик мог заменить файлы).
  Future<void> Function()? quitApp;

  StreamSubscription? _stSub, _statsSub;
  Timer? _subTimer, _updTimer;

  bool get isDesktop => Platform.isWindows;

  ServerProfile? get selected {
    for (final s in servers) {
      if (s.id == selectedId) return s;
    }
    return servers.isEmpty ? null : servers.first;
  }

  List<ServerProfile> serversOf(String? subId) =>
      servers.where((s) => s.subscriptionId == subId).toList();

  Subscription? subscriptionOf(ServerProfile s) {
    for (final sub in subscriptions) {
      if (sub.id == s.subscriptionId) return sub;
    }
    return null;
  }

  // ───────────────────────── загрузка / сохранение ─────────────────────────

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    settings = AppSettings.fromJsonString(_prefs.getString('settings'));
    try {
      final subs = jsonDecode(_readSecret('subscriptions')) as List;
      subscriptions
        ..clear()
        ..addAll(subs.map((e) => Subscription.fromJson(e)));
      final srv = jsonDecode(_readSecret('servers')) as List;
      servers
        ..clear()
        ..addAll(srv.map((e) => ServerProfile.fromJson(e)));
      // Старые незашифрованные данные сразу перешифровываем.
      if (WinDpapi.available &&
          !WinDpapi.isProtected(_prefs.getString('servers') ?? 'dpapi:')) {
        _save();
      }
    } catch (_) {}
    if (!isDesktop) {
      await RuAppsUpdater.load();
      unawaited(RuAppsUpdater.refresh());
    }
    if (!isDesktop && settings.secureScreen) {
      unawaited(AndroidSystem.setSecureScreen(true));
    }
    selectedId = _prefs.getString('selected');

    _stSub = core.states.listen(_onCoreState);
    _statsSub = core.stats.listen((s) {
      statsNotifier.value = s;
    });
    try {
      await core.init();
    } catch (e) {
      lastError = 'Ошибка инициализации ядра: $e';
    }
    core.coreVersion().then((v) {
      coreVersion = v;
      notifyListeners();
    });
    notifyListeners();

    // Сначала подключаемся, подписки обновляем параллельно — запуск быстрее.
    if (settings.autoConnectOnStart && selected != null) {
      unawaited(connect());
    }
    if (settings.autoUpdateOnStart && subscriptions.isNotEmpty) {
      unawaited(refreshAll(silent: true));
    }

    // Пока приложение открыто — обновляем подписки раз в 6 часов.
    _subTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      final stale = DateTime.now().subtract(const Duration(hours: 6));
      for (final sub in [...subscriptions]) {
        if (sub.updatedAt == null || sub.updatedAt!.isBefore(stale)) {
          unawaited(refresh(sub, silent: true));
        }
      }
    });

    // Обновления приложения: при запуске (не чаще раза в 3 часа) и каждые 6 часов.
    if (AppUpdater.configured && settings.autoUpdateApp) {
      final since = DateTime.now().millisecondsSinceEpoch - settings.lastAppCheck;
      if (since > const Duration(hours: 3).inMilliseconds) {
        unawaited(checkAppUpdate(silent: true));
      }
      _updTimer = Timer.periodic(const Duration(hours: 6),
          (_) => checkAppUpdate(silent: true));
    }

    // Раз в сутки тихо проверяем обновление ядра Xray.
    final day = const Duration(hours: 20).inMilliseconds;
    if (core.canUpdateCore &&
        settings.autoUpdateCore &&
        DateTime.now().millisecondsSinceEpoch - settings.lastCoreCheck > day) {
      unawaited(updateCore(silent: true));
    }
  }

  /// Проверка новой версии ядра Xray: на Windows — замена ядра,
  /// на Android — поиск обновления приложения со свежим ядром.
  Future<void> updateCore({bool silent = false}) async {
    if (coreUpdating) return;
    coreUpdating = true;
    if (!silent) coreUpdateStatus = 'Проверяю…';
    notifyListeners();
    try {
      final msg = await core.updateCore();
      coreUpdateStatus = msg;
      settings.lastCoreCheck = DateTime.now().millisecondsSinceEpoch;
      _save();
      coreVersion = await core.coreVersion();
    } catch (e) {
      if (!silent) coreUpdateStatus = _msg(e);
    } finally {
      coreUpdating = false;
      notifyListeners();
    }
  }

  /// Проверяет обновление; если есть — сразу скачивает его в фоне.
  Future<void> checkAppUpdate({bool silent = false}) async {
    if (!AppUpdater.configured || checkingUpdate || updateProgress != null) {
      return;
    }
    checkingUpdate = true;
    if (!silent) updateStatus = 'Проверяю…';
    notifyListeners();
    try {
      final u = await AppUpdater.check();
      settings.lastAppCheck = DateTime.now().millisecondsSinceEpoch;
      _save();
      if (u == null) {
        appUpdate = null;
        updateFile = null;
        updateStatus = 'Установлена последняя версия';
        return;
      }
      if (appUpdate?.build != u.build) updateFile = null;
      appUpdate = u;
      updateStatus = null;
      checkingUpdate = false;
      if (settings.autoUpdateApp) await _downloadUpdate();
    } catch (e) {
      if (!silent) updateStatus = _msg(e);
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> _downloadUpdate() async {
    final u = appUpdate;
    if (u == null || updateFile != null || updateProgress != null) return;
    updateProgress = 0;
    notifyListeners();
    var lastPct = -1;
    try {
      updateFile = await AppUpdater.download(u, onProgress: (p) {
        final pct = (p * 100).floor();
        if (pct != lastPct) {
          lastPct = pct;
          updateProgress = p;
          notifyListeners();
        }
      });
    } catch (e) {
      updateStatus = _msg(e);
    } finally {
      updateProgress = null;
      notifyListeners();
    }
  }

  /// Ставит обновление (при необходимости сначала скачивает).
  Future<void> installAppUpdate() async {
    if (appUpdate == null) return;
    if (updateFile == null) await _downloadUpdate();
    final f = updateFile;
    if (f == null) return;
    try {
      if (isDesktop) {
        updateStatus = 'Устанавливаю, Nexus перезапустится…';
        notifyListeners();
        if (state != ConnState.disconnected) await core.disconnect();
        await AppUpdater.install(f);
        await Future.delayed(const Duration(milliseconds: 500));
        await quitApp?.call();
      } else {
        await AppUpdater.install(f);
        updateStatus = 'Подтвердите установку в системном окне';
      }
    } catch (e) {
      updateStatus = _msg(e);
    }
    notifyListeners();
  }

  /// Ссылки подписок и ключи серверов на Windows хранятся зашифрованными (DPAPI).
  String _readSecret(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return '[]';
    return WinDpapi.unprotect(raw) ?? '[]';
  }

  void _writeSecret(String key, String value) =>
      _prefs.setString(key, WinDpapi.protect(value));

  void _save() {
    _writeSecret('subscriptions',
        jsonEncode(subscriptions.map((e) => e.toJson()).toList()));
    _writeSecret(
        'servers', jsonEncode(servers.map((e) => e.toJson()).toList()));
    if (selectedId != null) _prefs.setString('selected', selectedId!);
    _prefs.setString('settings', settings.toJsonString());
  }

  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    _save();
    notifyListeners();
  }

  // ───────────────────────────── подключение ─────────────────────────────

  /// Kill switch сработал (Windows): VPN упал, интернет заблокирован.
  bool get blocked => core.blocked;

  /// Реальная задержка через туннель после подключения.
  int? liveLatency;

  Future<void> measureLatency() async {
    final s = selected;
    if (s == null || state != ConnState.connected) return;
    liveLatency = null;
    notifyListeners();
    try {
      liveLatency = await core.connectedDelay(s);
    } catch (_) {
      liveLatency = -1;
    }
    notifyListeners();
  }

  void _onCoreState(ConnState s) {
    if (s == ConnState.connected && state != ConnState.connected) {
      connectedAt = DateTime.now();
      Future.delayed(const Duration(seconds: 1), measureLatency);
    }
    if (s != ConnState.connected) liveLatency = null;
    if (s == ConnState.disconnected) {
      connectedAt = null;
      statsNotifier.value = const ConnStats();
    }
    state = s;
    notifyListeners();
  }

  String _configFor(ServerProfile s) => buildXrayConfig(
        s,
        routing: settings.routing,
        desktop: isDesktop,
        lockLocalProxy: !isDesktop && settings.androidVpnMode,
      );

  Future<void> toggle() async {
    if (state == ConnState.connected || state == ConnState.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  bool _askedNotifications = false;

  Future<void> connect() async {
    if (!isDesktop && !_askedNotifications) {
      _askedNotifications = true;
      await AndroidSystem.requestNotifications();
    }
    final s = selected;
    if (s == null) {
      lastError = 'Сначала добавьте подписку или сервер';
      notifyListeners();
      return;
    }
    lastError = null;
    state = ConnState.connecting;
    notifyListeners();
    try {
      await core.connect(
        remark: s.cleanName,
        config: _configFor(s),
        settings: settings,
      );
    } catch (e) {
      lastError = _msg(e);
      state = ConnState.disconnected;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    state = ConnState.disconnecting;
    notifyListeners();
    try {
      await core.disconnect();
    } catch (e) {
      lastError = _msg(e);
    }
    // На Android статус придёт из сервиса; на всякий случай выставляем сами.
    await Future.delayed(const Duration(milliseconds: 600));
    if (state == ConnState.disconnecting) _onCoreState(ConnState.disconnected);
  }

  /// Выбор сервера; при активном соединении — переподключение.
  Future<void> select(ServerProfile s) async {
    if (selectedId == s.id) return;
    selectedId = s.id;
    _save();
    notifyListeners();
    if (state == ConnState.connected) {
      await core.disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      await connect();
    }
  }

  /// Полное переподключение (в том числе после срабатывания kill switch).
  Future<void> reconnect() async {
    await core.disconnect();
    await Future.delayed(const Duration(milliseconds: 300));
    await connect();
  }

  /// Перезапуск соединения после смены настроек маршрутизации.
  Future<void> reconnectIfActive() async {
    if (state != ConnState.connected) return;
    await core.disconnect();
    await Future.delayed(const Duration(milliseconds: 400));
    await connect();
  }

  // ─────────────────────────────── пинг ───────────────────────────────

  Future<void> pingOne(ServerProfile s) async {
    s.ping = null;
    notifyListeners();
    try {
      s.ping = await core.ping(s, _configFor(s));
    } catch (_) {
      s.ping = -1;
    }
    notifyListeners();
  }

  Future<void> pingAll() async {
    if (pingingAll) return;
    pingingAll = true;
    for (final s in servers) {
      s.ping = null;
    }
    notifyListeners();
    // Параллельно, но ограниченно: на Android замер идёт через ядро.
    final queue = [...servers];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final s = queue.removeAt(0);
        try {
          s.ping = await core.ping(s, _configFor(s));
        } catch (_) {
          s.ping = -1;
        }
        notifyListeners();
      }
    }

    await Future.wait(List.generate(isDesktop ? 8 : 3, (_) => worker()));
    pingingAll = false;
    notifyListeners();
  }

  /// Выбирает сервер с минимальной задержкой.
  Future<void> selectFastest() async {
    await pingAll();
    final ok = servers.where((s) => (s.ping ?? -1) > 0).toList()
      ..sort((a, b) => a.ping!.compareTo(b.ping!));
    if (ok.isNotEmpty) await select(ok.first);
  }

  // ─────────────────────────── добавление ───────────────────────────

  /// Универсальный импорт: ссылка на подписку, ссылка на сервер,
  /// список ссылок или base64-блок. Возвращает текст результата.
  Future<String> importText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) throw Exception('Пусто — вставьте ссылку');

    if (isHttpUrl(text) && !text.contains('\n')) {
      final sub = await addSubscription(text);
      return 'Подписка «${sub.title}» добавлена: ${serversOf(sub.id).length} серв.';
    }

    final links = extractLinks(text);
    if (links.isEmpty) {
      throw Exception('Не найдено ни одной поддерживаемой ссылки');
    }
    var added = 0;
    ServerProfile? first;
    for (final l in links) {
      if (servers.any((s) => s.link == l)) continue;
      final p = profileFromLink(l);
      if (p != null) {
        servers.add(p);
        first ??= p;
        added++;
      }
    }
    if (added == 0) throw Exception('Эти серверы уже добавлены');
    if (selectedId == null && first != null) selectedId = first.id;
    _save();
    notifyListeners();
    return 'Добавлено серверов: $added';
  }

  Future<Subscription> addSubscription(String url) async {
    final existing = subscriptions.where((s) => s.url == url).toList();
    if (existing.isNotEmpty) {
      await refresh(existing.first);
      return existing.first;
    }
    final sub = Subscription(id: newId(), url: url, title: 'Подписка');
    final res = await SubscriptionService.fetch(sub);
    subscriptions.add(res.meta);
    servers.addAll(res.servers);
    if (selected == null || selectedId == null) {
      selectedId = res.servers.first.id;
    }
    _save();
    notifyListeners();
    return res.meta;
  }

  Future<void> refresh(Subscription sub, {bool silent = false}) async {
    refreshing.add(sub.id);
    notifyListeners();
    try {
      final res = await SubscriptionService.fetch(sub);
      // Сохраняем выбор сервера, если он остался в подписке.
      final sel = selected;
      final keepLink = sel?.subscriptionId == sub.id ? sel?.link : null;
      final keepName = sel?.subscriptionId == sub.id ? sel?.name : null;
      servers.removeWhere((s) => s.subscriptionId == sub.id);
      servers.addAll(res.servers);
      if (keepLink != null) {
        final match = res.servers.where((s) => s.link == keepLink).toList();
        final byName = res.servers.where((s) => s.name == keepName).toList();
        selectedId = match.isNotEmpty
            ? match.first.id
            : byName.isNotEmpty
                ? byName.first.id
                : res.servers.first.id;
      }
      _save();
    } catch (e) {
      if (!silent) lastError = 'Обновление «${sub.title}»: ${_msg(e)}';
    } finally {
      refreshing.remove(sub.id);
      notifyListeners();
    }
  }

  Future<void> refreshAll({bool silent = false}) async {
    await Future.wait(subscriptions.map((s) => refresh(s, silent: silent)));
  }

  void removeSubscription(Subscription sub) {
    subscriptions.removeWhere((s) => s.id == sub.id);
    servers.removeWhere((s) => s.subscriptionId == sub.id);
    if (!servers.any((s) => s.id == selectedId)) {
      selectedId = servers.isEmpty ? null : servers.first.id;
    }
    _save();
    notifyListeners();
  }

  void removeServer(ServerProfile s) {
    servers.removeWhere((x) => x.id == s.id);
    if (selectedId == s.id) {
      selectedId = servers.isEmpty ? null : servers.first.id;
    }
    _save();
    notifyListeners();
  }

  void renameSubscription(Subscription sub, String title) {
    sub.title = title.trim().isEmpty ? sub.title : title.trim();
    _save();
    notifyListeners();
  }

  Future<void> resetAll() async {
    if (state != ConnState.disconnected) await disconnect();
    subscriptions.clear();
    servers.clear();
    selectedId = null;
    await _prefs.clear();
    settings = AppSettings();
    notifyListeners();
  }

  /// Окно свёрнуто/скрыто в трей — ядру можно реже опрашивать статистику.
  void setWindowVisible(bool v) {
    if (windowVisible == v) return;
    windowVisible = v;
    core.setForeground(v);
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  String _msg(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  @override
  void dispose() {
    _stSub?.cancel();
    _statsSub?.cancel();
    _subTimer?.cancel();
    _updTimer?.cancel();
    core.dispose();
    super.dispose();
  }
}
