import 'package:material_ui/material_ui.dart';

import 'dashboard.dart';
import 'entry_status.dart';
import 'library.dart';
import 'localization.dart';
import 'online_browser.dart';
import 'updates.dart';

class EntryDetails extends StatefulWidget {
  const EntryDetails({
    super.key,
    required this.entry,
    required this.onOpen,
    this.onEdit,
  });

  final Entry entry;
  final Future<void> Function(Entry) onOpen;
  final Future<Entry?> Function(Entry)? onEdit;

  @override
  State<EntryDetails> createState() => _EntryDetailsState();
}

class _EntryDetailsState extends State<EntryDetails> {
  late Entry _entry = widget.entry;
  late final AppLifecycleListener _lifecycle;
  Future<String?>? _installation;
  Future<String?>? _release;
  String? _repository;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _lifecycle = AppLifecycleListener(onResume: () => setState(_checkStatus));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _checkStatus() {
    _installation = EntryStatus.hasInstallationId(_entry)
        ? EntryStatus.installedVersion(_entry)
        : null;
    final repository = _repository = EntryStatus.repository(
      _entry.repositoryUrl,
    );
    _release = repository == null
        ? null
        : EntryStatus.latestVersion(repository);
  }

  Future<void> _edit() async {
    final edited = await widget.onEdit?.call(_entry);
    if (edited != null && mounted) {
      setState(() {
        _entry = edited;
        _checkStatus();
      });
    }
  }

  Widget _status() {
    final messages = context.messages;
    return FutureBuilder<String?>(
      future: _installation,
      builder: (context, installation) => FutureBuilder<String?>(
        future: _release,
        builder: (context, release) {
          final installed = installation.connectionState == ConnectionState.done
              ? installation.data
              : null;
          final latest = release.connectionState == ConnectionState.done
              ? release.data
              : null;
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_installation != null)
                Chip(
                  label: Text(switch (installation) {
                    AsyncSnapshot(hasError: true) =>
                      messages.installationCheckFailed,
                    AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                      messages.checkingInstallation,
                    _ when installed == null => messages.itemNotInstalled,
                    _ when installed.isEmpty => messages.itemInstalled,
                    _ => messages.installedItemVersion(installed),
                  }),
                ),
              if (_release != null && latest == null)
                Chip(
                  label: Text(switch (release) {
                    AsyncSnapshot(hasError: true) =>
                      messages.releaseCheckFailed,
                    AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                      messages.checkingRelease,
                    _ => messages.noStableRelease,
                  }),
                ),
              if (latest != null)
                OutlinedButton.icon(
                  onPressed: () => _openLink(
                    Uri(
                      scheme: 'https',
                      host: 'github.com',
                      pathSegments: [
                        ..._repository!.split('/'),
                        'releases',
                        'tag',
                        latest,
                      ],
                    ).toString(),
                  ),
                  icon: const Icon(Icons.new_releases_outlined),
                  label: Text(
                    installed != null && isNewer(latest, installed)
                        ? messages.itemUpdateAvailable(latest)
                        : messages.latestItemRelease(latest),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openLink(String address) async {
    try {
      await Library.openWebLink(address);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.messages.linkError(
                localizedError(context.messages, error),
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final game = entry.kind == Kind.game;
    final online = Library.webUri(entry.onlineUrl);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.name),
        actions: [
          if (widget.onEdit != null)
            IconButton(
              tooltip: context.messages.editItem,
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _DetailImage(
                            path: entry.backgroundPath ?? entry.coverPath,
                            width: 1440,
                            fallback: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xff225064),
                                    Color(0xff3f2852),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x2411141c), Color(0xf3161820)],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 62, 16, 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 104,
                                  height: 132,
                                  child: _DetailImage(
                                    path: entry.coverPath,
                                    width: 360,
                                    fallback: ColoredBox(
                                      color: const Color(0xff292d3b),
                                      child: Icon(
                                        game
                                            ? Icons.sports_esports_outlined
                                            : Icons.apps,
                                        color: dashboardCyan,
                                        size: 42,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    if (entry.developer.isNotEmpty)
                                      Text(
                                        entry.developer,
                                        style: const TextStyle(
                                          color: dashboardMuted,
                                          fontSize: 16,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_installation != null || _release != null) ...[
                    _status(),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (entry.target.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => widget.onOpen(entry),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            game
                                ? context.messages.play
                                : context.messages.open,
                          ),
                        ),
                      if (online != null)
                        FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => OnlineBrowser(
                                title: entry.name,
                                initialUrl: online,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.language),
                          label: Text(
                            game
                                ? context.messages.playOnline
                                : context.messages.openOnline,
                          ),
                        ),
                      if (Library.isWebLink(entry.downloadUrl))
                        OutlinedButton.icon(
                          onPressed: () => _openLink(entry.downloadUrl),
                          icon: const Icon(Icons.download_outlined),
                          label: Text(context.messages.download),
                        ),
                      if (Library.isWebLink(entry.repositoryUrl))
                        OutlinedButton.icon(
                          onPressed: () => _openLink(entry.repositoryUrl),
                          icon: const Icon(Icons.code),
                          label: Text(context.messages.repository),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.messages.description,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    entry.description.isEmpty
                        ? context.messages.noDescription
                        : entry.description,
                    style: const TextStyle(color: dashboardMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailImage extends StatelessWidget {
  const _DetailImage({
    required this.path,
    required this.width,
    required this.fallback,
  });

  final String? path;
  final int width;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => switch (path) {
    final path? => Image.network(
      path,
      fit: BoxFit.cover,
      cacheWidth: width,
      errorBuilder: (_, _, _) => fallback,
    ),
    null => fallback,
  };
}
