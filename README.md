# Nexus

Клиент для подписок **NEXUS_VPN** (и любых панелей 3x-ui / Marzban / Remnawave) для **Android** и **Windows**.
Аналог Happ — Proxy Utility в собственном дизайне «тёмный неон».

## Что умеет

- Подписки по ссылке `https://…` — с трафиком, сроком действия и названием из заголовков панели
  (`subscription-userinfo`, `profile-title`, `announce`)
- Отдельные ключи: `vless://`, `vmess://`, `trojan://`, `ss://`, `socks://`, `hysteria2://`
- Вставка из буфера одной кнопкой
- Пинг всех серверов и «самый быстрый» в один тап
- **Умный режим**: российские сайты и IP — напрямую, остальное — через VPN. Или «весь трафик»
- Android: режим VPN (весь телефон) или только локальный прокси
- Windows: системный прокси включается/выключается автоматически, скорость и трафик в реальном времени
- Ядро — Xray-core (REALITY, XTLS-Vision, xhttp, gRPC, WS)

## Как собрать (без Android Studio и Visual Studio)

Всё собирает GitHub Actions.

1. Создайте на GitHub **приватный** репозиторий, например `nexus-app`.
2. Положите в него содержимое этой папки и сделайте **Commit** → **Push origin** в GitHub Desktop.
3. Добавьте секреты подписи APK (один раз): репозиторий → **Settings → Secrets and variables → Actions → New repository secret**.
   Значения — в файле `github-secrets.txt`, который пришёл вместе с проектом:
   `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
   Без них APK соберётся, но каждую новую версию придётся ставить, удалив старую.
4. Откройте вкладку **Actions** → «Сборка Nexus». Через 10–15 минут внизу страницы запуска появятся:
   - **Nexus-Android** — `Nexus-…-universal.apk` (подходит любому телефону), `arm64` (большинство современных), `armv7` (старые)
   - **Nexus-Windows** — `Nexus-Setup-….exe` (установщик) и `.zip` (портативная версия)

### Выпуск версии

Поменяйте `version:` в `pubspec.yaml`, закоммитьте, затем создайте тег (GitHub Desktop → History → правый клик по коммиту → Create Tag) вида `v1.0.1` и сделайте **Push origin**. Готовые файлы появятся во вкладке **Releases** — эту ссылку удобно давать пользователям в Discord-боте.

## Устройство проекта

```
lib/
  main.dart                    окно, навигация (нижняя панель на телефоне, боковая на ПК)
  models.dart                  сервер, подписка, настройки
  state/app_state.dart         логика: подписки, выбор, подключение, пинг
  services/
    subscription_service.dart  загрузка и разбор подписок
    config_builder.dart        сборка конфига Xray + маршрутизация
  core/
    android_core.dart          VpnService через flutter_v2ray_client
    windows_core.dart          nexus-core.exe (Xray) + системный прокси через реестр
  ui/                          тема, виджеты, экраны
tool/
  patch_platforms.py           донастройка android/ и windows/ после flutter create
  nexus.iss                    установщик Windows (Inno Setup)
.github/workflows/build.yml    сборка APK, Windows и релизов
```

Папки `android/` и `windows/` в репозиторий не кладутся — CI создаёт их сам и применяет `tool/patch_platforms.py`.

## Если сборка упала

Откройте упавший шаг в Actions, скопируйте последние ~40 строк лога и пришлите — поправим.
