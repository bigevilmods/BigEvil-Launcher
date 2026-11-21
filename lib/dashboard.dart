import 'package:material_ui/material_ui.dart';

import 'entry.dart';
import 'localization.dart';

const dashboardCyan = Color(0xff65d6fb);
const dashboardPurple = Color(0xffb47bff);
const dashboardMuted = Color(0xffb4b8c2);
const dashboardBorder = Color(0xff383d49);
const dashboardGradient = LinearGradient(
  colors: [Color(0xff6558ea), Color(0xffa645dd)],
);

class DashboardNavigation extends StatelessWidget {
  const DashboardNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onSettings,
    required this.desktop,
    this.onSearch,
  });

  final Kind? selected;
  final ValueChanged<Kind?> onSelect;
  final VoidCallback? onSettings;
  final bool desktop;
  final VoidCallback? onSearch;

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
      width: 98,
      decoration: const BoxDecoration(
        color: Color(0xff16191f),
        border: Border(right: BorderSide(color: Color(0xff242832))),
      ),
      padding: const EdgeInsets.fromLTRB(7, 76, 7, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff171c26), Color(0xff11171d)],
          ),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xff3c606b)),
          boxShadow: const [
            BoxShadow(color: Color(0x303caac6), blurRadius: 12),
          ],
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: [
            if (onSearch != null)
              _NavigationTile(
                label: MaterialLocalizations.of(context).searchFieldLabel,
                icon: Icons.search,
                onTap: onSearch,
              ),
            for (final (kind, icon, label) in destinations)
              _NavigationTile(
                label: kind == Kind.game ? context.messages.games : label,
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
  Widget build(BuildContext context) => Material(
    color: active ? const Color(0xff282138) : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          if (active)
            Positioned(
              top: 8,
              bottom: 8,
              left: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: dashboardPurple,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: dashboardPurple, blurRadius: 10),
                  ],
                ),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 23,
                    color: active ? dashboardPurple : dashboardMuted,
                    shadows: active
                        ? const [Shadow(color: dashboardPurple, blurRadius: 12)]
                        : null,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: active ? dashboardPurple : dashboardMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class DashboardGallery extends StatelessWidget {
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
    this.minHeight = 0,
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
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final games = kind == Kind.game;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: const Color(0xff191c23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dashboardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 460
                ? 3
                : bounds.maxWidth >= 255
                ? 2
                : 1;
            const gap = 14.0;
            final width = (bounds.maxWidth - (columns - 1) * gap) / columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (games
                                ? context.messages.gameLibrary
                                : context.messages.creationProductivity)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff272b35),
                        border: Border.all(color: dashboardBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text('${entries.length}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                if (entries.isEmpty)
                  _GalleryEmpty(
                    games: games,
                    hasSearch: hasSearch,
                    onAdd: onAdd,
                  )
                else
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final entry in entries)
                        SizedBox(
                          width: width,
                          height: 248,
                          child: DashboardCard(
                            entry: entry,
                            onOpen: () => onOpen(entry),
                            canPlay: canPlay?.call(entry) ?? false,
                            onDetails: onDetails == null
                                ? null
                                : () => onDetails!(entry),
                            onEdit: onEdit == null
                                ? null
                                : () => onEdit!(entry),
                            onRemove: onRemove == null
                                ? null
                                : () => onRemove!(entry),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
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
        color: const Color(0xff151820),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: games ? dashboardBorder : accent.withAlpha(75),
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
                    else if (games)
                      Image.network(
                        cover,
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                        errorBuilder: (_, _, _) => fallback,
                      )
                    else ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [deep, const Color(0xff151820)],
                          ),
                        ),
                      ),
                      Center(
                        child: SizedBox.square(
                          dimension: 84,
                          child: Image.network(
                            cover,
                            fit: BoxFit.contain,
                            cacheWidth: 180,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.apps_rounded,
                              color: accent,
                              size: 66,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xff151820)],
                          stops: [.64, 1],
                        ),
                      ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      entry.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
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
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: dashboardMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff222630),
                        gradient: games && canPlay ? dashboardGradient : null,
                        border: Border.all(color: dashboardBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton(
                        onPressed: !hasTarget && !canPlay
                            ? onDetails
                            : (!games || canPlay ? onOpen : null),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 35),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: Text(
                          !hasTarget && !canPlay
                              ? context.messages.details
                              : games
                              ? context.messages.play
                              : context.messages.open,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
