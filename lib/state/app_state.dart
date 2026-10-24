import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/vpn_core.dart';
import '../models.dart';
import '../services/config_builder.dart';
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
  ConnStats stats = const ConnStats();
  DateTime? connectedAt;
  String? lastError;
  bool pingingAll = false;
  final Set<String> refreshing = {};
  String coreVersion = '…';
  bool coreUpdating = false;
  String? coreUpdateStatus;

  StreamSubscription? _stSub, _statsSub;

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
      final subs = jsonDecode(_prefs.getString('subscriptions') ?? '[]') as List;
      subscriptions
        ..clear()
        ..addAll(subs.map((e) => Subscription.fromJson(e)));
      final srv = jsonDecode(_prefs.getString('servers') ?? '[]') as List;
      servers
        ..clear()
        ..addAll(srv.map((e) => ServerProfile.fromJson(e)));
    } catch (_) {}
    selectedId = _prefs.getString('selected');

    _stSub = core.states.listen(_onCoreState);
    _statsSub = core.stats.listen((s) {
      stats = s;
      notifyListeners();
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

    if (settings.autoUpdateOnStart && subscriptions.isNotEmpty) {
      await refreshAll(silent: true);
    }
    if (settings.autoConnectOnStart && selected != null) {
      unawaited(connect());
    }

    // Раз в сутки тихо проверяем обновление ядра Xray.
    final day = const Duration(hours: 20).inMilliseconds;
    if (core.canUpdateCore &&
        settings.autoUpdateCore &&
        DateTime.now().millisecondsSinceEpoch - settings.lastCoreCheck > day) {
      unawaited(updateCore(silent: true));
    }
  }

  /// Проверка и установка новой версии ядра Xray (Windows).
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

  void _save() {
    _prefs.setString('subscriptions',
        jsonEncode(subscriptions.map((e) => e.toJson()).toList()));
    _prefs.setString(
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

  void _onCoreState(ConnState s) {
    if (s == ConnState.connected && state != ConnState.connected) {
      connectedAt = DateTime.now();
    }
    if (s == ConnState.disconnected) {
      connectedAt = null;
      stats = const ConnStats();
    }
    state = s;
    notifyListeners();
  }

  String _configFor(ServerProfile s) =>
      buildXrayConfig(s, routing: settings.routing, desktop: isDesktop);

  Future<void> toggle() async {
    if (state == ConnState.connected || state == ConnState.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
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
    core.dispose();
    super.dispose();
  }
}
