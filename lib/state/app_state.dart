import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../changelog.dart' show appVersion;
import '../core/vpn_core.dart';
import '../services/app_updater.dart';
import '../services/backup.dart';
import '../services/support_report.dart';
import '../models.dart';
import '../platform/android_system.dart';
import '../platform/win_dpapi.dart';
import '../services/config_builder.dart';
import '../services/net_probe.dart';
import '../services/ru_apps.dart';
import '../services/subscription_service.dart';
import '../services/traffic_log.dart';
import '../l10n.dart';

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

  /// Трафик через VPN по дням.
  final traffic = TrafficLog();
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
    SubscriptionService.appVersion = appVersion;
    settings = AppSettings.fromJsonString(_prefs.getString('settings'));
    L10n.apply(settings.language, PlatformDispatcher.instance.locale.languageCode);
    language.value = L10n.lang;
    traffic.load(_prefs);
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
    _syncExpiry();

    _stSub = core.states.listen(_onCoreState);
    _statsSub = core.stats.listen((s) {
      statsNotifier.value = s;
      traffic.onStats(s);
    });
    try {
      await core.init();
    } catch (e) {
      lastError = tr('Ошибка инициализации ядра: {0}', [e]);
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
      // Как просит панель (profile-update-interval), но не реже раза в 6 часов.
      for (final sub in [...subscriptions]) {
        final h = math.min(sub.updateHours ?? 6, 6);
        final stale = DateTime.now().subtract(Duration(hours: h));
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
    if (!silent) coreUpdateStatus = tr('Проверяю…');
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
    if (!silent) updateStatus = tr('Проверяю…');
    notifyListeners();
    try {
      final u = await AppUpdater.check();
      settings.lastAppCheck = DateTime.now().millisecondsSinceEpoch;
      _save();
      if (u == null) {
        appUpdate = null;
        updateFile = null;
        updateStatus = tr('Установлена последняя версия');
        return;
      }
      // После отката плохую версию сами не предлагаем — только по кнопке.
      if (silent && u.build <= settings.skippedBuild) {
        appUpdate = null;
        updateFile = null;
        updateStatus = tr('{0} пропущена после отката', [u.version]);
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
    updateStatus = tr('Готовлю {0}…', [r.version]);
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
        updateStatus = tr('Устанавливаю, Nexus перезапустится…');
        notifyListeners();
        if (state != ConnState.disconnected) await core.disconnect();
        await AppUpdater.install(f);
        await Future.delayed(const Duration(milliseconds: 500));
        await quitApp?.call();
      } else {
        await AppUpdater.install(f);
        updateStatus = tr('Подтвердите установку в системном окне');
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
  Future<void> flushSaves() {
    traffic.save();
    return _saveChain;
  }

  void _save() {
    final subs = jsonEncode(subscriptions.map((e) => e.toJson()).toList());
    final srv = jsonEncode(servers.map((e) => e.toJson()).toList());
    _saveChain = _saveChain.then((_) async {
      await _writeSecret('subscriptions', subs);
      await _writeSecret('servers', srv);
    }).catchError((_) {});
    if (selectedId != null) _prefs.setString('selected', selectedId!);
    _prefs.setString('settings', settings.toJsonString());
    _syncExpiry();
  }

  String _expirySig = '';

  /// Android: системные напоминания за 3 дня и за день до конца подписок
  /// (приходят, даже если Nexus закрыт).
  void _syncExpiry() {
    if (isDesktop) return;
    final list = [
      for (final s in subscriptions)
        if (s.expire != null) (s.id, s.title, s.expire!),
    ];
    final sig = '${L10n.lang}:' + list.map((e) => '${e.$1}|${e.$2}|${e.$3.millisecondsSinceEpoch}').join(';');
    if (sig == _expirySig) return;
    _expirySig = sig;
    unawaited(AndroidSystem.scheduleExpiry(list));
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
        ? (settings.autoMode
            ? tr('Режим «Авто»: трафик идёт, задержка {0} мс', [liveLatency])
            : tr('Трафик через «{0}» идёт, задержка {1} мс', [s.cleanName, liveLatency]))
        : tr('Через «{0}» трафик не проходит — сервер не ответил', [s.cleanName]));
    if (afterConnect && liveLatency == -1) await _failover(s);
    if (afterConnect && (liveLatency ?? -1) > 0) unawaited(checkExit());
  }

  // ───────────────────── IP выхода и тест скорости ─────────────────────

  /// Под каким IP и страной сайты видят пользователя сейчас.
  ExitInfo? exitInfo;
  bool exitChecking = false;

  /// Предупреждение: сайты видят российский IP, хотя сервер не в России —
  /// трафик идёт мимо VPN.
  String? exitWarning;

  /// Результат последнего теста скорости (Мбит/с) и текущее значение во
  /// время замера.
  double? speedMbps;
  double? speedLive;
  bool speedTesting = false;

  Future<void> checkExit() async {
    final proxy = state == ConnState.connected ? core.activeProxy : null;
    if (proxy == null || exitChecking) return;
    exitChecking = true;
    notifyListeners();
    final r = await NetProbe.exitInfo(proxy);
    exitChecking = false;
    if (state == ConnState.connected && r != null) {
      exitInfo = r;
      core.note(tr('IP выхода: {0}{1}', [r.ip, r.country.isEmpty ? '' : ' (${r.country})']));
      final serverCc = selected?.countryCode?.toUpperCase();
      exitWarning = r.country == 'RU' && serverCc != 'RU'
          ? tr('Сайты видят ваш российский IP — трафик идёт мимо VPN. Нажмите, чтобы переподключиться')
          : null;
      if (exitWarning != null) core.note(tr('Внимание: трафик идёт мимо VPN'));
    }
    notifyListeners();
  }

  /// Тест скорости загрузки через текущий сервер. Возвращает текст ошибки
  /// или null при успехе.
  Future<String?> runSpeedTest() async {
    final proxy = state == ConnState.connected ? core.activeProxy : null;
    if (proxy == null) return tr('Сначала подключитесь');
    if (speedTesting) return null;
    speedTesting = true;
    speedLive = 0;
    notifyListeners();
    var last = DateTime.now();
    final r = await NetProbe.downloadSpeed(proxy, onProgress: (v) {
      speedLive = v;
      final now = DateTime.now();
      if (now.difference(last).inMilliseconds >= 250) {
        last = now;
        notifyListeners();
      }
    });
    speedTesting = false;
    speedLive = null;
    if (state == ConnState.connected && r != null) {
      speedMbps = r;
      core.note(tr('Тест скорости: {0} Мбит/с через «{1}»', [r.toStringAsFixed(1), selected?.cleanName ?? '—']));
    }
    notifyListeners();
    if (state != ConnState.connected) return tr('Соединение прервалось');
    return r == null ? tr('Не удалось измерить скорость') : null;
  }

  /// Серверы, уже опробованные в текущей попытке подключения.
  final Set<String> _failoverTried = {};
  String? failoverNote;

  /// Сервер подключился, но трафик не идёт — пробуем следующие
  /// по задержке (до 3 штук), если включено «Автовыбор при сбое».
  Future<void> _failover(ServerProfile bad) async {
    if (!settings.autoFailover || settings.autoMode || core.blocked) return;
    _failoverTried.add(bad.id);
    if (_failoverTried.length > 3) {
      failoverNote = null;
      lastError = tr('Ни один сервер не отвечает — проверьте интернет или подписку');
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
    failoverNote = tr('«{0}» не отвечает — переключаюсь на «{1}»', [bad.cleanName, next.cleanName]);
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
    reconnectNote = tr('Связь пропала — переподключаюсь (попытка {0})…', [_retry]);
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
          lastError = tr('Не удаётся подключиться к «{0}». Попробуйте другой сервер', [s.cleanName]);
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
        lastError = tr('VPN включён в другом приложении — Nexus отключился. Нажмите «Подключить», чтобы вернуть его');
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
    if (d <= 0) core.note(tr('Проверка канала: «{0}» не ответил', [s.cleanName]));
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
    if (_deadReconnects == 0 || !settings.autoFailover || settings.autoMode) {
      _deadReconnects++;
      reconnectNote = tr('Канал не отвечает — переподключаюсь…');
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
    // VPN подняли плиткой или виджетом, пока Nexus был закрыт: держим его
    // так же, как после нажатия «Подключить».
    if (s == ConnState.connected && state == ConnState.disconnected) {
      _wantConnected = true;
    }
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
    if (s != ConnState.connected) {
      liveLatency = null;
      exitInfo = null;
      exitWarning = null;
      speedMbps = null;
    }
    if (s == ConnState.disconnected) {
      connectedAt = null;
      statsNotifier.value = const ConnStats();
      traffic.sessionEnded();
    }
    if (!isDesktop &&
        (s == ConnState.connected || s == ConnState.disconnected) &&
        s != state) {
      unawaited(AndroidSystem.setTileState(s == ConnState.connected,
          vpn: settings.androidVpnMode));
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
        blockAds: settings.blockAds,
        antiBlock: settings.antiBlock,
      );

  /// Серверы для режима «Авто»: подписка выбранного сервера (или все
  /// добавленные вручную), без заведомо мёртвых, от быстрых к медленным.
  /// Ядро периодически проверяет каждый сервер пула, а это трафик и
  /// батарея: на телефоне — до 6 серверов раз в 5 минут (≈15 МБ в сутки),
  /// на ПК — до 10 раз в 2 минуты.
  List<ServerProfile> autoPool([ServerProfile? around]) {
    final s = around ?? selected;
    if (s == null) return const [];
    final list = serversOf(s.subscriptionId)
        .where((x) => x.ping == null || x.ping! > 0)
        .toList()
      ..sort((a, b) {
        int k(ServerProfile x) => x.ping ?? 1 << 20;
        return k(a).compareTo(k(b));
      });
    final pool = list.take(isDesktop ? 10 : 6).toList();
    return pool.isEmpty ? [s] : pool;
  }

  /// Пул, с которым запущено текущее соединение «Авто» (nx-0, nx-1…).
  List<ServerProfile> activeAutoPool = const [];

  /// Режим «Авто»: через какой сервер идёт трафик сейчас и его задержка
  /// (по проверке ядра; известно только на Windows). null — неизвестно.
  (ServerProfile, int)? get autoCurrent {
    if (!settings.autoMode || state != ConnState.connected) return null;
    (ServerProfile, int)? best;
    core.autoStatus.forEach((tag, ms) {
      final i = int.tryParse(tag.replaceFirst(kAutoPrefix, ''));
      if (ms <= 0 || i == null || i >= activeAutoPool.length) return;
      if (best == null || ms < best!.$2) best = (activeAutoPool[i], ms);
    });
    return best;
  }

  String _autoConfig(ServerProfile s) => buildAutoConfig(
        activeAutoPool = autoPool(s),
        probeInterval: isDesktop ? '2m' : '5m',
        routing: settings.routing,
        desktop: isDesktop,
        lockLocalProxy: !isDesktop && settings.androidVpnMode,
        customProxy: settings.customProxy,
        customDirect: settings.customDirect,
        blockAds: settings.blockAds,
        antiBlock: settings.antiBlock,
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
      lastError = tr('Сначала добавьте подписку или сервер');
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
        lastError = tr('Не удалось подключиться за 30 секунд');
      }
      try {
        await core.disconnect();
      } catch (_) {}
      // Ядро промолчало — выходим из «Подключение…» сами.
      if (state == ConnState.connecting) _onCoreState(ConnState.disconnected);
    });
    try {
      await core.connect(
        remark: settings.autoMode ? tr('Nexus · Авто') : s.cleanName,
        config: settings.autoMode ? _autoConfig(s) : _configFor(s),
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
  /// Явный выбор сервера выключает режим «Авто» (возвращает true, если
  /// он был включён).
  Future<bool> select(ServerProfile s) async {
    final wasAuto = settings.autoMode;
    if (wasAuto) settings.autoMode = false;
    if (selectedId == s.id && !wasAuto) return false;
    selectedId = s.id;
    _save();
    notifyListeners();
    if (state == ConnState.connected) {
      await core.disconnect();
      await Future.delayed(const Duration(milliseconds: 400));
      await connect();
    }
    return wasAuto;
  }

  /// Язык интерфейса ('ru'/'en') — интерфейс пересобирается только при его смене.
  final language = ValueNotifier<String>(L10n.lang);

  /// Язык интерфейса: 'system', 'ru' или 'en'.
  void setLanguage(String v) {
    L10n.apply(v, PlatformDispatcher.instance.locale.languageCode);
    updateSettings((s) => s.language = v);
    language.value = L10n.lang;
    if (!isDesktop) {
      unawaited(AndroidSystem.setTileState(state == ConnState.connected,
          vpn: settings.androidVpnMode));
    }
  }

  /// Включает или выключает режим «Авто» и переподключается.
  Future<void> setAutoMode(bool on) async {
    updateSettings((s) => s.autoMode = on);
    if (on && servers.any((s) => s.ping == null)) {
      unawaited(pingMany(autoPool()));
    }
    await reconnectIfActive();
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
    if (text.isEmpty) throw Exception(tr('Пусто — вставьте ссылку'));

    if (isHttpUrl(text) && !text.contains('\n')) {
      final sub = await addSubscription(text);
      return tr('Подписка «{0}» добавлена: {1} серв.', [sub.title, serversOf(sub.id).length]);
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
      if (ok == 0) throw Exception(tr('Не удалось загрузить ни одну подписку'));
      return tr('Добавлено подписок: {0} из {1}', [ok, lines.length]);
    }

    final links = extractLinks(text);
    if (links.isEmpty) {
      throw Exception(tr('Не найдено ни одной поддерживаемой ссылки'));
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
    if (added == 0) throw Exception(tr('Эти серверы уже добавлены'));
    if (selectedId == null && first != null) selectedId = first.id;
    _save();
    notifyListeners();
    return tr('Добавлено серверов: {0}', [added]);
  }

  /// Загрузка подписки. Если провайдер не пускает к её серверу напрямую
  /// (оборванное TLS-рукопожатие и т.п.) — пробуем через Nexus:
  /// через активное подключение, а без него — через временный туннель.
  Future<FetchResult> _fetchSub(Subscription sub) async {
    // Подписка без шифрования (http): провайдер видел бы ссылку и ключи.
    // Если VPN подключён — сначала загружаем её через туннель.
    final tunnel = state == ConnState.connected ? core.activeProxy : null;
    if (tunnel != null && sub.url.startsWith('http://')) {
      try {
        return await SubscriptionService.fetch(sub, proxy: tunnel);
      } catch (e) {
        if (!isTransportError(e)) rethrow;
      }
    }
    try {
      return await SubscriptionService.fetch(sub);
    } catch (e) {
      if (!isTransportError(e)) rethrow;
      Object last = e;
      final via = state == ConnState.connected ? core.activeProxy : null;
      if (via != null) {
        try {
          return await SubscriptionService.fetch(sub, proxy: via);
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

  // ───────────────────────── отчёт для поддержки ─────────────────────────

  /// Сведения о приложении и соединении без ключей и токенов —
  /// чтобы клиент мог отправить их в поддержку одним сообщением.
  Future<String> supportReport() async {
    String d(DateTime? t) => t == null
        ? '—'
        : '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final st = settings;
    final s = selected;
    final b = StringBuffer()
      ..writeln('Nexus $appVersion · ${isDesktop ? 'Windows' : 'Android'} '
          '${Platform.operatingSystemVersion}')
      ..writeln('Xray: $coreVersion')
      ..writeln('Время: ${d(DateTime.now())}')
      ..writeln('Режим: ${st.routing.name}'
          '${isDesktop ? ' · TUN ${st.windowsTun ? 'вкл' : 'выкл'} · прокси ${st.windowsSystemProxy ? 'вкл' : 'выкл'}' : ' · VPN ${st.androidVpnMode ? 'вкл' : 'только прокси'}'}'
          ' · Авто ${st.autoMode ? 'вкл' : 'выкл'}'
          ' · обход ${st.antiBlock ? 'вкл' : 'выкл'}'
          ' · реклама ${st.blockAds ? 'блок' : 'нет'}'
          ' · своих правил ${st.customProxy.length + st.customDirect.length}')
      ..writeln('Состояние: ${state.name}'
          '${liveLatency == null ? '' : ' · задержка $liveLatency мс'}'
          '${core.modeWarning == null ? '' : ' · ${core.modeWarning}'}')
      ..writeln(s == null
          ? 'Сервер: не выбран'
          : 'Сервер: ${s.cleanName} · ${s.protocol} ${s.transport} · ${s.host}:${s.port}'
              '${s.ping == null ? '' : ' · пинг ${s.ping}'}');
    if (lastError != null) b.writeln('Ошибка: $lastError');
    b.writeln('Подписки: ${subscriptions.length}');
    for (final x in subscriptions) {
      b.writeln('  · ${x.title} (${Uri.tryParse(x.url)?.host ?? '?'}): '
          'серверов ${serversOf(x.id).length}, '
          'трафик ${x.used ~/ (1 << 20)}/${x.total == 0 ? '∞' : x.total ~/ (1 << 20)} МБ, '
          'до ${d(x.expire)}, обновлена ${d(x.updatedAt)}');
    }
    final logs = await core.fetchLogs();
    b.writeln('— журнал (последние строки) —');
    for (final l in logs.skip(logs.length > 80 ? logs.length - 80 : 0)) {
      b.writeln(l);
    }
    return redactSecrets(b.toString());
  }

  // ───────────────────────── резервная копия ─────────────────────────

  /// Подписки, свои серверы и настройки одной строкой, зашифрованной паролем.
  Future<String> exportBackup(String password) {
    final st = jsonDecode(settings.toJsonString()) as Map<String, dynamic>
      ..remove('lastCoreCheck')
      ..remove('lastAppCheck')
      ..remove('skippedBuild');
    return Backup.encrypt({
      'v': 1,
      'subscriptions': [
        for (final x in subscriptions) {'url': x.url, 'title': x.title},
      ],
      'servers': [
        for (final x in servers)
          if (x.subscriptionId == null) x.link,
      ],
      'settings': st,
    }, password);
  }

  /// Восстановление из резервной копии. Существующее не удаляется —
  /// добавляется недостающее. Возвращает текст результата.
  Future<String> importBackup(String text, String password) async {
    final j = await Backup.decrypt(text, password);
    var subs = 0, srv = 0;
    // Ограничения на случай испорченной или подсунутой копии.
    for (final e in (j['subscriptions'] as List? ?? const []).take(50)) {
      if (e is! Map) continue;
      final url = e['url'];
      if (url is! String || !isHttpUrl(url) || url.length > 2048) continue;
      if (subscriptions.any((x) => x.url == url)) continue;
      try {
        await addSubscription(url);
      } catch (_) {
        // Нет связи с сервером подписки — сохраняем, загрузится позже.
        final t = e['title'];
        subscriptions.add(Subscription(
            id: newId(),
            url: url,
            title: t is String && t.isNotEmpty && t.length <= 80
                ? t
                : titleFromUrl(url)));
      }
      subs++;
    }
    for (final l in (j['servers'] as List? ?? const []).take(1000)) {
      if (l is! String || l.length > 8192 || servers.any((x) => x.link == l)) {
        continue;
      }
      final p = profileFromLink(l);
      if (p != null) {
        servers.add(p);
        srv++;
      }
    }
    final st = j['settings'];
    if (st is Map<String, dynamic>) {
      final cur = jsonDecode(settings.toJsonString()) as Map<String, dynamic>;
      for (final k in st.keys) {
        if (const [
          'lastCoreCheck', 'lastAppCheck', 'skippedBuild',
          // Привязано к конкретному устройству.
          'launchAtStartup', 'windowsTun',
        ].contains(k)) {
          continue;
        }
        cur[k] = st[k];
      }
      settings = AppSettings.fromJsonString(jsonEncode(cur));
      _applyAliases();
    }
    if (selected == null && servers.isNotEmpty) selectedId = servers.first.id;
    _save();
    notifyListeners();
    return tr('Восстановлено: подписок {0}, серверов {1}, настройки', [subs, srv]);
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
      if (!silent) lastError = tr('Обновление «{0}»: {1}', [sub.title, _msg(e)]);
    } finally {
      refreshing.remove(sub.id);
      notifyListeners();
    }
  }

  Future<void> refreshAll({bool silent = false}) async {
    await Future.wait(subscriptions.map((s) => refresh(s, silent: silent)));
  }

  void removeSubscription(Subscription sub) {
    if (selected?.subscriptionId == sub.id) _forgetTileConfig();
    subscriptions.removeWhere((s) => s.id == sub.id);
    servers.removeWhere((s) => s.subscriptionId == sub.id);
    if (!servers.any((s) => s.id == selectedId)) {
      selectedId = servers.isEmpty ? null : servers.first.id;
    }
    _save();
    notifyListeners();
  }

  /// Плитка и виджет не должны подключаться к удалённому серверу.
  void _forgetTileConfig() {
    if (!isDesktop) unawaited(AndroidSystem.saveTileConfig());
  }

  void removeServer(ServerProfile s) {
    if (selectedId == s.id) _forgetTileConfig();
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
    traffic.clear();
    if (!isDesktop) {
      unawaited(AndroidSystem.saveTileConfig());
      unawaited(AndroidSystem.scheduleExpiry(const []));
      _expirySig = '';
    }
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
    if (d.inHours > 0) return tr('{0} ч {1} мин', [d.inHours, d.inMinutes % 60]);
    if (d.inMinutes > 0) return tr('{0} мин', [d.inMinutes]);
    return tr('{0} с', [d.inSeconds]);
  }

  static String _fmtBytes(int b) {
    final u = [tr('Б'), tr('КБ'), tr('МБ'), tr('ГБ'), tr('ТБ')];
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
    traffic.save();
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
