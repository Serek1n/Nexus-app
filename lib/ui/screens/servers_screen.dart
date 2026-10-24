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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final groups = <(String, List<ServerProfile>)>[];
    for (final sub in app.subscriptions) {
      groups.add((sub.title, app.serversOf(sub.id)));
    }
    final manual = app.serversOf(null);
    if (manual.isNotEmpty) groups.add(('Добавлены вручную', manual));

    bool match(ServerProfile s) =>
        _q.isEmpty ||
        s.name.toLowerCase().contains(_q) ||
        s.host.toLowerCase().contains(_q);

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
            for (final (title, list) in groups) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: SectionTitle(title)),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: list.where(match).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = list.where(match).elementAt(i);
                    return _ServerTile(
                      server: s,
                      onSelected: widget.onSelected,
                    );
                  },
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
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
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      onTap: () async {
        await app.select(server);
        onSelected?.call();
      },
      onLongPress: () => _menu(context),
      child: Row(
        children: [
          ServerAvatar(server: server),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
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
