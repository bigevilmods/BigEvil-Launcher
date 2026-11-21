import 'dart:ui' show PointerDeviceKind;

import 'package:material_ui/material_ui.dart';

import 'entry.dart';
import 'localization.dart';

const dashboardCyan = Color(0xff65d6fb);
const dashboardPurple = Color(0xffc38af8);
const dashboardMuted = Color(0xffb4b8c2);
const dashboardBorder = Color(0xff3d414d);
const dashboardGradient = LinearGradient(
  colors: [dashboardCyan, Color(0xff82a2f4), dashboardPurple],
);

class DashboardNavigation extends StatelessWidget {
  const DashboardNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onSettings,
    required this.desktop,
  });

  final Kind? selected;
  final ValueChanged<Kind?> onSelect;
  final VoidCallback? onSettings;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (null, Icons.home_outlined, context.messages.home),
      (Kind.game, Icons.sports_esports_outlined, context.messages.gameLibrary),
      (Kind.app, Icons.apps_outlined, context.messages.applications),
    ];
    if (!desktop) {
      return NavigationBar(
        backgroundColor: const Color(0xff22252b),
        selectedIndex: destinations.indexWhere((item) => item.$1 == selected),
        onDestinationSelected: (index) => onSelect(destinations[index].$1),
        destinations: [
          for (final (kind, icon, label) in destinations)
            NavigationDestination(
              icon: Icon(icon),
              label: kind == Kind.game ? context.messages.games : label,
            ),
        ],
      );
    }
    return Container(
      width: 199,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff26292e), Color(0xff202126)],
        ),
        border: Border(right: BorderSide(color: dashboardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 38, 14, 36),
            child: DashboardBrand(),
          ),
          for (final (kind, icon, label) in destinations)
            _NavigationTile(
              label: label,
              icon: icon,
              active: selected == kind,
              onTap: () => onSelect(kind),
            ),
          _NavigationTile(
            label: context.messages.settings,
            icon: Icons.settings_outlined,
            onTap: onSettings,
          ),
        ],
      ),
    );
  }
}

class DashboardBrand extends StatelessWidget {
  const DashboardBrand({super.key});

  @override
  Widget build(BuildContext context) => const Text.rich(
    TextSpan(
      style: TextStyle(fontSize: 21, letterSpacing: -.7),
      children: [
        TextSpan(
          text: 'BIGEVIL',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        TextSpan(
          text: ' LAUNCHER',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: .1,
            color: dashboardPurple,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
    semanticsLabel: 'BigEvil Launcher',
  );
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(13, 0, 10, 7),
    child: Material(
      color: active ? const Color(0xff383e46) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                color: active ? dashboardCyan : dashboardMuted,
                shadows: active
                    ? const [Shadow(color: dashboardCyan, blurRadius: 14)]
                    : null,
                size: 23,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: active ? Colors.white : dashboardMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DashboardGallery extends StatefulWidget {
  const DashboardGallery({
    super.key,
    required this.kind,
    required this.entries,
    required this.hasSearch,
    required this.onOpen,
    this.canPlay,
    this.onDetails,
    this.onAdd,
    this.onEdit,
    this.onRemove,
  });

  final Kind kind;
  final List<Entry> entries;
  final bool hasSearch;
  final ValueChanged<Entry> onOpen;
  final bool Function(Entry)? canPlay;
  final ValueChanged<Entry>? onDetails;
  final VoidCallback? onAdd;
  final ValueChanged<Entry>? onEdit;
  final ValueChanged<Entry>? onRemove;

  @override
  State<DashboardGallery> createState() => _DashboardGalleryState();
}

class _DashboardGalleryState extends State<DashboardGallery> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(double offset) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + offset).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.kind == Kind.game;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: dashboardGradient,
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(color: Color(0x2854cbff), blurRadius: 19),
          BoxShadow(
            color: Color(0x206f2eac),
            blurRadius: 25,
            offset: Offset(6, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15.5),
            gradient: const LinearGradient(
              colors: [Color(0xff23343b), Color(0xff302e41), Color(0xff302739)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final width = (bounds.maxWidth * (games ? .31 : .232))
                    .clamp(games ? 234.0 : 196.0, games ? 352.0 : 270.0)
                    .clamp(0.0, bounds.maxWidth);
                final scrolls =
                    widget.entries.length * (width + 14) - 14 > bounds.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            games
                                ? context.messages.gameLibrary.toUpperCase()
                                : context.messages.creationProductivity
                                      .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                            ),
                          ),
                        ),
                        if (scrolls) ...[
                          IconButton(
                            tooltip: context.messages.galleryBack,
                            onPressed: () => _move(-width - 14),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          IconButton(
                            tooltip: context.messages.galleryForward,
                            onPressed: () => _move(width + 14),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 9),
                    if (widget.entries.isEmpty)
                      _GalleryEmpty(
                        games: games,
                        hasSearch: widget.hasSearch,
                        onAdd: widget.onAdd,
                      )
                    else
                      SizedBox(
                        height: games ? 225 : 226,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            scrollbars: false,
                            dragDevices: const {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                              PointerDeviceKind.stylus,
                            },
                          ),
                          child: ListView.separated(
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final entry = widget.entries[index];
                              return SizedBox(
                                width: width,
                                child: DashboardCard(
                                  entry: entry,
                                  onOpen: () => widget.onOpen(entry),
                                  canPlay: widget.canPlay?.call(entry) ?? false,
                                  onDetails: widget.onDetails == null
                                      ? null
                                      : () => widget.onDetails!(entry),
                                  onEdit: widget.onEdit == null
                                      ? null
                                      : () => widget.onEdit!(entry),
                                  onRemove: widget.onRemove == null
                                      ? null
                                      : () => widget.onRemove!(entry),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryEmpty extends StatelessWidget {
  const _GalleryEmpty({
    required this.games,
    required this.hasSearch,
    this.onAdd,
  });

  final bool games;
  final bool hasSearch;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 210),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0x66141720),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xff424653)),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            games ? Icons.sports_esports_outlined : Icons.apps_outlined,
            color: games ? dashboardCyan : dashboardPurple,
            size: 38,
          ),
          const SizedBox(height: 9),
          Text(
            hasSearch
                ? context.messages.noResults
                : games
                ? context.messages.noGames
                : context.messages.noApps,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (!hasSearch && onAdd != null)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                games ? context.messages.addGame : context.messages.addApp,
              ),
            ),
        ],
      ),
    ),
  );
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.entry,
    required this.onOpen,
    this.canPlay = false,
    this.onDetails,
    this.onEdit,
    this.onRemove,
  });

  final Entry entry;
  final VoidCallback onOpen;
  final bool canPlay;
  final VoidCallback? onDetails;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final games = entry.kind == Kind.game;
    final colors = [
      (const Color(0xff113f51), const Color(0xff70dfff)),
      (const Color(0xff48244d), const Color(0xffd58aee)),
      (const Color(0xff4a3226), const Color(0xffffbe75)),
      (const Color(0xff153e40), const Color(0xff7be7c7)),
    ];
    final slot = entry.name.codeUnits.fold<int>(0, (sum, value) => sum + value);
    final (deep, accent) = colors[slot % colors.length];
    final cover = entry.coverPath;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.48, -.46),
          radius: 1.7,
          colors: [deep, const Color(0xff11121a)],
        ),
      ),
      child: Center(
        child: Icon(
          games ? Icons.sports_esports_outlined : Icons.apps_rounded,
          size: 70,
          color: accent,
          shadows: [Shadow(color: accent.withAlpha(100), blurRadius: 24)],
        ),
      ),
    );
    final hasTarget = entry.target.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff202329),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: games ? dashboardBorder : accent.withAlpha(155),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover == null)
                      fallback
                    else
                      Image.network(
                        cover,
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                        errorBuilder: (_, _, _) => fallback,
                      ),
                    if (onDetails != null)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onDetails,
                            child: Semantics(
                              label: context.messages.itemDetails(entry.name),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    if (onEdit != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: const Color(0xc61b1e27),
                          shape: const CircleBorder(),
                          child: PopupMenuButton<String>(
                            tooltip: context.messages.itemOptions(entry.name),
                            icon: const Icon(Icons.more_horiz, size: 19),
                            onSelected: (action) {
                              if (action == 'edit') onEdit?.call();
                              if (action == 'remove') onRemove?.call();
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(context.messages.edit),
                              ),
                              if (onRemove != null)
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    context.messages.removeFromLibrary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(11, 8, 10, 8),
                color: const Color(0xff21242a),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.name.toUpperCase(),
                            maxLines: games ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (entry.platforms.isNotEmpty)
                            Tooltip(
                              message: entry.platforms.join(' · '),
                              child: Text(
                                entry.platforms.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: dashboardMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          if (!games && hasTarget)
                            Tooltip(
                              message: entry.target,
                              child: Text(
                                entry.target,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: dashboardMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    if (!hasTarget && !canPlay)
                      TextButton(
                        onPressed: onDetails,
                        child: Text(context.messages.details),
                      )
                    else if (games)
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          decoration: const BoxDecoration(
                            gradient: dashboardGradient,
                          ),
                          child: TextButton(
                            onPressed: canPlay ? onOpen : null,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xff101824),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            child: Text(context.messages.play),
                          ),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: onOpen,
                        style: TextButton.styleFrom(foregroundColor: accent),
                        child: Text('${context.messages.open} ›'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
