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
                  if (entry.platforms.isNotEmpty) ...[
                    Text(context.messages.platform),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final platform in entry.platforms)
                          Chip(label: Text(platform)),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_installation != null || _release != null) ...[
                    _status(),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (game || entry.target.isNotEmpty || _canPlay)
                        FilledButton.icon(
                          onPressed: game && !_canPlay
                              ? null
                              : () => widget.onOpen(entry),
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
                      if (_repository != null ||
                          Library.webUri(entry.downloadUrl)?.scheme == 'https')
                        OutlinedButton.icon(
                          onPressed: _downloading ? null : _downloadItem,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(context.messages.downloadAndInstall),
                        ),
                      if (Library.isWebLink(entry.repositoryUrl))
                        OutlinedButton.icon(
                          onPressed: () => _openLink(entry.repositoryUrl),
                          icon: const Icon(Icons.code),
                          label: Text(context.messages.repository),
                        ),
                    ],
                  ),
                  if (_downloading) ...[
                    const SizedBox(height: 12),
                    if (_installing) Text(context.messages.installingItem),
                    LinearProgressIndicator(
                      value: _installing ? null : _downloadProgress,
                    ),
                  ],
                  if (_downloadPath case final path?) ...[
                    const SizedBox(height: 12),
                    SelectableText(context.messages.itemInstalledPath(path)),
                  ],
                  if (_installerOpened) ...[
                    const SizedBox(height: 12),
                    Text(context.messages.itemInstallerOpened),
                  ],
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
