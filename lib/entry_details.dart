import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'dashboard.dart';
import 'entry_status.dart';
import 'item_download.dart';
import 'item_installation.dart';
import 'item_updates.dart';
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
    this.onPlayable,
  });

  final Entry entry;
  final Future<void> Function(Entry) onOpen;
  final Future<Entry?> Function(Entry)? onEdit;
  final ValueChanged<Entry>? onPlayable;

  @override
  State<EntryDetails> createState() => _EntryDetailsState();
}

class _EntryDetailsState extends State<EntryDetails> {
  late Entry _entry = widget.entry;
  late final AppLifecycleListener _lifecycle;
  Future<String?>? _installation;
  Future<Map<String, dynamic>?>? _release;
  String? _repository;
  bool _downloading = false;
  bool _installing = false;
  bool _canPlay = false;
  bool _installerOpened = false;
  double? _downloadProgress;
  String? _downloadPath;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _refreshDownload();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        setState(_checkStatus);
        _refreshDownload();
      },
    );
  }

  Future<void> _refreshDownload() async {
    final entry = _entry;
    final canPlay = await ItemInstallation.canPlay(entry);
    if (mounted && !_downloading && identical(entry, _entry)) {
      setState(() => _canPlay = canPlay);
      if (canPlay) widget.onPlayable?.call(entry);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _checkStatus() {
    final repository = _repository =
        EntryStatus.repository(_entry.repositoryUrl) ??
        EntryStatus.repository(_entry.downloadUrl);
    _installation = repository != null || EntryStatus.hasInstallationId(_entry)
        ? ItemUpdates.installedVersion(_entry).then((version) => version?.tag)
        : null;
    _release = repository == null ? null : Updater.latestRelease(repository);
  }

  Future<void> _downloadItem() async {
    if (_downloading) return;
    final repository = _repository;
    final entry = _entry;
    final onPlayable = widget.onPlayable;
    setState(() {
      _downloading = true;
      _downloadProgress = null;
      _installerOpened = false;
    });
    try {
      void progress(double? value) {
        if (mounted) setState(() => _downloadProgress = value);
      }

      void installing() {
        if (mounted) setState(() => _installing = true);
      }

      final direct = Library.webUri(_entry.downloadUrl);
      final file = repository == null
          ? await ItemInstallation.downloadAndInstall(
              entry,
              direct!,
              direct.pathSegments.lastWhere(
                (part) => part.isNotEmpty,
                orElse: () => 'download',
              ),
              progress,
              installing,
            )
          : await _downloadRelease(entry, repository, progress, installing);
      if (mounted && identical(entry, _entry)) {
        setState(() {
          _downloadPath = file?.path;
          _installerOpened = file == null;
          if (file != null) _canPlay = true;
        });
      }
      if (file != null) onPlayable?.call(entry);
    } catch (error) {
      if (mounted) {
        final messages = context.messages;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              messages.itemDownloadFailed(localizedError(messages, error)),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _installing = false;
        });
        _refreshDownload();
      }
    }
  }

  Future<File?> _downloadRelease(
    Entry entry,
    String repository,
    void Function(double?) progress,
    void Function() installing,
  ) async {
    final check = Updater.latestRelease(repository);
    setState(() => _release = check);
    final release = await check;
    final package = release == null
        ? null
        : selectItemPackage(
            release,
            repository,
            Abi.current(),
            platforms: entry.platforms,
          );
    if (package == null) {
      throw LocalizedFailure((messages) => messages.noItemPackage);
    }
    return ItemInstallation.downloadAndInstall(
      entry,
      package.url,
      package.name,
      progress,
      installing,
      size: package.size,
      digest: package.digest,
      github: true,
      version: package.version,
    );
  }

  Future<void> _edit() async {
    final edited = await widget.onEdit?.call(_entry);
    if (edited != null && mounted) {
      setState(() {
        _entry = edited;
        _downloadPath = null;
        _canPlay = false;
        _installerOpened = false;
        _checkStatus();
      });
      _refreshDownload();
    }
  }

  Widget _status() {
    final messages = context.messages;
    return FutureBuilder<String?>(
      future: _installation,
      builder: (context, installation) => FutureBuilder<Map<String, dynamic>?>(
        future: _release,
        builder: (context, release) {
          final installed = installation.connectionState == ConnectionState.done
              ? installation.data
              : null;
          final latest = release.connectionState == ConnectionState.done
              ? EntryStatus.releaseTag(release.data)
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
              if (release.connectionState == ConnectionState.done &&
                  release.hasError)
                OutlinedButton.icon(
                  onPressed: () => setState(_checkStatus),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    '${messages.releaseCheckFailed}. '
                    '${localizedError(messages, release.error!)}',
                  ),
                )
              else if (_release != null && latest == null)
                Chip(
                  label: Text(switch (release) {
                    AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                      messages.checkingRelease,
                    _ => messages.noStableRelease,
                  }),
                ),
              if (latest != null)
                Chip(
                  avatar: const Icon(Icons.new_releases_outlined),
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
    final messages = context.messages;
    return Scaffold(
      backgroundColor: const Color(0xff101116),
      appBar: AppBar(
        title: Text(messages.details),
        backgroundColor: const Color(0xff16191f),
        actions: [
          if (widget.onEdit != null)
            IconButton(
              tooltip: messages.editItem,
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 840;
          final description = _DetailPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  messages.description,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  entry.description.isEmpty
                      ? messages.noDescription
                      : entry.description,
                  style: const TextStyle(
                    color: dashboardMuted,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          );
          final hasActions =
              entry.kind == Kind.game ||
              entry.target.isNotEmpty ||
              _canPlay ||
              _installation != null ||
              _release != null ||
              Library.isWebLink(entry.onlineUrl) ||
              Library.isWebLink(entry.repositoryUrl) ||
              Library.webUri(entry.downloadUrl)?.scheme == 'https';
          final actions = hasActions
              ? _DetailPanel(child: _actions(entry))
              : null;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              wide ? 28 : 14,
              20,
              wide ? 28 : 14,
              28,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailHero(entry: entry, wide: wide),
                      const SizedBox(height: 16),
                      if (actions == null)
                        description
                      else if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: description),
                            const SizedBox(width: 16),
                            SizedBox(width: 320, child: actions),
                          ],
                        )
                      else ...[
                        actions,
                        const SizedBox(height: 16),
                        description,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _actions(Entry entry) {
    final messages = context.messages;
    final game = entry.kind == Kind.game;
    final online = Library.webUri(entry.onlineUrl);
    final canDownload =
        _repository != null ||
        Library.webUri(entry.downloadUrl)?.scheme == 'https';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canDownload && !_canPlay) ...[
          _downloadButton(primary: true),
          const SizedBox(height: 8),
        ],
        if (game || entry.target.isNotEmpty || _canPlay) ...[
          FilledButton.icon(
            onPressed: game && !_canPlay ? null : () => widget.onOpen(entry),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              backgroundColor: const Color(0xff7952d7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(game ? messages.play : messages.open),
          ),
          const SizedBox(height: 8),
        ],
        if (canDownload && _canPlay) ...[
          _downloadButton(primary: false),
          const SizedBox(height: 8),
        ],
        if (online != null) ...[
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    OnlineBrowser(title: entry.name, initialUrl: online),
              ),
            ),
            icon: const Icon(Icons.language),
            label: Text(game ? messages.playOnline : messages.openOnline),
          ),
        ],
        if (_installation != null || _release != null) ...[
          const SizedBox(height: 10),
          _status(),
        ],
        if (Library.isWebLink(entry.repositoryUrl))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openLink(entry.repositoryUrl),
              icon: const Icon(Icons.code),
              label: Text(messages.repository),
            ),
          ),
        if (_downloading) ...[
          const SizedBox(height: 12),
          if (_installing) Text(messages.installingItem),
          LinearProgressIndicator(
            value: _installing ? null : _downloadProgress,
          ),
        ],
        if (_downloadPath case final path?) ...[
          const SizedBox(height: 12),
          SelectableText(messages.itemInstalledPath(path)),
        ],
        if (_installerOpened) ...[
          const SizedBox(height: 12),
          Text(messages.itemInstallerOpened),
        ],
      ],
    );
  }

  Widget _downloadButton({required bool primary}) {
    final label = Text(context.messages.downloadAndInstall);
    const icon = Icon(Icons.download_outlined);
    final action = _downloading ? null : _downloadItem;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
    );
    if (!primary) {
      return OutlinedButton.icon(
        onPressed: action,
        icon: icon,
        label: label,
        style: OutlinedButton.styleFrom(
          shape: shape,
          minimumSize: const Size(0, 42),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: _downloading ? null : dashboardGradient,
        borderRadius: BorderRadius.circular(9),
      ),
      child: FilledButton.icon(
        onPressed: action,
        icon: icon,
        label: label,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: shape,
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xff191c23),
      border: Border.all(color: dashboardBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    padding: const EdgeInsets.all(18),
    child: child,
  );
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.entry, required this.wide});

  final Entry entry;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final game = entry.kind == Kind.game;
    final background = entry.backgroundPath;
    final backdrop = background != entry.coverPath ? background : null;
    final artwork = Container(
      width: wide ? 118 : 82,
      height: wide ? (game ? 156 : 118) : (game ? 112 : 82),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff232338),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dashboardPurple.withAlpha(105)),
      ),
      child: _DetailImage(
        path: entry.coverPath,
        width: 384,
        fit: game ? BoxFit.cover : BoxFit.contain,
        fallback: Icon(
          game ? Icons.sports_esports_outlined : Icons.apps_rounded,
          color: dashboardPurple,
          size: wide ? 54 : 38,
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff191c23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dashboardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(.9, -.9),
                  radius: 1.55,
                  colors: [Color(0xff373052), Color(0xff191c23)],
                ),
              ),
            ),
          ),
          if (backdrop != null) ...[
            Positioned.fill(
              child: _DetailImage(
                path: backdrop,
                width: 1440,
                fallback: const SizedBox.shrink(),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0x2410141c),
                      Color(0xe012151e),
                      Color(0xff191c23),
                    ],
                    stops: [0, .65, 1],
                  ),
                ),
              ),
            ),
          ],
          Container(
            constraints: BoxConstraints(minHeight: wide ? 250 : 175),
            padding: EdgeInsets.all(wide ? 28 : 16),
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                artwork,
                SizedBox(width: wide ? 24 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: wide ? 38 : 24,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      if (entry.developer.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          entry.developer,
                          style: const TextStyle(
                            color: dashboardMuted,
                            fontSize: 15,
                          ),
                        ),
                      ],
                      if (entry.platforms.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final platform in entry.platforms)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xff252334),
                                  border: Border.all(color: dashboardBorder),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  child: Text(
                                    platform,
                                    style: const TextStyle(
                                      color: dashboardMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
    this.fit = BoxFit.cover,
  });

  final String? path;
  final int width;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => switch (path) {
    final path? => Image.network(
      path,
      fit: fit,
      cacheWidth: width,
      errorBuilder: (_, _, _) => fallback,
    ),
    null => fallback,
  };
}
