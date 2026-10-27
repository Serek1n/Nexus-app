import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
    // Случайный идентификатор установки для подписок с лимитом устройств.
    var did = _prefs.getString('deviceId');
    if (did == null || did.length < 16) {
      final r = math.Random.secure();
      did = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      await _prefs.setString('deviceId', did);
    }
    SubscriptionService.deviceId = did;
    settings = AppSettings.fromJsonString(_prefs.getString('settings'));
    try {
      final subs = jsonDecode(await _readSecret('subscriptions')) as List;
      subscriptions
        ..clear()
        ..addAll(subs.map((e) => Subscription.fromJson(e)));
      final srv = jsonDecode(await _readSecret('servers')) as List;
      servers
        ..clear()
        ..addAll(srv.map((e) => ServerProfile.fromJson(e)));
      _applyAliases();
      // Старые незашифрованные данные сразу перешифровываем.
      final raw = _prefs.getString('servers');
      if (raw != null && !_isProtected(raw)) _save();
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
    unawaited(refreshBattery());
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
      // После отката плохую версию сами не предлагаем — только по кнопке.
      if (silent && u.build <= settings.skippedBuild) {
        appUpdate = null;
        updateFile = null;
        updateStatus = '${u.version} пропущена после отката';
        return;
      }
      if (appUpdate?.build != u.build) updateFile = null;
      appUpdate = u;
      updateStatus = null;
      checkingUpdate = false;
      // Только сообщаем: скачивание начнётся, когда нажмут «Установить».
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

  /// Откат (Windows): ставит выбранную старую версию поверх текущей.
  /// Текущая сборка и всё до неё больше не предлагаются автоматически.
  Future<void> rollbackTo(AppRelease r) async {
    final current = await AppUpdater.currentBuild();
    updateStatus = 'Готовлю ${r.version}…';
    notifyListeners();
    try {
      final u = await AppUpdater.prepare(r);
      settings.skippedBuild = current;
      _save();
      appUpdate = u;
      updateFile = null;
      await installAppUpdate();
    } catch (e) {
      updateStatus = _msg(e);
      notifyListeners();
      rethrow;
    }
  }

  /// Ссылки всех подписок — чтобы перенести их после переустановки.
  String exportSubscriptions() =>
      subscriptions.map((s) => s.url).join('\n');

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

  /// Ссылки подписок и ключи серверов хранятся зашифрованными:
  /// на Windows — DPAPI, на Android — ключом из Android Keystore.
  static const _aks = 'aks:';

  bool _isProtected(String raw) =>
      raw.startsWith(_aks) || WinDpapi.isProtected(raw);

  Future<String> _readSecret(String key) async {
    final raw = _prefs.getString(key);
    if (raw == null) return '[]';
    if (raw.startsWith(_aks)) {
      return await AndroidSystem.unprotect(raw.substring(_aks.length)) ?? '[]';
    }
    return WinDpapi.unprotect(raw) ?? '[]';
  }

  Future<void> _writeSecret(String key, String value) async {
    if (Platform.isAndroid) {
      final enc = await AndroidSystem.protect(value);
      // Если Keystore недоступен — не теряем данные, сохраняем как есть.
      await _prefs.setString(key, enc != null ? '$_aks$enc' : value);
    } else {
      await _prefs.setString(key, WinDpapi.protect(value));
    }
  }

  /// Сохранения выполняются строго по очереди, чтобы старое не затёрло новое.
  Future<void> _saveChain = Future.value();

  /// Дождаться записи всех изменений на диск (перед перезапуском).
  Future<void> flushSaves() => _saveChain;

  void _save() {
    final subs = jsonEncode(subscriptions.map((e) => e.toJson()).toList());
    final srv = jsonEncode(servers.map((e) => e.toJson()).toList());
    _saveChain = _saveChain.then((_) async {
      await _writeSecret('subscriptions', subs);
      await _writeSecret('servers', srv);
    }).catchError((_) {});
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

  Future<void> measureLatency({bool afterConnect = false}) async {
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
    core.note(liveLatency != null && liveLatency! > 0
        ? 'Трафик через «${s.cleanName}» идёт, задержка $liveLatency мс'
        : 'Через «${s.cleanName}» трафик не проходит — сервер не ответил');
    if (afterConnect && liveLatency == -1) await _failover(s);
  }

  /// Серверы, уже опробованные в текущей попытке подключения.
  final Set<String> _failoverTried = {};
  String? failoverNote;

  /// Сервер подключился, но трафик не идёт — пробуем следующие
  /// по задержке (до 3 штук), если включено «Автовыбор при сбое».
  Future<void> _failover(ServerProfile bad) async {
    if (!settings.autoFailover || core.blocked) return;
    _failoverTried.add(bad.id);
    if (_failoverTried.length > 3) {
      failoverNote = null;
      lastError = 'Ни один сервер не отвечает — проверьте интернет или подписку';
      _wantConnected = false;
      reconnectNote = null;
      notifyListeners();
      return;
    }
    final candidates = servers
        .where((x) => !_failoverTried.contains(x.id))
        .toList()
      ..sort((a, b) {
        int k(ServerProfile x) =>
            (x.ping == null || x.ping! < 0) ? 1 << 30 : x.ping!;
        return k(a).compareTo(k(b));
      });
    if (candidates.isEmpty) return;
    final next = candidates.first;
    failoverNote = '«${bad.cleanName}» не отвечает — переключаюсь на «${next.cleanName}»';
    notifyListeners();
    selectedId = next.id;
    _save();
    await core.disconnect();
    await Future.delayed(const Duration(milliseconds: 400));
    await connect(keepFailover: true);
  }

  // ───────────── стабильность: автопереподключение и проверка канала ─────────────

  /// Пользователь хочет быть подключённым (нажал «Подключить» и не нажимал «Отключить»).
  bool _wantConnected = false;
  int _retry = 0;
  Timer? _retryTimer, _healthTimer;
  int _healthFails = 0;
  String? reconnectNote;

  /// Соединение оборвалось само (система закрыла VPN, упало ядро, пропала сеть) —
  /// переподключаемся с нарастающей паузой: 2, 5, 10, 20, 30 с, дальше каждые 30 с.
  void _scheduleReconnect() {
    if (!_wantConnected || !settings.autoReconnect || core.blocked) return;
    _retryTimer?.cancel();
    const steps = [2, 5, 10, 20, 30];
    final sec = steps[_retry.clamp(0, steps.length - 1)];
    _retry++;
    reconnectNote = 'Связь пропала — переподключаюсь (попытка $_retry)…';
    notifyListeners();
    _retryTimer = Timer(Duration(seconds: sec), () async {
      if (!_wantConnected || state != ConnState.disconnected) return;
      // Сервер так и не подключился за 4 попытки, а сеть есть —
      // не крутим бесконечно: другой сервер или понятная ошибка.
      final s = selected;
      if (_retry >= 4 && s != null &&
          (await _networkSignature()).isNotEmpty) {
        _retry = 0;
        reconnectNote = null;
        if (settings.autoFailover && servers.length > 1) {
          await _failover(s);
        } else {
          _wantConnected = false;
          lastError = 'Не удаётся подключиться к «${s.cleanName}». '
              'Попробуйте другой сервер';
          notifyListeners();
        }
        return;
      }
      // Android: VPN забрало другое приложение — не воюем с ним и не
      // выскакиваем системным окном разрешения поверх других программ.
      if (!isDesktop &&
          settings.androidVpnMode &&
          !await AndroidSystem.vpnPrepared()) {
        _wantConnected = false;
        reconnectNote = null;
        lastError = 'VPN включён в другом приложении — Nexus отключился. '
            'Нажмите «Подключить», чтобы вернуть его';
        notifyListeners();
        return;
      }
      await connect(keepFailover: true, auto: true);
    });
  }

  /// Проверка канала: раз в 45 с запрос через туннель. Провал — повтор через
  /// 10 с; второй провал — переподключение; если и после него трафика нет —
  /// следующий сервер. Смена сети (Wi-Fi ↔ мобильный) — проверка сразу.
  Timer? _netTimer;
  String? _netSig;
  DateTime _lastNetTick = DateTime.now();
  Timer? _connectGuard;

  /// Итог последней сессии («1 ч 12 мин · ↓ 1.2 ГБ · ↑ 80 МБ»).
  String? lastSession;

  /// Android: включена экономия батареи для Nexus — система может рвать VPN.
  bool batteryRestricted = false;

  /// Пора показать уведомление про батарею: подключены, ограничение есть,
  /// а прошлое уведомление было больше 3 дней назад.
  bool get batteryHintDue =>
      !isDesktop &&
      batteryRestricted &&
      settings.autoReconnect &&
      state == ConnState.connected &&
      DateTime.now().millisecondsSinceEpoch -
              (_prefs.getInt('batteryHintAt') ?? 0) >
          const Duration(days: 3).inMilliseconds;

  void markBatteryHintShown() {
    _prefs.setInt('batteryHintAt', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> refreshBattery() async {
    if (isDesktop) return;
    final restricted = !(await AndroidSystem.isIgnoringBattery());
    if (restricted != batteryRestricted) {
      batteryRestricted = restricted;
      notifyListeners();
    }
  }

  /// Переподключений подряд без восстановления трафика (сбрасывается
  /// только успешной проверкой, а не новым подключением).
  int _deadReconnects = 0;

  void _startHealth() {
    _healthTimer?.cancel();
    _netTimer?.cancel();
    _healthFails = 0;
    if (!settings.autoReconnect) return;
    _scheduleHealth(const Duration(seconds: 45));
    _networkSignature().then((v) => _netSig = v);
    _lastNetTick = DateTime.now();
    _netTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (state != ConnState.connected) return;
      // Большой разрыв между тиками — компьютер/телефон спал: проверяем канал.
      final now = DateTime.now();
      final slept = now.difference(_lastNetTick).inSeconds > 20;
      _lastNetTick = now;
      if (slept) {
        _scheduleHealth(const Duration(seconds: 3));
        return;
      }
      final sig = await _networkSignature();
      if (sig.isEmpty) return;
      final changed = _netSig != null && _netSig!.isNotEmpty && sig != _netSig;
      _netSig = sig;
      if (changed) _scheduleHealth(const Duration(seconds: 2));
    });
  }

  void _stopHealth() {
    _healthTimer?.cancel();
    _netTimer?.cancel();
  }

  void _scheduleHealth(Duration d) {
    _healthTimer?.cancel();
    _healthTimer = Timer(d, _healthCheck);
  }

  Future<void> _healthCheck() async {
    final s = selected;
    if (state != ConnState.connected) return;
    if (s == null || core.blocked) {
      _scheduleHealth(const Duration(seconds: 45));
      return;
    }
    final d = await core.connectedDelay(s);
    if (state != ConnState.connected) return;
    if (d <= 0) core.note('Проверка канала: «${s.cleanName}» не ответил');
    if (d > 0) {
      _healthFails = 0;
      _deadReconnects = 0;
      liveLatency = d;
      if (reconnectNote != null) reconnectNote = null;
      notifyListeners();
      _scheduleHealth(const Duration(seconds: 45));
      return;
    }
    // Нет ни одной сети — ждём её, сервер не виноват.
    if ((await _networkSignature()).isEmpty) {
      _scheduleHealth(const Duration(seconds: 10));
      return;
    }
    _healthFails++;
    if (_healthFails == 1) {
      _scheduleHealth(const Duration(seconds: 10));
      return;
    }
    _healthFails = 0;
    if (_deadReconnects == 0 || !settings.autoFailover) {
      _deadReconnects++;
      reconnectNote = 'Канал не отвечает — переподключаюсь…';
      notifyListeners();
      await reconnect();
    } else {
      _deadReconnects = 0;
      await _failover(s);
    }
  }

  /// «Отпечаток» сетей устройства: меняется при переключении Wi-Fi/мобильной
  /// сети. Учитываем только IPv4 и пропускаем туннели (свой VPN и чужие).
  Future<String> _networkSignature() async {
    try {
      final list = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      final parts = <String>[];
      for (final i in list) {
        final n = i.name.toLowerCase();
        if (n.startsWith('tun') ||
            n.startsWith('ppp') ||
            n.contains('wintun') ||
            n.contains('wireguard') ||
            n.contains('vpn')) {
          continue;
        }
        for (final a in i.addresses) {
          if (!a.isLinkLocal) parts.add('${i.name}=${a.address}');
        }
      }
      parts.sort();
      return parts.join(',');
    } catch (_) {
      return 'unknown';
    }
  }

  void _onCoreState(ConnState s) {
    if (s != ConnState.connecting) _connectGuard?.cancel();
    if (s == ConnState.connected) unawaited(refreshBattery());
    if (s == ConnState.connected && state != ConnState.connected) {
      unawaited(_refreshOnConnect());
    }
    if (s == ConnState.disconnected && connectedAt != null) {
      final d = DateTime.now().difference(connectedAt!);
      final st = statsNotifier.value;
      if (d.inSeconds >= 10) {
        lastSession = [
          _fmtDuration(d),
          if (st.download > 0) '↓ ${_fmtBytes(st.download)}',
          if (st.upload > 0) '↑ ${_fmtBytes(st.upload)}',
        ].join(' · ');
      }
    }
    if (s == ConnState.connected && state != ConnState.connected) {
      _retry = 0;
      reconnectNote = null;
      _startHealth();
    }
    if (s == ConnState.disconnected) {
      _stopHealth();
      if (_wantConnected && state != ConnState.disconnecting) {
        // Обрыв не по команде пользователя.
        Future.delayed(const Duration(seconds: 2), () {
          if (state == ConnState.disconnected) _scheduleReconnect();
        });
      }
    }
    if (s == ConnState.connected && state != ConnState.connected) {
      connectedAt = DateTime.now();
      Future.delayed(const Duration(seconds: 1),
          () => measureLatency(afterConnect: true));
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
        customProxy: settings.customProxy,
        customDirect: settings.customDirect,
      );

  Future<void> toggle() async {
    if (state == ConnState.connected || state == ConnState.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  bool _askedNotifications = false;

  Future<void> connect({bool keepFailover = false, bool auto = false}) async {
    _wantConnected = true;
    if (!auto) {
      _retry = 0;
      _retryTimer?.cancel();
    }
    if (!keepFailover) {
      _failoverTried.clear();
      failoverNote = null;
    }
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
    lastSession = null;
    state = ConnState.connecting;
    notifyListeners();
    // Подключение «зависло» (нет ответа от ядра или системы) — не ждём вечно.
    _connectGuard?.cancel();
    _connectGuard = Timer(const Duration(seconds: 30), () async {
      if (state != ConnState.connecting) return;
      if (!settings.autoReconnect) {
        lastError = 'Не удалось подключиться за 30 секунд';
      }
      try {
        await core.disconnect();
      } catch (_) {}
      // Ядро промолчало — выходим из «Подключение…» сами.
      if (state == ConnState.connecting) _onCoreState(ConnState.disconnected);
    });
    try {
      await core.connect(
        remark: s.cleanName,
        config: _configFor(s),
        settings: settings,
      );
    } catch (e) {
      state = ConnState.disconnected;
      if (auto) {
        _scheduleReconnect();
      } else {
        lastError = _msg(e);
      }
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _connectGuard?.cancel();
    _retryTimer?.cancel();
    _stopHealth();
    _deadReconnects = 0;
    reconnectNote = null;
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

  bool isFavorite(ServerProfile s) => settings.favorites.contains(s.favKey);

  void toggleFavorite(ServerProfile s) => updateSettings((st) {
        st.favorites = isFavorite(s)
            ? st.favorites.where((k) => k != s.favKey).toList()
            : [...st.favorites, s.favKey];
      });

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

  /// Серверы, задержка которых измеряется прямо сейчас.
  final Set<String> pinging = {};
  Timer? _notifyTimer;

  /// При сотнях замеров перерисовываем экран не на каждый результат,
  /// а не чаще 4 раз в секунду.
  void _notifySoon() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 250), notifyListeners);
  }

  Future<void> pingAll() async {
    if (pingingAll) return;
    pingingAll = true;
    notifyListeners();
    await pingMany(servers);
    pingingAll = false;
    notifyListeners();
  }

  /// Проверка группы серверов (например, одной подписки).
  Future<void> pingMany(Iterable<ServerProfile> list) async {
    final queue = list.where((s) => !pinging.contains(s.id)).toList();
    if (queue.isEmpty) return;
    for (final s in queue) {
      s.ping = null;
      pinging.add(s.id);
    }
    notifyListeners();
    final total = queue.length;
    pingProgress = (0, total);

    // ПК: пачками по 24 сервера на одно ядро — в разы быстрее, чем
    // запускать ядро на каждый сервер. Не вышло — меряем по одному.
    if (isDesktop && queue.length > 2) {
      final rest = <ServerProfile>[];
      while (queue.isNotEmpty) {
        final chunk = queue.take(24).toList();
        queue.removeRange(0, chunk.length);
        final r = await core.pingBatch(chunk, _configFor);
        if (r == null) {
          rest.addAll(chunk);
          continue;
        }
        for (final s in chunk) {
          s.ping = r[s.id] ?? -1;
          pinging.remove(s.id);
        }
        pingProgress = (total - queue.length - rest.length, total);
        _notifySoon();
      }
      queue.addAll(rest);
    }

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final s = queue.removeAt(0);
        try {
          s.ping = await core.ping(s, _configFor(s));
        } catch (_) {
          s.ping = -1;
        }
        pinging.remove(s.id);
        pingProgress = (total - queue.length, total);
        _notifySoon();
      }
    }

    // По одному: на ПК не больше 4 ядер разом, на Android — 5 замеров.
    await Future.wait(List.generate(isDesktop ? 4 : 5, (_) => worker()));
    pingProgress = null;
    notifyListeners();
  }

  /// Прогресс массовой проверки: (готово, всего); null — не идёт.
  (int, int)? pingProgress;

  /// Своё название сервера («» — вернуть исходное).
  void renameServer(ServerProfile s, String name) {
    final n = name.trim();
    if (n.isEmpty) {
      settings.aliases.remove(s.aliasKey);
    } else {
      settings.aliases[s.aliasKey] = n.length > 40 ? n.substring(0, 40) : n;
    }
    _applyAliases();
    _save();
    notifyListeners();
  }

  void _applyAliases() {
    for (final s in servers) {
      s.alias = settings.aliases[s.aliasKey];
    }
  }

  Future<void> pingOne(ServerProfile s) async {
    if (pinging.contains(s.id)) return;
    pinging.add(s.id);
    s.ping = null;
    notifyListeners();
    try {
      s.ping = await core.ping(s, _configFor(s));
    } catch (_) {
      s.ping = -1;
    }
    pinging.remove(s.id);
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
    // Несколько ссылок подписок (перенос после переустановки).
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length > 1 && lines.every(isHttpUrl)) {
      var ok = 0;
      for (final l in lines.take(50)) {
        try {
          await addSubscription(l);
          ok++;
        } catch (_) {}
      }
      if (ok == 0) throw Exception('Не удалось загрузить ни одну подписку');
      return 'Добавлено подписок: $ok из ${lines.length}';
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

  /// Загрузка подписки. Если провайдер не пускает к её серверу напрямую
  /// (оборванное TLS-рукопожатие и т.п.) — пробуем через Nexus:
  /// через активное подключение, а без него — через временный туннель.
  Future<FetchResult> _fetchSub(Subscription sub) async {
    try {
      return await SubscriptionService.fetch(sub);
    } catch (e) {
      if (!isTransportError(e)) rethrow;
      Object last = e;
      if (isDesktop && state == ConnState.connected && !core.blocked) {
        try {
          return await SubscriptionService.fetch(sub,
              proxy: '127.0.0.1:$activeHttpPort');
        } catch (e2) {
          last = e2;
        }
      }
      // Временный туннель: сначала выбранный сервер, затем ещё пара.
      final cands = <ServerProfile>[
        if (selected != null) selected!,
        ...servers.where((x) => x.id != selectedId && (x.ping ?? 0) >= 0),
      ].take(3);
      for (final c in cands) {
        try {
          final r = await core.viaTunnel(c, _configFor(c),
              (proxy) => SubscriptionService.fetch(sub, proxy: proxy));
          if (r != null) return r;
        } catch (e3) {
          if (!isTransportError(e3)) rethrow;
          last = e3;
        }
      }
      throw Exception(transportErrorText(last));
    }
  }

  /// При каждом подключении и переподключении VPN обновляем подписки:
  /// подписку текущего сервера — не чаще раза в 2 минуты (чтобы не
  /// дёргать сервер при серии переподключений), остальные — раз в час.
  /// Загрузка идёт уже через туннель, так что блокировки ей не мешают.
  Future<void> _refreshOnConnect() async {
    if (!settings.autoUpdateOnStart || subscriptions.isEmpty) return;
    await Future.delayed(const Duration(seconds: 3));
    if (state != ConnState.connected) return;
    final mainId = selected?.subscriptionId;
    final now = DateTime.now();
    final list = [...subscriptions]
      ..sort((a, b) => (a.id == mainId ? 0 : 1).compareTo(b.id == mainId ? 0 : 1));
    for (final sub in list) {
      if (refreshing.contains(sub.id)) continue;
      final gap = sub.id == mainId
          ? const Duration(minutes: 2)
          : const Duration(hours: 1);
      final last = sub.updatedAt;
      if (last != null && now.difference(last) < gap) continue;
      final before = selected?.link;
      await refresh(sub, silent: true);
      // Ключ текущего сервера поменялся (панель выдала новый) —
      // переподключаемся уже с новыми настройками.
      if (sub.id == mainId &&
          state == ConnState.connected &&
          selected != null &&
          before != null &&
          !_sameLink(selected!.link, before)) {
        await reconnectIfActive();
        return;
      }
    }
  }

  /// Тот же сервер с теми же ключами? 3x-ui при каждой выдаче подписки
  /// подставляет случайный spx (путь маскировки Reality) — его и название
  /// не сравниваем, иначе каждое обновление вызывало бы переподключение.
  static bool _sameLink(String a, String b) {
    String norm(String l) {
      var x = l.split('#').first;
      x = x.replaceAllMapped(
          RegExp(r'([?&])spx=[^&]*&?'), (m) => m.group(1)!);
      return x.replaceAll(RegExp(r'[?&]$'), '');
    }

    return norm(a) == norm(b);
  }

  Future<Subscription> addSubscription(String url) async {
    final existing = subscriptions.where((s) => s.url == url).toList();
    if (existing.isNotEmpty) {
      await refresh(existing.first);
      return existing.first;
    }
    final sub = Subscription(id: newId(), url: url, title: titleFromUrl(url));
    final res = await _fetchSub(sub);
    subscriptions.add(res.meta);
    servers.addAll(res.servers);
    _applyAliases();
    // Небольшую подписку сразу проверяем — задержки видны без лишнего нажатия.
    if (res.servers.length <= 30) unawaited(pingMany(res.servers));
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
      final res = await _fetchSub(sub);
      // Сохраняем выбор сервера, если он остался в подписке.
      final sel = selected;
      final keepLink = sel?.subscriptionId == sub.id ? sel?.link : null;
      final keepName = sel?.subscriptionId == sub.id ? sel?.name : null;
      // Задержки сохраняем: адрес сервера тот же — замер ещё актуален.
      final oldPing = {
        for (final s in servers.where((s) => s.subscriptionId == sub.id))
          s.aliasKey: s.ping
      };
      for (final s in res.servers) {
        s.ping = oldPing[s.aliasKey];
      }
      servers.removeWhere((s) => s.subscriptionId == sub.id);
      servers.addAll(res.servers);
      _applyAliases();
      if (keepLink != null) {
        final match =
            res.servers.where((s) => _sameLink(s.link, keepLink)).toList();
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

  static String _fmtDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours} ч ${d.inMinutes % 60} мин';
    if (d.inMinutes > 0) return '${d.inMinutes} мин';
    return '${d.inSeconds} с';
  }

  static String _fmtBytes(int b) {
    const u = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v < 10 && i > 0 ? v.toStringAsFixed(1) : v.round()} ${u[i]}';
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
    _retryTimer?.cancel();
    _connectGuard?.cancel();
    _notifyTimer?.cancel();
    _stopHealth();
    core.dispose();
    super.dispose();
  }
}
