import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'dashboard.dart';
import 'entry_details.dart';
import 'library.dart';
import 'localization.dart';
import 'updates.dart';

const ink = Color(0xff1b1c22);
const panel = Color(0xff2a2c34);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var language = InterfaceLanguage.system;
  try {
    language = await (await LanguagePreference.forApp()).load();
  } catch (error) {
    debugPrint('Could not load saved language: $error');
  }
  runApp(BigEvil(initialLanguage: language));
}

class BigEvil extends StatefulWidget {
  const BigEvil({super.key, this.initialLanguage = InterfaceLanguage.system});

  final InterfaceLanguage initialLanguage;

  @override
  State<BigEvil> createState() => _BigEvilState();
}

class _BigEvilState extends State<BigEvil> {
  late InterfaceLanguage _language = widget.initialLanguage;

  Future<void> _setLanguage(InterfaceLanguage language) async {
    await (await LanguagePreference.forApp()).save(language);
    if (mounted) setState(() => _language = language);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BigEvil Launcher',
    locale: _language.locale,
    supportedLocales: InterfaceLanguage.supportedLocales,
    localizationsDelegates: const [
      Messages.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: dashboardCyan,
        brightness: Brightness.dark,
        surface: panel,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: dashboardBorder),
        ),
      ),
    ),
    home: Launcher(language: _language, onLanguageChanged: _setLanguage),
  );
}

class Launcher extends StatefulWidget {
  const Launcher({
    super.key,
    required this.language,
    required this.onLanguageChanged,
  });

  final InterfaceLanguage language;
  final Future<void> Function(InterfaceLanguage) onLanguageChanged;

  @override
  State<Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<Launcher> {
  List<Entry> _entries = [];
  final Set<Entry> _downloadedGames = {};
  String _query = '';
  String _repository = '';
  Kind? _filter;
  String? _platformFilter;
  bool _loading = true;
  bool _loadFailed = false;
  bool _checking = false;
  bool _updateDialogOpen = false;
  String? _updateVersion;
  Object? _updateFailure;
  bool _changingLanguage = false;
  File? _package;
  double? _progress;
  Timer? _timer;

  Future<void> _chooseLanguage() async {
    if (_changingLanguage) return;
    setState(() => _changingLanguage = true);
    try {
      final language = await showDialog<InterfaceLanguage>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(context.messages.language),
          children: [
            for (final language in InterfaceLanguage.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, language),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(language.label(context.messages)),
                  trailing: language == widget.language
                      ? const Icon(Icons.check)
                      : null,
                ),
              ),
          ],
        ),
      );
      if (language != null && language != widget.language && mounted) {
        await widget.onLanguageChanged(language);
      }
    } catch (error) {
      debugPrint('Could not save language: $error');
      _notify((messages) => messages.languageSaveError);
    } finally {
      if (mounted) setState(() => _changingLanguage = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_configureUpdates());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await Library.load();
      final downloaded = await Future.wait(
        entries
            .where((entry) => entry.kind == Kind.game)
            .map(
              (entry) async =>
                  await Updater.savedItemPath(entry) == null ? null : entry,
            ),
      );
      if (mounted)
        setState(() {
          _entries = entries;
          _downloadedGames
            ..clear()
            ..addAll(downloaded.whereType<Entry>());
          _loadFailed = false;
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _loadFailed = true;
          _loading = false;
        });
      _notify(
        (messages) =>
            messages.libraryReadError(localizedError(messages, error)),
      );
    }
  }

  Future<void> _configureUpdates() async {
    try {
      final repository = await Updater.repository();
      if (!mounted) return;
      _repository = repository;
      await _check();
    } catch (error) {
      _notify(
        (messages) =>
            messages.settingsReadError(localizedError(messages, error)),
      );
    }
  }

  void _notify(String Function(Messages) message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message(context.messages))));
  }

  Future<void> _check({bool manual = false}) async {
    if (!mounted || _checking || _updateDialogOpen || _repository.isEmpty) {
      return;
    }
    setState(() {
      _checking = true;
      _updateVersion = null;
      _updateFailure = null;
      _package = null;
    });
    try {
      final release = await Updater.check(_repository);
      if (!mounted) return;
      if (release == null) {
        if (manual) _notify((messages) => messages.currentRelease);
        return;
      }
      setState(() => _progress = 0);
      final file = await Updater.download(release, (value) {
        if (mounted) setState(() => _progress = value);
      });
      if (mounted)
        setState(() {
          _package = file;
          _updateVersion = release.version;
        });
    } catch (error) {
      if (mounted) setState(() => _updateFailure = error);
    } finally {
      if (mounted)
        setState(() {
          _progress = null;
          _checking = false;
        });
    }
  }

  Future<void> _settings() async {
    if (_checking || _updateDialogOpen) return;
    _updateDialogOpen = true;
    final verify = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.messages.updates),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.messages.versionLabel(currentVersion)),
            const SizedBox(height: 12),
            Text(context.messages.updateHelp),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.messages.checkForUpdates),
          ),
        ],
      ),
    );
    _updateDialogOpen = false;
    if (mounted && verify == true) await _check(manual: true);
  }

  void _showDetails(Entry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryDetails(
          entry: entry,
          onOpen: _open,
          onDownloaded: (item) {
            if (mounted && item.kind == Kind.game) {
              setState(() => _downloadedGames.add(item));
            }
          },
        ),
      ),
    );
  }

  Future<void> _open(Entry entry) async {
    try {
      if (entry.kind == Kind.game &&
          await Updater.savedItemPath(entry) == null) {
        if (mounted) setState(() => _downloadedGames.remove(entry));
        return;
      }
      await Library.open(entry);
    } catch (error) {
      _notify(
        (messages) =>
            messages.itemOpenError(entry.name, localizedError(messages, error)),
      );
    }
  }

  Future<void> _install() async {
    final file = _package;
    if (file == null) return;
    try {
      await Updater.install(file);
    } catch (error) {
      _notify(
        (messages) => messages.installerError(localizedError(messages, error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final platforms =
        {
            for (final entry in _entries)
              for (final platform in entry.platforms)
                platform.toLowerCase(): platform,
          }.values.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final matches = filterEntries(
      _entries,
      _query,
      _filter,
      platform: _platformFilter,
    ).toList(growable: false);
    final settings = _checking ? null : _settings;
    final updateMessage = switch ((_updateFailure, _updateVersion)) {
      (final error?, _) => context.messages.updateError(
        localizedError(context.messages, error),
      ),
      (_, final version?) => context.messages.updateReady(version),
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final desktop = bounds.maxWidth >= 760;
            final toolbarProgress = bounds.maxWidth >= 1080 ? _progress : null;
            final navigation = DashboardNavigation(
              desktop: desktop,
              selected: _filter,
              onSelect: (kind) => setState(() => _filter = kind),
              onSettings: settings,
            );
            final dashboard = Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xff20282e),
                      Color(0xff1b1c22),
                      Color(0xff24212c),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: desktop
                          ? const EdgeInsets.fromLTRB(24, 25, 24, 21)
                          : const EdgeInsets.fromLTRB(14, 12, 14, 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!desktop) ...[
                            const DashboardBrand(),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Flexible(
                                fit: FlexFit.tight,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 520,
                                    ),
                                    child: TextField(
                                      onChanged: (value) =>
                                          setState(() => _query = value),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          size: 21,
                                        ),
                                        hintText: desktop
                                            ? context.messages.searchItems
                                            : context.messages.searchLibrary,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (toolbarProgress case final progress?) ...[
                                SizedBox(
                                  width: 188,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        context.messages.updateProgress(
                                          (progress * 100).round(),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      LinearProgressIndicator(value: progress),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              IconButton.outlined(
                                tooltip: context.messages.language,
                                onPressed: _changingLanguage
                                    ? null
                                    : _chooseLanguage,
                                icon: const Icon(Icons.translate, size: 20),
                              ),
                              const SizedBox(width: 7),
                              IconButton.outlined(
                                tooltip: context.messages.updateSettings,
                                onPressed: settings,
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  size: 21,
                                ),
                              ),
                            ],
                          ),
                          if (platforms.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            PopupMenuButton<String>(
                              initialValue: _platformFilter ?? '',
                              tooltip: context.messages.platform,
                              onSelected: (value) => setState(
                                () => _platformFilter = value.isEmpty
                                    ? null
                                    : value,
                              ),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: '',
                                  child: Text(context.messages.allPlatforms),
                                ),
                                for (final platform in platforms)
                                  PopupMenuItem(
                                    value: platform,
                                    child: Text(platform),
                                  ),
                              ],
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.devices, size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _platformFilter ??
                                          context.messages.allPlatforms,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 24 : 14,
                          0,
                          desktop ? 24 : 14,
                          22,
                        ),
                        children: [
                          if (_progress case final progress?
                              when toolbarProgress == null) ...[
                            Text(
                              context.messages.updateProgress(
                                (progress * 100).round(),
                              ),
                            ),
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 15),
                          ],
                          if (updateMessage case final message?) ...[
                            ListTile(
                              tileColor: panel,
                              leading: const Icon(Icons.system_update_alt),
                              title: Text(message),
                              trailing: _package == null
                                  ? null
                                  : TextButton(
                                      onPressed: _install,
                                      child: Text(context.messages.install),
                                    ),
                            ),
                            const SizedBox(height: 15),
                          ],
                          if (_loading)
                            const Center(child: CircularProgressIndicator())
                          else if (_loadFailed)
                            ListTile(
                              title: Text(context.messages.libraryUnavailable),
                              trailing: TextButton(
                                onPressed: _load,
                                child: Text(context.messages.retry),
                              ),
                            )
                          else
                            for (final kind in Kind.values)
                              if (_filter == null || _filter == kind)
                                Padding(
                                  key: ValueKey(kind),
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: DashboardGallery(
                                    kind: kind,
                                    entries: matches
                                        .where((entry) => entry.kind == kind)
                                        .toList(growable: false),
                                    hasSearch:
                                        _query.trim().isNotEmpty ||
                                        _platformFilter != null,
                                    onOpen: _open,
                                    canPlay: _downloadedGames.contains,
                                    onDetails: _showDetails,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
            if (desktop) return Row(children: [navigation, dashboard]);
            return Column(children: [dashboard, navigation]);
          },
        ),
      ),
    );
  }
}
