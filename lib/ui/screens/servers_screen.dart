import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../add_sheet.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, this.onSelected});
  final VoidCallback? onSelected;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _q = '';
  bool _byPing = false;

  /// Фильтр по подписке: null — все, '★' — избранное, '' — добавленные вручную.
  String? _filter;

  /// Свёрнутые группы (id подписки, '' — вручную).
  final Set<String> _collapsed = {};
  bool _collapseInit = false;

  /// Избранные — всегда сверху; внутри — по задержке, если выбрано.
  List<ServerProfile> _sorted(List<ServerProfile> list) {
    final app = AppScope.read(context);
    int fav(ServerProfile s) => app.isFavorite(s) ? 0 : 1;
    int key(ServerProfile s) =>
        (s.ping == null || s.ping! < 0) ? 1 << 30 : s.ping!;
    final out = [...list];
    out.sort((a, b) {
      final f = fav(a).compareTo(fav(b));
      if (f != 0 || !_byPing) return f;
      return key(a).compareTo(key(b));
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Группы: (ключ, название, серверы).
    final all = <(String, String, List<ServerProfile>)>[];
    for (final sub in app.subscriptions) {
      all.add((sub.id, sub.title, _sorted(app.serversOf(sub.id))));
    }
    final manual = _sorted(app.serversOf(null));
    if (manual.isNotEmpty) all.add(('', 'Добавлены вручную', manual));

    // При большом числе подписок сразу сворачиваем всё, кроме группы
    // с выбранным сервером, — список не превращается в простыню.
    if (!_collapseInit && all.isNotEmpty) {
      _collapseInit = true;
      if (all.length >= 3) {
        final sel = app.selected?.subscriptionId ?? '';
        for (final g in all) {
          if (g.$1 != sel) _collapsed.add(g.$1);
        }
      }
    }

    bool match(ServerProfile s) =>
        _q.isEmpty ||
        s.name.toLowerCase().contains(_q) ||
        s.host.toLowerCase().contains(_q);

    final favs = app.servers.where(app.isFavorite).toList();
    final List<(String, String, List<ServerProfile>)> groups = switch (_filter) {
      null => all,
      '★' => [('★', 'Избранное', _sorted(favs))],
      final f => all.where((g) => g.$1 == f).toList(),
    };
    // Поиск или фильтр — показываем группы развёрнутыми.
    final forceOpen = _q.isNotEmpty || _filter != null;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: PageHeader(
                title: 'Серверы',
                subtitle: app.servers.isEmpty
                    ? null
                    : '${app.servers.length} ${plural(app.servers.length, 'локация', 'локации', 'локаций')}',
                actions: [
                  NxIconButton(
                    icon: _byPing
                        ? Icons.sort_rounded
                        : Icons.format_list_bulleted_rounded,
                    tooltip: _byPing
                        ? 'Сортировка: по задержке'
                        : 'Сортировка: как в подписке',
                    onPressed: app.servers.isEmpty
                        ? null
                        : () => setState(() => _byPing = !_byPing),
                  ),
                  NxIconButton(
                    icon: Icons.speed_rounded,
                    tooltip: 'Проверить задержку',
                    spinning: app.pingingAll,
                    onPressed: app.servers.isEmpty ? null : app.pingAll,
                  ),
                  const SizedBox(width: 8),
                  NxIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Добавить',
                    onPressed: () => showAddSheet(context),
                  ),
                ],
              ),
            ),
          ),
          if (all.length > 1 || favs.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: 14),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _Chip(
                        label: 'Все',
                        count: app.servers.length,
                        selected: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      if (favs.isNotEmpty)
                        _Chip(
                          label: 'Избранное',
                          icon: Icons.star_rounded,
                          count: favs.length,
                          selected: _filter == '★',
                          onTap: () => setState(() => _filter = '★'),
                        ),
                      for (final g in all)
                        _Chip(
                          label: g.$2,
                          count: g.$3.length,
                          selected: _filter == g.$1,
                          onTap: () => setState(() => _filter = g.$1),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (app.servers.length > 6)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Поиск сервера',
                    prefixIcon: Icon(Icons.search_rounded, color: NX.text3),
                  ),
                ),
              ),
            ),
          if (app.servers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.dns_rounded,
                title: 'Пока нет серверов',
                text: 'Добавьте подписку из бота — серверы появятся здесь',
                action: NeonButton(
                  label: 'Добавить подписку',
                  icon: Icons.add_rounded,
                  onPressed: () => showAddSheet(context),
                ),
              ),
            )
          else
            for (final (key, title, list) in groups)
              if (list.any(match)) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: _GroupHeader(
                      title: title,
                      servers: list,
                      collapsed: !forceOpen && _collapsed.contains(key),
                      // Один фильтр — сворачивать незачем.
                      onToggle: forceOpen || groups.length == 1
                          ? null
                          : () => setState(() => _collapsed.contains(key)
                              ? _collapsed.remove(key)
                              : _collapsed.add(key)),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !forceOpen && _collapsed.contains(key)
                          ? const SizedBox(width: double.infinity)
                          : Column(
                              children: [
                                for (final (i, s)
                                    in list.where(match).indexed) ...[
                                  if (i > 0) const SizedBox(height: 8),
                                  _ServerTile(
                                    server: s,
                                    onSelected: widget.onSelected,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Фильтр-«таблетка» над списком.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? NX.violet.withValues(alpha: 0.16) : NX.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: selected
                    ? NX.violet.withValues(alpha: 0.5)
                    : NX.stroke),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: NX.amber),
                    const SizedBox(width: 5),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? NX.text : NX.text2)),
                  ),
                  const SizedBox(width: 6),
                  Text('$count',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected ? NX.violet : NX.text3)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Заголовок группы: название подписки, число серверов, лучшая задержка.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.servers,
    required this.collapsed,
    this.onToggle,
  });
  final String title;
  final List<ServerProfile> servers;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pings = servers
        .map((s) => s.ping)
        .whereType<int>()
        .where((p) => p > 0)
        .toList()
      ..sort();
    final hasActive = servers.any((s) => s.id == app.selectedId);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            if (onToggle != null) ...[
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded,
                    size: 20, color: NX.text3),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: NX.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            if (hasActive) ...[
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: app.state == ConnState.connected
                      ? NX.mint
                      : NX.violet,
                ),
              ),
            ],
            const Spacer(),
            Text(
              '${servers.length} '
              '${plural(servers.length, 'сервер', 'сервера', 'серверов')}'
              '${pings.isEmpty ? '' : ' · от ${pings.first} мс'}',
              style: const TextStyle(color: NX.text3, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, this.onSelected});
  final ServerProfile server;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final active = app.selected?.id == server.id;
    final live = active && app.state == ConnState.connected;
    return NeonCard(
      active: active,
      accent: live ? NX.mint : NX.violet,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      onTap: () async {
        await app.select(server);
        onSelected?.call();
      },
      onLongPress: () => _menu(context),
      child: Row(
        children: [
          ServerAvatar(server: server, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (app.isFavorite(server)) ...[
                    const Icon(Icons.star_rounded, size: 16, color: NX.amber),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(server.cleanName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ),
                ]),
                const SizedBox(height: 5),
                Row(children: [
                  Tag(server.protocol, color: NX.cyan),
                  if (live) ...[
                    const SizedBox(width: 6),
                    const Tag('АКТИВЕН', color: NX.mint),
                  ],
                ]),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => app.pingOne(server),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: PingBadge(
                ping: server.ping,
                loading: app.pingingAll && server.ping == null,
              ),
            ),
          ),
          IconButton(
            onPressed: () => _menu(context),
            icon: const Icon(Icons.more_vert_rounded,
                color: NX.text3, size: 20),
          ),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    final app = AppScope.read(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: NX.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: NX.strokeStrong)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(children: [
                  ServerAvatar(server: server, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(server.cleanName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ]),
              ),
              ListTile(
                leading: Icon(
                    app.isFavorite(server)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: NX.amber),
                title: Text(app.isFavorite(server)
                    ? 'Убрать из избранного'
                    : 'В избранное'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.toggleFavorite(server);
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed_rounded, color: NX.cyan),
                title: const Text('Проверить задержку'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.pingOne(server);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: NX.violet),
                title: const Text('Скопировать ключ'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: server.link));
                  Navigator.pop(ctx);
                  toast(context, 'Ключ скопирован');
                },
              ),
              if (server.subscriptionId == null)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline_rounded, color: NX.red),
                  title: const Text('Удалить',
                      style: TextStyle(color: NX.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    app.removeServer(server);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
