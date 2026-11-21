import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
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
  String _query = '';
  String _repository = '';
  Kind? _filter;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _checking = false;
  bool _editingRepository = false;
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
    try {
      final entries = await Library.load();
      if (mounted)
        setState(() {
          _entries = entries;
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
    if (!mounted || _checking || _editingRepository || _repository.isEmpty) {
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
    if (_checking || _editingRepository) return;
    setState(() => _editingRepository = true);
    var value = _repository;
    final repository = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          title: Text(context.messages.updates),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.messages.versionLabel(currentVersion)),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: value,
                onChanged: (text) => value = text.trim(),
                decoration: InputDecoration(
                  labelText: context.messages.publicRepo,
                  hintText: context.messages.repoPlaceholder,
                ),
              ),
              const SizedBox(height: 12),
              Text(context.messages.updateHelp),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.messages.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: Text(context.messages.saveAndCheck),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    setState(() => _editingRepository = false);
    if (repository == null) return;
    if (repository.isNotEmpty && !repositoryPattern.hasMatch(repository)) {
      _notify((messages) => messages.repoFormat);
      return;
    }
    try {
      await Updater.saveRepository(repository);
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _package = null;
        _updateVersion = null;
        _updateFailure = null;
      });
      await _check(manual: true);
    } catch (error) {
      _notify(
        (messages) =>
            messages.settingsSaveError(localizedError(messages, error)),
      );
    }
  }

  Future<void> _save(List<Entry> entries) async {
    if (_saving || _loadFailed || _loading) return;
    setState(() => _saving = true);
    try {
      await Library.save(entries);
      if (mounted) setState(() => _entries = entries);
    } catch (error) {
      _notify(
        (messages) =>
            messages.librarySaveError(localizedError(messages, error)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Entry?> _edit([Entry? previous, Kind? initialKind]) async {
    final entry = await showDialog<Entry>(
      context: context,
      builder: (_) => EntryEditor(previous: previous, initialKind: initialKind),
    );
    if (entry == null || !mounted) return null;
    final index = _entries.indexOf(previous ?? entry);
    final entries = [..._entries];
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _save(entries);
    return _entries.contains(entry) ? entry : null;
  }

  void _showDetails(Entry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryDetails(
          entry: entry,
          onOpen: _open,
          onEdit: (entry) => _edit(entry),
        ),
      ),
    );
  }

  Future<void> _open(Entry entry) async {
    try {
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
    final matches = filterEntries(
      _entries,
      _query,
      _filter,
    ).toList(growable: false);
    final editable = !_loading && !_loadFailed && !_saving;
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
            final add = editable ? () => _edit(null, _filter) : null;
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
                              if (desktop && bounds.maxWidth >= 920)
                                OutlinedButton.icon(
                                  onPressed: add,
                                  icon: const Icon(Icons.add, size: 19),
                                  label: Text(context.messages.addItem),
                                )
                              else
                                IconButton.outlined(
                                  tooltip: context.messages.addItem,
                                  onPressed: add,
                                  icon: const Icon(Icons.add),
                                ),
                              const SizedBox(width: 7),
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
                                    hasSearch: _query.trim().isNotEmpty,
                                    onOpen: _open,
                                    onDetails: _showDetails,
                                    onAdd: editable
                                        ? () => _edit(null, kind)
                                        : null,
                                    onEdit: editable
                                        ? (entry) => _edit(entry)
                                        : null,
                                    onRemove: editable
                                        ? (entry) => _save(
                                            _entries
                                                .where((item) => item != entry)
                                                .toList(),
                                          )
                                        : null,
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

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, this.previous, this.initialKind});
  final Entry? previous;
  final Kind? initialKind;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.previous?.name);
  late final _target = TextEditingController(text: widget.previous?.target);
  late final _description = TextEditingController(
    text: widget.previous?.description,
  );
  late final _developer = TextEditingController(
    text: widget.previous?.developer,
  );
  late final _repositoryUrl = TextEditingController(
    text: widget.previous?.repositoryUrl,
  );
  late final _downloadUrl = TextEditingController(
    text: widget.previous?.downloadUrl,
  );
  late final _onlineUrl = TextEditingController(
    text: widget.previous?.onlineUrl,
  );
  late Kind _kind = widget.previous?.kind ?? widget.initialKind ?? Kind.game;
  late final _cover = _ItemImage(widget.previous?.coverPath);
  late final _background = _ItemImage(widget.previous?.backgroundPath);
  bool _importingCover = false;
  String? _pickerError;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _description.dispose();
    _developer.dispose();
    _repositoryUrl.dispose();
    _downloadUrl.dispose();
    _onlineUrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      if (Platform.isAndroid) {
        final entries = await Library.installedAndroidApps();
        if (!mounted) return;
        final selected = await showDialog<Entry>(
          context: context,
          builder: (_) => _AppPicker(entries),
        );
        if (selected != null && mounted) {
          _name.text = selected.name;
          _target.text = selected.target;
        }
      } else {
        final file = await openFile();
        if (file != null && mounted) {
          if (_name.text.trim().isEmpty)
            _name.text = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
          _target.text = file.path;
        }
      }
    } catch (error) {
      if (mounted)
        setState(
          () => _pickerError = context.messages.pickerError(
            localizedError(context.messages, error),
          ),
        );
    }
  }

  Future<void> _pickImage(_ItemImage image) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: context.messages.images,
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          ),
        ],
      );
      if (file != null && mounted)
        setState(() {
          image.selected = file;
          _pickerError = null;
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _pickerError = context.messages.imagePickError(
            localizedError(context.messages, error),
          ),
        );
    }
  }

  Future<void> _submit() async {
    if (_importingCover || !_form.currentState!.validate()) return;
    setState(() => _importingCover = true);
    try {
      for (final image in [_cover, _background]) {
        if (image.selected case final selected?) {
          image.path = await Library.importCover(selected);
          image.selected = null;
        }
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _importingCover = false;
          _pickerError = context.messages.imageImportError(
            localizedError(context.messages, error),
          );
        });
      return;
    }
    if (mounted) {
      Navigator.pop(
        context,
        Entry(
          _name.text.trim(),
          _target.text.trim(),
          _kind,
          coverPath: _cover.path,
          backgroundPath: _background.path,
          description: _description.text.trim(),
          developer: _developer.text.trim(),
          repositoryUrl: _repositoryUrl.text.trim(),
          downloadUrl: _downloadUrl.text.trim(),
          onlineUrl: _onlineUrl.text.trim(),
        ),
      );
    }
  }

  String? _validateTarget(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty || Library.isWebLink(value)) return null;
    if (Platform.isAndroid &&
        RegExp(r'^[A-Za-z_][\w]*(\.[A-Za-z_][\w]*)+$').hasMatch(value))
      return null;
    if (!Platform.isAndroid && value.isNotEmpty && File(value).isAbsolute)
      return null;
    return Platform.isAndroid
        ? context.messages.androidTargetHelp
        : context.messages.desktopTargetHelp;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.previous == null
          ? context.messages.addItem
          : context.messages.editItem,
    ),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            maxLength: 100,
            decoration: InputDecoration(labelText: context.messages.name),
            validator: (value) => value == null || value.trim().isEmpty
                ? context.messages.nameRequired
                : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _target,
            decoration: InputDecoration(
              labelText: Platform.isAndroid
                  ? context.messages.androidTarget
                  : context.messages.desktopTarget,
            ),
            validator: _validateTarget,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open),
            label: Text(
              Platform.isAndroid
                  ? context.messages.pickInstalledApp
                  : context.messages.pickFile,
            ),
          ),
          for (final image in [_cover, _background])
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _importingCover ? null : () => _pickImage(image),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    image == _cover
                        ? context.messages.pickCover
                        : context.messages.pickBackground,
                  ),
                ),
                if (image.selected != null || image.path != null)
                  IconButton(
                    tooltip: image == _cover
                        ? context.messages.removeCover
                        : context.messages.removeBackground,
                    onPressed: _importingCover
                        ? null
                        : () => setState(() {
                            image.selected = null;
                            image.path = null;
                            _pickerError = null;
                          }),
                    icon: const Icon(Icons.hide_image_outlined),
                  ),
                if (image.selected case final file?)
                  Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _developer,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: context.messages.developerName,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _description,
            maxLength: 6000,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: context.messages.description,
            ),
          ),
          for (final (label, controller) in [
            (context.messages.repositoryLink, _repositoryUrl),
            (context.messages.downloadLink, _downloadUrl),
            (context.messages.onlineLink, _onlineUrl),
          ]) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: label),
              validator: (input) {
                final value = input?.trim() ?? '';
                return value.isEmpty || Library.isWebLink(value)
                    ? null
                    : context.messages.webAddressHelp;
              },
            ),
          ],
          if (_pickerError != null) Text(_pickerError!),
          const SizedBox(height: 12),
          DropdownButtonFormField<Kind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: context.messages.itemType),
            items: [
              DropdownMenuItem(
                value: Kind.game,
                child: Text(context.messages.game),
              ),
              DropdownMenuItem(
                value: Kind.app,
                child: Text(context.messages.app),
              ),
            ],
            onChanged: (kind) {
              if (kind != null) _kind = kind;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.messages.cancel),
      ),
      FilledButton(
        onPressed: _importingCover ? null : _submit,
        child: Text(context.messages.save),
      ),
    ],
  );
}

class _ItemImage {
  _ItemImage(this.path);
  String? path;
  XFile? selected;
}

class _AppPicker extends StatefulWidget {
  const _AppPicker(this.entries);
  final List<Entry> entries;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = filterEntries(
      widget.entries,
      _query,
      null,
    ).toList(growable: false);
    return AlertDialog(
      title: Text(context.messages.installedApps),
      content: SizedBox(
        width: 420,
        height: 340,
        child: Column(
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: context.messages.searchApps,
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(context.messages.noAppsFound))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final entry = matches[index];
                        return ListTile(
                          title: Text(entry.name),
                          subtitle: Text(entry.target),
                          onTap: () => Navigator.pop(context, entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
