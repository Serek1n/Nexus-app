// Английский перевод интерфейса. Ключ — русская строка из кода.
// Строки без перевода показываются по-русски.
const kEn = <String, String>{
  '  · безлимит':
      '  · unlimited',
  '  из {0}':
      '  of {0}',
  ' · {0} не отвечают':
      ' · {0} not responding',
  ' · от {0} мс':
      ' · from {0} ms',
  'Android может отключать VPN в фоне — разрешите Nexus работать без ограничений':
      'Android may stop the VPN in the background — let Nexus run without restrictions',
  'Android не даёт поставить старую версию поверх новой. Скопируйте подписки, удалите Nexus, скачайте нужную версию со страницы релиза и вставьте подписки обратно.':
      'Android won\'t install an older version over a newer one. Copy your subscriptions, uninstall Nexus, download the version you need from the release page and paste the subscriptions back.',
  'GitHub ответил {0}':
      'GitHub responded {0}',
  'GitHub ответил {0} на {1}':
      'GitHub responded {0} to {1}',
  'HTTP · без шифрования':
      'HTTP · not encrypted',
  'IP выхода: {0}{1}':
      'Exit IP: {0}{1}',
  'Nexus · Авто':
      'Nexus · Auto',
  'Nexus сам держит соединение через самый быстрый сервер подписки и незаметно переходит на другой, если этот упал':
      'Nexus keeps you on the fastest server of the subscription and quietly switches to another one if it goes down',
  'Nexus стартует свёрнутым в трей':
      'Nexus starts minimized to the tray',
  'Nexus установит выбранную версию и перезапустится. Подписки и настройки сохранятся. Текущую версию автоматически предлагать не будем — только более новые.':
      'Nexus will install the selected version and restart. Subscriptions and settings are kept. The current version won\'t be offered automatically again — only newer ones.',
  'Telegram Desktop не всегда использует системный прокси — добавим ему прокси Nexus':
      'Telegram Desktop doesn\'t always use the system proxy — we\'ll add the Nexus proxy to it',
  'Telegram не установлен':
      'Telegram is not installed',
  'VPN включён в другом приложении — Nexus отключился. Нажмите «Подключить», чтобы вернуть его':
      'A VPN was turned on in another app — Nexus disconnected. Tap “Connect” to get it back',
  'VPN оборвался — интернет заблокирован, чтобы ничего не ушло мимо':
      'The VPN dropped — internet is blocked so nothing leaks around it',
  'Windows не дал прав администратора — TUN не включён':
      'Windows didn\'t grant administrator rights — TUN is not enabled',
  'https://… или vless://…':
      'https://… or vless://…',
  '{0} {1} назад':
      '{0} {1} ago',
  '{0} · без лимита':
      '{0} · no limit',
  '{0} Б':
      '{0} B',
  '{0} Мбит/с':
      '{0} Mbps',
  '{0} из {1}':
      '{0} of {1}',
  '{0} мин':
      '{0} min',
  '{0} мс':
      '{0} ms',
  '{0} пропущена после отката':
      '{0} skipped after rollback',
  '{0} с':
      '{0} s',
  '{0} ч {1} мин':
      '{0} h {1} min',
  '{0}/с':
      '{0}/s',
  '«{0}» и все её серверы будут удалены.':
      '“{0}” and all its servers will be removed.',
  '«{0}» не отвечает — переключаюсь на «{1}»':
      '“{0}” is not responding — switching to “{1}”',
  '· текущая':
      '· current',
  'АКТИВЕН':
      'ACTIVE',
  'Абсолютно всё идёт через сервер Nexus':
      'Absolutely everything goes through the Nexus server',
  'Авто':
      'Auto',
  'Автовыбор при сбое':
      'Auto-switch on failure',
  'Автообновление ядра':
      'Auto-update core',
  'Автоподключение':
      'Auto-connect',
  'Б':
      'B',
  'Бессрочно':
      'No expiry',
  'Блокировать рекламу':
      'Block ads',
  'Более ранних версий пока нет':
      'No earlier versions yet',
  'Больше {0} приложений: банки, Госуслуги, VK, Яндекс, маркетплейсы. Список обновляется сам':
      'Over {0} apps: banks, Gosuslugi, VK, Yandex, marketplaces. The list updates itself',
  'Браузеры и программы Windows автоматически пойдут через Nexus':
      'Browsers and Windows programs will go through Nexus automatically',
  'Будет добавлен сервер {0}.':
      'Server {0} will be added.',
  'Будут удалены все подписки, серверы и настройки.':
      'All subscriptions, servers and settings will be deleted.',
  'Буфер обмена пуст':
      'Clipboard is empty',
  'В QR-коде нет текста':
      'The QR code has no text',
  'В архиве нет xray.exe':
      'xray.exe is missing from the archive',
  'В избранное':
      'Add to favorites',
  'В копии — ваши подписки и ключи серверов. Придумайте пароль не короче 6 символов.':
      'The backup contains your subscriptions and server keys. Choose a password of at least 6 characters.',
  'В настройках VPN выберите Nexus и включите «Постоянная VPN» и «Блокировать соединения без VPN»':
      'In VPN settings, choose Nexus and turn on “Always-on VPN” and “Block connections without VPN”',
  'В подписке не найдено ни одного сервера':
      'No servers found in the subscription',
  'В релизе {0} нет сборки для Windows':
      'Release {0} has no Windows build',
  'В релизе нет файла для этого устройства':
      'The release has no file for this device',
  'Вернуть исходное':
      'Restore original',
  'Версия':
      'Version',
  'Версия {0}':
      'Version {0}',
  'Весь трафик':
      'All traffic',
  'Весь трафик телефона идёт через Nexus':
      'All phone traffic goes through Nexus',
  'Включён, но Nexus запущен без прав администратора — работает системный прокси':
      'On, but Nexus is running without administrator rights — the system proxy is used',
  'Внимание: трафик идёт мимо VPN':
      'Warning: traffic is bypassing the VPN',
  'Восстановить':
      'Restore',
  'Восстановлено: подписок {0}, серверов {1}, настройки':
      'Restored: {0} subscriptions, {1} servers, settings',
  'Все':
      'All',
  'Все приложения через VPN':
      'All apps through the VPN',
  'Все программы через Nexus, как VPN на телефоне. Нужны права администратора':
      'All programs through Nexus, like a VPN on a phone. Requires administrator rights',
  'Всегда напрямую':
      'Always direct',
  'Всегда через VPN':
      'Always through VPN',
  'Всего':
      'Total',
  'Вставить из буфера обмена':
      'Paste from clipboard',
  'Вставить ссылку':
      'Paste link',
  'Вставьте ссылку из бота NEXUS':
      'Paste the link from the NEXUS bot',
  'Выберите сайты, которые всегда идут через VPN или напрямую':
      'Choose sites that always go through the VPN or directly',
  'Выбран: {0}':
      'Selected: {0}',
  'Выход':
      'Quit',
  'ГБ':
      'GB',
  'Гео-база {0} не прошла проверку и пропущена':
      'Geo database {0} failed verification and was skipped',
  'Главная':
      'Home',
  'Готовлю {0}…':
      'Preparing {0}…',
  'Готово к установке':
      'Ready to install',
  'ДЕНЬ':
      'DAY',
  'ДНЕЙ':
      'DAYS',
  'ДНЯ':
      'DAYS',
  'Данные':
      'Data',
  'Держать соединение':
      'Keep connection alive',
  'До {0}':
      'Until {0}',
  'Добавить':
      'Add',
  'Добавить подписку':
      'Add subscription',
  'Добавить подписку?':
      'Add subscription?',
  'Добавить сервер?':
      'Add server?',
  'Добавлено подписок: {0} из {1}':
      'Subscriptions added: {0} of {1}',
  'Добавлено серверов: {0}':
      'Servers added: {0}',
  'Добавлены вручную':
      'Added manually',
  'Добавьте подписку':
      'Add a subscription',
  'Добавьте подписку из бота — серверы появятся здесь':
      'Add a subscription from the bot — servers will appear here',
  'Доступна {0}':
      '{0} available',
  'Доступно обновление':
      'Update available',
  'Если VPN оборвётся, интернет блокируется, а не идёт напрямую':
      'If the VPN drops, internet is blocked instead of going direct',
  'Если провайдер блокирует подключение к серверу: Nexus режет первый пакет на части, и его сложнее распознать. Подключение чуть медленнее':
      'If your provider blocks connections to the server: Nexus splits the first packet into pieces so it\'s harder to detect. Connecting is a bit slower',
  'Если сервер не пропускает трафик, Nexus сам переключится на следующий':
      'If a server doesn\'t pass traffic, Nexus switches to the next one by itself',
  'Ещё раз':
      'Repeat',
  'Журнал':
      'Log',
  'Журнал пуст':
      'Log is empty',
  'Журнал ядра':
      'Core log',
  'Загружено {0} — применится при следующем подключении':
      'Downloaded {0} — applies on next connection',
  'Загрузка':
      'Download',
  'Загрузка {0}%':
      'Downloading {0}%',
  'Загрузка не удалась (код {0})':
      'Download failed (code {0})',
  'Закрыть':
      'Close',
  'Запрет скриншотов и размытие в списке недавних приложений':
      'Blocks screenshots and blurs the app in recent apps',
  'Запуск':
      'Startup',
  'Запуск ядра: {0}':
      'Starting core: {0}',
  'Запускать вместе с Windows':
      'Start with Windows',
  'Защита':
      'Protection',
  'ИСТЕКЛА':
      'EXPIRED',
  'Избранное':
      'Favorites',
  'Измените запрос поиска':
      'Change your search',
  'Использовано {0}% трафика подписки':
      '{0}% of subscription traffic used',
  'Истекла':
      'Expired',
  'Источник обновлений не задан в сборке':
      'No update source configured in this build',
  'КБ':
      'KB',
  'Как в системе':
      'System default',
  'Канал не отвечает — переподключаюсь…':
      'Connection not responding — reconnecting…',
  'Ключ скопирован':
      'Key copied',
  'Кнопка «закрыть» прячет окно, VPN продолжает работать. Выйти можно из меню значка в трее':
      'The close button hides the window, the VPN keeps running. Quit from the tray icon menu',
  'Контрольная сумма не совпала — обновление отменено':
      'Checksum mismatch — update cancelled',
  'Контрольная сумма ядра не совпала — обновление отменено':
      'Core checksum mismatch — update cancelled',
  'Копия повреждена':
      'The backup is corrupted',
  'Копия повреждена — скопируйте её целиком':
      'The backup is corrupted — copy it in full',
  'Лимит устройств подписки исчерпан — отключите старое устройство в боте или попросите увеличить лимит':
      'The subscription\'s device limit is reached — remove an old device in the bot or ask for a higher limit',
  'Личный кабинет':
      'Account',
  'Локальный прокси':
      'Local proxy',
  'МБ':
      'MB',
  'Маршрутизация':
      'Routing',
  'Наведите камеру на QR подписки или ключа':
      'Point the camera at a subscription or key QR code',
  'Нажмите «Установить» — скачаем и проверим':
      'Tap “Install” — we\'ll download and verify it',
  'Нажмите, чтобы подключиться':
      'Tap to connect',
  'Название подписки':
      'Subscription name',
  'Название сервера':
      'Server name',
  'Напрямую автоматически':
      'Direct automatically',
  'Настройки':
      'Settings',
  'Не короче 6 символов':
      'At least 6 characters',
  'Не найдено ни одной поддерживаемой ссылки':
      'No supported links found',
  'Не найдено ядро {0} рядом с программой. Переустановите Nexus из архива целиком.':
      'Core {0} not found next to the program. Reinstall Nexus from the full archive.',
  'Не подключено':
      'Not connected',
  'Не удалось загрузить ни одну подписку':
      'Couldn\'t load any subscription',
  'Не удалось запустить ядро: {0}':
      'Couldn\'t start the core: {0}',
  'Не удалось измерить скорость':
      'Couldn\'t measure the speed',
  'Не удалось открыть установщик':
      'Couldn\'t open the installer',
  'Не удалось подключиться за 30 секунд':
      'Couldn\'t connect within 30 seconds',
  'Не удалось построить QR-код — скопируйте ссылку':
      'Couldn\'t build a QR code — copy the link',
  'Не удалось применить обновление ядра: {0}':
      'Couldn\'t apply the core update: {0}',
  'Не удалось разобрать ни один сервер подписки':
      'Couldn\'t parse any server in the subscription',
  'Не удалось разобрать ссылки из подписки':
      'Couldn\'t parse the links in the subscription',
  'Не удалось узнать последнюю версию (код {0})':
      'Couldn\'t get the latest version (code {0})',
  'Не удалось установить защищённое соединение с сервером подписки — похоже, адрес блокирует провайдер. Подключитесь к VPN и повторите':
      'Couldn\'t establish a secure connection to the subscription server — your provider seems to block it. Connect to the VPN and try again',
  'Не удаётся подключиться к «{0}». Попробуйте другой сервер':
      'Can\'t connect to “{0}”. Try another server',
  'Неверный пароль':
      'Wrong password',
  'Нет контрольной суммы для {0}':
      'No checksum for {0}',
  'Нет подписок':
      'No subscriptions',
  'Нет разрешения на VPN — разрешите его в системном окне':
      'No VPN permission — allow it in the system dialog',
  'Нет соединения':
      'No connection',
  'Нет файла wintun.dll рядом с ядром — режим TUN недоступен, работаю через системный прокси. Переустановите Nexus':
      'wintun.dll is missing next to the core — TUN mode is unavailable, using the system proxy. Reinstall Nexus',
  'Ни один сервер не отвечает — проверьте интернет или подписку':
      'No server is responding — check your internet or subscription',
  'Ничего не найдено':
      'Nothing found',
  'Новые версии берутся с GitHub XTLS/Xray-core':
      'New versions come from GitHub XTLS/Xray-core',
  'Новые версии приходят с GitHub':
      'New versions come from GitHub',
  'Нужны права администратора':
      'Administrator rights required',
  'О приложении':
      'About',
  'ОСТАЛОСЬ {0} {1}':
      '{0} {1} LEFT',
  'ОТКЛЮЧИТЬ':
      'DISCONNECT',
  'Обновить':
      'Refresh',
  'Обновить все':
      'Refresh all',
  'Обновление «{0}»: {1}':
      'Updating “{0}”: {1}',
  'Обновления Nexus':
      'Nexus updates',
  'Обновлено до {0}':
      'Updated to {0}',
  'Обновляется вместе с приложением':
      'Updated together with the app',
  'Обновлять подписки':
      'Update subscriptions',
  'Обновляются автоматически при запуске':
      'Updated automatically on launch',
  'Обход блокировок':
      'Bypass blocking',
  'Отдача':
      'Upload',
  'Откатить':
      'Roll back',
  'Откатить версию':
      'Roll back version',
  'Откатить на {0}?':
      'Roll back to {0}?',
  'Отключение…':
      'Disconnecting…',
  'Отключено':
      'Disconnected',
  'Отключите для Nexus экономию батареи, чтобы VPN не обрывался':
      'Turn off battery saving for Nexus so the VPN doesn\'t drop',
  'Отключить':
      'Disconnect',
  'Открыть':
      'Open',
  'Открыть Nexus':
      'Open Nexus',
  'Отмена':
      'Cancel',
  'Отправить':
      'Send',
  'Отчёт для поддержки':
      'Report for support',
  'Отчёт скопирован — отправьте его в поддержку. Ключей и ссылок подписок в нём нет':
      'Report copied — send it to support. It contains no keys or subscription links',
  'Очищать буфер обмена':
      'Clear clipboard',
  'Ошибка инициализации ядра: {0}':
      'Core initialization error: {0}',
  'Пароли не совпадают':
      'Passwords don\'t match',
  'Пароль':
      'Password',
  'Пароль для копии':
      'Backup password',
  'Пароль от копии':
      'Backup password',
  'Пароль — не короче 6 символов':
      'Password must be at least 6 characters',
  'Перезапуск не удался: {0}':
      'Restart failed: {0}',
  'Перезапустить':
      'Restart',
  'Переименовать':
      'Rename',
  'Переподключаться при обрыве и раз в 45 секунд проверять, что трафик идёт':
      'Reconnect on drops and check every 45 seconds that traffic flows',
  'Переподключить':
      'Reconnect',
  'Платформа':
      'Platform',
  'По одному сайту или IP в строке. Поддомены входят автоматически: «ozon.ru» — это и «www.ozon.ru». Свои правила важнее режима маршрутизации.':
      'One site or IP per line. Subdomains are included automatically: “ozon.ru” also covers “www.ozon.ru”. Your rules take priority over the routing mode.',
  'По этой ссылке получают все серверы подписки и тратят её трафик. Делитесь только с теми, кому доверяете, и если владелец подписки не против.':
      'This link gives access to all servers of the subscription and uses its traffic. Share only with people you trust, and only if the subscription owner agrees.',
  'Поддержка':
      'Support',
  'Поделиться (QR)':
      'Share (QR)',
  'Подключаться сразу после запуска':
      'Connect right after launch',
  'Подключение':
      'Connection',
  'Подключение…':
      'Connecting…',
  'Подключено':
      'Connected',
  'Подключить':
      'Connect',
  'Подключить Telegram':
      'Connect Telegram',
  'Подозрительный путь в архиве обновления':
      'Suspicious path in the update archive',
  'Подписка «{0}»':
      'Subscription “{0}”',
  'Подписка «{0}» добавлена: {1} серв.':
      'Subscription “{0}” added: {1} servers',
  'Подписка «{0}» закончилась — продлите её в боте':
      'Subscription “{0}” has expired — renew it in the bot',
  'Подписка «{0}» закончится завтра — продлите её в боте':
      'Subscription “{0}” ends tomorrow — renew it in the bot',
  'Подписка «{0}» закончится через 3 дня — продлите её в боте':
      'Subscription “{0}” ends in 3 days — renew it in the bot',
  'Подписка загружается без шифрования: её могут подменить или подсмотреть ключи. Попросите https-ссылку.':
      'The subscription is loaded without encryption: it can be tampered with or the keys spied on. Ask for an https link.',
  'Подписка заканчивается через {0} {1} — продлите её в боте':
      'Subscription ends in {0} {1} — renew it in the bot',
  'Подписка не найдена (404) — проверьте ссылку: возможно, она устарела, клиент удалён или срок истёк':
      'Subscription not found (404) — check the link: it may be outdated, the client deleted or expired',
  'Подписка с сайта {0} будет добавлена в Nexus.':
      'A subscription from {0} will be added to Nexus.',
  'Подписка слишком большая (больше 8 МБ)':
      'The subscription is too large (over 8 MB)',
  'Подписка указывает на адрес этого устройства — загрузка остановлена':
      'The subscription points to this device\'s own address — loading stopped',
  'Подписки':
      'Subscriptions',
  'Подписки, серверы и настройки под паролем. Восстановить — через «Добавить»':
      'Subscriptions, servers and settings under a password. Restore via “Add”',
  'Подпись релиза неверна — обновление отклонено':
      'Invalid release signature — update rejected',
  'Подтвердите прокси в окне Telegram':
      'Confirm the proxy in the Telegram window',
  'Подтвердите установку в системном окне':
      'Confirm the installation in the system dialog',
  'Поиск приложения':
      'Search apps',
  'Поиск сервера':
      'Search servers',
  'Пока нет серверов':
      'No servers yet',
  'Получите ссылку на подписку в Discord-боте NEXUS_VPN\nи вставьте её сюда':
      'Get a subscription link from the NEXUS_VPN Discord bot\nand paste it here',
  'Порты {0}/{1} заняты другой программой (например, Happ или v2rayN) — Nexus использует {2}/{3}':
      'Ports {0}/{1} are used by another program (e.g. Happ or v2rayN) — Nexus uses {2}/{3}',
  'После добавления ключа или подписки':
      'After adding a key or subscription',
  'Последние 14 дней':
      'Last 14 days',
  'При запуске, подключении и переподключении VPN':
      'On launch, connect and reconnect',
  'Приложения без VPN':
      'Apps without VPN',
  'Проверить':
      'Check',
  'Проверить задержку':
      'Test latency',
  'Проверить задержку группы':
      'Test group latency',
  'Проверка «{0}» ({1}): {2}{3}':
      'Check “{0}” ({1}): {2}{3}',
  'Проверка канала: «{0}» не ответил':
      'Connection check: “{0}” didn\'t respond',
  'Проверка: {0} из {1}':
      'Checking: {0} of {1}',
  'Проверять обновления':
      'Check for updates',
  'Проверяю задержку…':
      'Testing latency…',
  'Проверяю…':
      'Checking…',
  'Прошлая сессия: {0}':
      'Last session: {0}',
  'Пусто — вставьте ссылку':
      'Empty — paste a link',
  'Работа в фоне':
      'Background',
  'Работа в фоне разрешена':
      'Background work allowed',
  'Раз в сутки проверять и предлагать обновление':
      'Check daily and offer the update',
  'Раз в сутки проверять и ставить новую версию':
      'Check daily and install the new version',
  'Разрешите Nexus устанавливать приложения и нажмите «Установить» ещё раз':
      'Allow Nexus to install apps and tap “Install” again',
  'Разрешить':
      'Allow',
  'Режим TUN':
      'TUN mode',
  'Режим TUN работает только с правами администратора — пока Nexus работает через системный прокси. Включите TUN в настройках ещё раз, чтобы перезапустить Nexus от администратора':
      'TUN mode needs administrator rights — for now Nexus uses the system proxy. Turn TUN on in settings again to restart Nexus as administrator',
  'Режим TUN создаёт виртуальную сетевую карту, и для этого Windows просит права администратора. Nexus перезапустится — подтвердите запрос Windows. Подписки и настройки сохранятся.':
      'TUN mode creates a virtual network adapter, so Windows asks for administrator rights. Nexus will restart — confirm the Windows prompt. Subscriptions and settings are kept.',
  'Режим TUN: весь трафик компьютера идёт через Nexus':
      'TUN mode: all computer traffic goes through Nexus',
  'Режим VPN':
      'VPN mode',
  'Режим «Авто»':
      'Auto mode',
  'Режим «Авто» выключен — выбран «{0}»':
      'Auto mode off — “{0}” selected',
  'Режим «Авто»: трафик идёт, задержка {0} мс':
      'Auto mode: traffic flows, latency {0} ms',
  'Резервная копия':
      'Backup',
  'Рекламные сети и трекеры не загружаются — страницы открываются быстрее, меньше трафика. Если сайт сломался, добавьте его в «Свои правила»':
      'Ad networks and trackers don\'t load — pages open faster and use less traffic. If a site breaks, add it to “Custom rules”',
  'Релиз не подписан — пропущен':
      'Release is not signed — skipped',
  'Релизы недоступны — репозиторий закрыт или пуст':
      'Releases unavailable — the repository is private or empty',
  'Российские приложения напрямую':
      'Russian apps direct',
  'Российские сайты, IP и приложения (Госуслуги, банки, VK, Яндекс) работают напрямую, без VPN; остальное — через Nexus':
      'Russian sites, IPs and apps (Gosuslugi, banks, VK, Yandex) work directly without the VPN; everything else goes through Nexus',
  'Российские — напрямую':
      'Russian — direct',
  'Сайты видят ваш российский IP — трафик идёт мимо VPN. Нажмите, чтобы переподключиться':
      'Sites see your Russian IP — traffic is bypassing the VPN. Tap to reconnect',
  'Самый быстрый':
      'Fastest',
  'Самый быстрый из {0}{1}':
      'Fastest of {0}{1}',
  'Сбросить':
      'Reset',
  'Сбросить всё':
      'Reset everything',
  'Сбросить всё?':
      'Reset everything?',
  'Сбросить статистику':
      'Reset statistics',
  'Сбросить статистику?':
      'Reset statistics?',
  'Свежий Xray приходит обновлением Nexus':
      'Fresh Xray arrives with Nexus updates',
  'Свои правила':
      'Custom rules',
  'Сворачивать в трей':
      'Minimize to tray',
  'Связь пропала — переподключаюсь (попытка {0})…':
      'Connection lost — reconnecting (attempt {0})…',
  'Сегодня':
      'Today',
  'Сегодня: {0}':
      'Today: {0}',
  'Сейчас включён режим «Весь трафик»: российские приложения идут через VPN. Отмеченные вручную — всегда напрямую.':
      '“All traffic” mode is on: Russian apps go through the VPN. Apps you check manually always go direct.',
  'Сейчас установлена {0}. Выберите версию, которая работала хорошо.':
      '{0} is installed now. Choose a version that worked well.',
  'Сейчас: {0}':
      'Now: {0}',
  'Сервер':
      'Server',
  'Сервер «{0}»':
      'Server “{0}”',
  'Сервер ответил кодом {0}':
      'Server responded with code {0}',
  'Сервер подписки не ответил вовремя':
      'The subscription server didn\'t respond in time',
  'Сервер подписки недоступен — проверьте интернет или подключитесь к VPN':
      'The subscription server is unreachable — check your internet or connect to the VPN',
  'Сервер подписки отвечает бесконечными перенаправлениями':
      'The subscription server keeps redirecting endlessly',
  'Сервер подписки перенаправил на незащищённый адрес — загрузка остановлена':
      'The subscription server redirected to an insecure address — loading stopped',
  'Серверы':
      'Servers',
  'Сертификат сервера подписки недействителен или просрочен — сообщите владельцу подписки':
      'The subscription server certificate is invalid or expired — tell the subscription owner',
  'Система может остановить VPN':
      'The system may stop the VPN',
  'Системный прокси':
      'System proxy',
  'Сканер QR недоступен на этом устройстве':
      'QR scanner is not available on this device',
  'Сканер QR недоступен: {0}':
      'QR scanner unavailable: {0}',
  'Сканировать QR-код':
      'Scan QR code',
  'Скачанное ядро не запускается':
      'The downloaded core doesn\'t start',
  'Скачано и проверено — можно установить':
      'Downloaded and verified — ready to install',
  'Скопировано':
      'Copied',
  'Скопировано подписок: {0}':
      'Subscriptions copied: {0}',
  'Скопировано: {0}':
      'Copied: {0}',
  'Скопировать':
      'Copy',
  'Скопировать ключ':
      'Copy key',
  'Скопировать подписки':
      'Copy subscriptions',
  'Скопировать ссылку':
      'Copy link',
  'Скопируйте ссылку из бота и нажмите сюда':
      'Copy the link from the bot and tap here',
  'Скорость':
      'Speed',
  'Скрывать экран':
      'Hide screen',
  'Слишком большая копия':
      'The backup is too large',
  'Сначала добавьте подписку или сервер':
      'Add a subscription or server first',
  'Сначала подключитесь':
      'Connect first',
  'Соединение прервалось':
      'The connection was interrupted',
  'Создать':
      'Create',
  'Сообщать о новой версии; скачивание — по кнопке «Установить»':
      'Notify about new versions; download with the “Install” button',
  'Сортировка: как в подписке':
      'Sort: as in subscription',
  'Сортировка: по задержке':
      'Sort: by latency',
  'Сохранено: через VPN {0}, напрямую {1}':
      'Saved: {0} via VPN, {1} direct',
  'Сохраните строку в заметках или отправьте себе. Чтобы восстановить: «Добавить» → вставить её → ввести пароль. Без пароля копию не открыть — его нельзя восстановить.':
      'Save the string in your notes or send it to yourself. To restore: “Add” → paste it → enter the password. Without the password the backup can\'t be opened — it can\'t be recovered.',
  'Сохранить':
      'Save',
  'Ссылка на подписку (https://…) или ключ сервера (vless://, vmess://, trojan://, ss://)':
      'Subscription link (https://…) or server key (vless://, vmess://, trojan://, ss://)',
  'Ссылка подписки должна начинаться с https://':
      'A subscription link must start with https://',
  'Ссылка скопирована':
      'Link copied',
  'Ссылка слишком длинная для QR-кода — скопируйте её':
      'The link is too long for a QR code — copy it',
  'Статистика трафика':
      'Traffic statistics',
  'Считается только трафик через VPN, данные хранятся на этом устройстве. Оператор и провайдер могут считать иначе.':
      'Only VPN traffic is counted; the data is stored on this device. Your carrier or provider may count differently.',
  'ТБ':
      'TB',
  'Текст слишком длинный для QR-кода':
      'The text is too long for a QR code',
  'Тест скорости: {0} Мбит/с через «{1}»':
      'Speed test: {0} Mbps via “{1}”',
  'Только прокси 127.0.0.1:10807 — им сможет пользоваться любое приложение на телефоне':
      'Proxy only 127.0.0.1:10807 — any app on the phone can use it',
  'Только рабочие':
      'Working only',
  'Трафик через «{0}» идёт, задержка {1} мс':
      'Traffic flows via “{0}”, latency {1} ms',
  'Убрать из избранного':
      'Remove from favorites',
  'Удалить':
      'Delete',
  'Удалить подписку?':
      'Delete subscription?',
  'Умный режим':
      'Smart mode',
  'Умный режим (РФ напрямую)':
      'Smart mode (Russia direct)',
  'Устанавливаю, Nexus перезапустится…':
      'Installing, Nexus will restart…',
  'Установить':
      'Install',
  'Установить и перезапустить':
      'Install and restart',
  'Установить обновление':
      'Install update',
  'Установлена последняя версия':
      'The latest version is installed',
  'Через Nexus идут все программы: Telegram, игры, всё, что не смотрит на прокси':
      'All programs go through Nexus: Telegram, games, everything that ignores the proxy',
  'Через VPN: {0} · напрямую: {1}':
      'Via VPN: {0} · direct: {1}',
  'Через «{0}» трафик не проходит — сервер не ответил':
      'No traffic through “{0}” — the server didn\'t respond',
  'Что нового':
      'What\'s new',
  'Что нового в {0}':
      'What\'s new in {0}',
  'Экономия батареи не мешает Nexus':
      'Battery saving doesn\'t interfere with Nexus',
  'Эта версия подписана другим ключом, и Android не поставит её поверх текущей. Скопируйте подписки (Откатить версию → Скопировать подписки), удалите Nexus и установите новую версию со страницы релиза. Дальше обновления пойдут как обычно.':
      'This version is signed with a different key, so Android won\'t install it over the current one. Copy your subscriptions (Roll back version → Copy subscriptions), uninstall Nexus and install the new version from the release page. Updates will work as usual after that.',
  'Эта сборка без источника обновлений':
      'This build has no update source',
  'Эти серверы уже добавлены':
      'These servers are already added',
  'Это ключ доступа к серверу: с ним можно подключаться от вашего имени. Делитесь только с теми, кому доверяете.':
      'This is a server access key: anyone with it can connect as you. Share only with people you trust.',
  'Это не резервная копия Nexus или она из новой версии':
      'This isn\'t a Nexus backup, or it\'s from a newer version',
  'Ядро':
      'Core',
  'Ядро Xray':
      'Xray core',
  'Ядро завершилось (код {0})':
      'Core exited (code {0})',
  'Ядро не запустилось.{0}':
      'The core didn\'t start.{0}',
  'Ядро не работает — интернет заблокирован (kill switch)':
      'The core is down — internet is blocked (kill switch)',
  'Ядро не работает — отключение':
      'The core is down — disconnecting',
  'Ядро обновлено до {0}':
      'Core updated to {0}',
  'Ядро обновляется вместе с приложением':
      'The core is updated together with the app',
  'Ядро перестало работать — перезапуск ({0} из 3)':
      'The core stopped — restarting ({0} of 3)',
  'август':
      'August',
  'апрель':
      'April',
  'выбрано: {0}':
      'selected: {0}',
  'декабрь':
      'December',
  'день':
      'day',
  'дней':
      'days',
  'дня':
      'days',
  'ещё {0} {1}':
      '{0} {1} left',
  'ещё не обновлялась':
      'not updated yet',
  'или вручную':
      'or manually',
  'июль':
      'July',
  'июнь':
      'June',
  'локации':
      'locations',
  'локаций':
      'locations',
  'локация':
      'location',
  'май':
      'May',
  'март':
      'March',
  'минут':
      'minutes',
  'минуту':
      'minute',
  'минуты':
      'minutes',
  'не найдено':
      'not found',
  'не подключено':
      'not connected',
  'нет связи':
      'no connection',
  'нет сервисов Google Play':
      'no Google Play services',
  'ноябрь':
      'November',
  'октябрь':
      'October',
  'отключение…':
      'disconnecting…',
  'подключение…':
      'connecting…',
  'подключено':
      'connected',
  'подписку':
      'subscription',
  'сентябрь':
      'September',
  'сервер':
      'server',
  'сервер не ответил за 6 с':
      'server didn\'t respond within 6 s',
  'сервера':
      'servers',
  'серверов':
      'servers',
  'только что':
      'just now',
  'февраль':
      'February',
  'час':
      'hour',
  'часа':
      'hours',
  'часов':
      'hours',
  'ядро не запустилось':
      'core didn\'t start',
  'январь':
      'January',
  '— мс':
      '— ms',
};
