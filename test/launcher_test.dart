import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:bigevil_launcher/dashboard.dart';
import 'package:bigevil_launcher/entry_details.dart';
import 'package:bigevil_launcher/entry_status.dart';
import 'package:bigevil_launcher/item_download.dart';
import 'package:bigevil_launcher/item_installation.dart';
import 'package:bigevil_launcher/library.dart';
import 'package:bigevil_launcher/main.dart';
import 'package:bigevil_launcher/updates.dart';
import 'package:bigevil_launcher/localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('language preference persists and defaults to the system', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bigevil-language-',
    );
    final file = File('${directory.path}/language.txt');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
      await directory.delete();
    });
    final preference = LanguagePreference(file);
    expect(await preference.load(), InterfaceLanguage.system);
    await preference.save(InterfaceLanguage.english);
    expect(await LanguagePreference(file).load(), InterfaceLanguage.english);
    await preference.save(InterfaceLanguage.spanish);
    expect(await LanguagePreference(file).load(), InterfaceLanguage.spanish);
    await file.writeAsString('unsupported');
    expect(await preference.load(), InterfaceLanguage.system);
  });

  testWidgets('language picker switches library labels without restarting', (
    tester,
  ) async {
    var language = InterfaceLanguage.ptBR;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          locale: language.locale,
          supportedLocales: InterfaceLanguage.supportedLocales,
          localizationsDelegates: const [
            Messages.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Launcher(
            language: language,
            onLanguageChanged: (value) async =>
                setState(() => language = value),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Idioma'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byTooltip('Language'), findsOneWidget);
    expect(find.text('Search games and apps...'), findsOneWidget);
    await tester.tap(find.byTooltip('Language'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Español'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Buscar juegos y aplicaciones...'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('library entries round-trip and search by category and target', () {
    final game = Entry('Corrida', '/games/race', Kind.game);
    final app = Entry('Editor', '/apps/draw', Kind.app);
    expect(Entry.fromJson(game.toJson()).toJson(), game.toJson());
    expect(Entry.fromJson(game.toJson()).coverPath, isNull);
    final illustrated = Entry(
      'Editor',
      '/apps/draw',
      Kind.app,
      coverPath: '/covers/editor.img',
    );
    expect(
      Entry.fromJson(illustrated.toJson()).coverPath,
      illustrated.coverPath,
    );
    expect(filterEntries([game, app], ' RACE ', Kind.game), [game]);
    expect(filterEntries([game, app], '', Kind.app), [app]);
    expect(filterEntries([game, app], 'none', null), isEmpty);
    expect(Library.isWebLink('https://example.org'), isTrue);
    expect(Library.isWebLink('file:///tmp/example'), isFalse);
  });

  test('blank update settings use the official repository by default', () {
    expect(Updater.resolveRepository(''), 'bigevilmods/BigEvil-Launcher');
    expect(Updater.resolveRepository('owner/fork'), 'owner/fork');
  });

  test('catalog accepts remote items and rejects local paths', () {
    final entries = Library.parseCatalog('''
      [
        {
          "name": "Corrida",
          "kind": "game",
          "coverPath": "https://example.org/cover.webp",
          "onlineUrl": "https://example.org/play"
        },
        {"name": "Editor", "kind": "app"}
      ]
    ''');
    expect(entries.map((entry) => entry.kind), [Kind.game, Kind.app]);
    expect(entries.first.target, isEmpty);
    expect(entries.first.coverPath, 'https://example.org/cover.webp');
    expect(Library.parseCatalog('[]'), isEmpty);
    expect(
      () => Library.parseCatalog(
        '[{"name":"Corrida","kind":"game","target":"file:///race.exe"}]',
      ),
      throwsFormatException,
    );
  });

  test('catalog keeps installation identifiers and validates GitHub URLs', () {
    final entry = Library.parseCatalog('''
      [{
        "name": "Example",
        "kind": "app",
        "repositoryUrl": "https://github.com/demo/example.git/",
        "androidPackage": "org.example.app",
        "windowsUninstallKey": "{12345678-1234-1234-1234-123456789abc}",
        "linuxPackage": "example-app"
      }]
    ''').single;
    expect(entry.toJson()['androidPackage'], 'org.example.app');
    expect(entry.windowsUninstallKey, startsWith('{12345678'));
    expect(entry.linuxPackage, 'example-app');
    expect(EntryStatus.repository(entry.repositoryUrl), 'demo/example');
    expect(
      EntryStatus.repository('https://github.com/demo/app/issues'),
      isNull,
    );
    expect(
      EntryStatus.repository('https://github.com.example/demo/app'),
      isNull,
    );
  });

  test('catalog platform tags round-trip and filter case-insensitively', () {
    final entries = Library.parseCatalog('''
      [
        {"name":"Game","kind":"game","plataforma":[" Windows ","windows","Sega Dreamcast"]},
        {"name":"App","kind":"app","plataforma":"Android"},
        {"name":"Classic","kind":"game"}
      ]
    ''');
    expect(entries.first.platforms, ['Windows', 'Sega Dreamcast']);
    expect(
      Entry.fromJson(entries.first.toJson()).platforms,
      entries.first.platforms,
    );
    expect(entries.last.platforms, isEmpty);
    expect(filterEntries(entries, 'dreamcast', null), [entries.first]);
    expect(filterEntries(entries, '', Kind.game, platform: 'windows'), [
      entries.first,
    ]);
    expect(filterEntries(entries, '', Kind.game, platform: 'Android'), isEmpty);
  });

  test('release selection ignores old and prerelease builds', () {
    expect(isNewer('v1.10.0', '1.9.9'), isTrue);
    expect(isNewer('v1.0.0', '1.0.0'), isFalse);
    expect(isNewer('v1.9.0-beta', '1.0.0'), isFalse);
    expect(
      selectRelease(
        {'tag_name': 'v1.1.0', 'prerelease': true},
        'owner/repo',
        'test.apk',
        '1.0.0',
      ),
      isNull,
    );
  });

  test('item releases select only a package for the current platform', () {
    Map<String, Object> asset(String name, {String host = 'github.com'}) => {
      'name': name,
      'state': 'uploaded',
      'size': 1024,
      'browser_download_url':
          'https://$host/Demo/Game/releases/download/v2/$name',
    };
    final release = {
      'tag_name': 'v2',
      'assets': [
        asset('game-windows-arm64.msi'),
        asset('game-windows-x64.msi', host: 'example.org'),
        asset('game-windows-x64.exe'),
        asset('game-linux-arm64.deb'),
        asset('game-linux-x86_64.AppImage'),
        asset('game-android-arm64-v8a.apk'),
        asset('game-android.apk'),
      ],
    };
    String? select(Abi abi) =>
        selectItemPackage(release, 'demo/game', abi)?.name;
    expect(select(Abi.windowsX64), 'game-windows-x64.exe');
    expect(select(Abi.linuxX64), 'game-linux-x86_64.AppImage');
    expect(select(Abi.androidArm64), 'game-android-arm64-v8a.apk');
    expect(select(Abi.androidIA32), 'game-android.apk');
    expect(select(Abi.macosArm64), isNull);
  });

  test('item updates compare versions and detect replaced release assets', () {
    ItemVersion version(String tag, {DateTime? date, String? revision}) =>
        (tag: tag, publishedAt: date, revision: revision);
    final early = DateTime.utc(2025);
    final late = DateTime.utc(2026);
    expect(isNewerItemVersion(version('v1.4.0'), version('1.3.0')), isTrue);
    expect(
      isNewerItemVersion(
        version('v1.2.0', date: late),
        version('v1.3.0', date: early),
      ),
      isFalse,
    );
    expect(
      isNewerItemVersion(
        version('release', revision: '2'),
        version('release', revision: '1'),
      ),
      isTrue,
    );
    expect(
      isNewerItemVersion(
        version('release', revision: '1'),
        version('release', revision: '1'),
      ),
      isFalse,
    );
    expect(
      isNewerItemVersion(
        version('current', date: late),
        version('old', date: early),
      ),
      isTrue,
    );
    expect(
      isNewerItemVersion(version('current', date: late), version('unknown')),
      isFalse,
    );
  });

  testWidgets('details gate local play and require an online URL', (
    tester,
  ) async {
    final entry = Entry(
      'Corrida',
      '/games/race',
      Kind.game,
      description: 'Pistas para corrida.',
      developer: 'Studio',
      repositoryUrl: 'https://github.com/demo/race',
      downloadUrl: 'https://example.org/race.zip',
      onlineUrl: 'https://example.org/play',
      platforms: ['Windows', 'Sega Dreamcast'],
      backgroundPath: null,
    );
    expect(Entry.fromJson(entry.toJson()).toJson(), entry.toJson());
    expect(filterEntries([entry], 'studio', null), [entry]);
    expect(Library.webUri('javascript:alert(1)'), isNull);
    Entry? opened;
    Widget details(Entry item) => MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: InterfaceLanguage.supportedLocales,
      localizationsDelegates: const [
        Messages.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: EntryDetails(
        key: ValueKey(item),
        entry: item,
        onOpen: (value) async => opened = value,
      ),
    );
    await tester.pumpWidget(details(entry));
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('Pistas para corrida.'), findsOneWidget);
    expect(find.text('Repositório'), findsOneWidget);
    expect(find.text('Baixar e instalar'), findsOneWidget);
    expect(find.text('Jogar online'), findsOneWidget);
    expect(find.text('Sega Dreamcast'), findsOneWidget);
    final play = find.widgetWithText(FilledButton, 'Jogar');
    expect(tester.widget<FilledButton>(play).onPressed, isNull);
    expect(opened, isNull);
    await tester.pumpWidget(
      details(Entry('Corrida', '/games/race', Kind.game)),
    );
    expect(find.text('Jogar online'), findsNothing);
  });

  test('Windows archive extraction finds a selected executable', () async {
    final root = await Directory.systemTemp.createTemp('bigevil-archive-');
    addTearDown(() => root.delete(recursive: true));
    final source = await Directory('${root.path}/source').create();
    await File('${source.path}/Game.exe').writeAsBytes([77, 90, 0, 0]);
    await File('${source.path}/Helper.exe').writeAsBytes([77, 90, 0, 0]);
    final archive = File('${root.path}/game.zip');
    final tar =
        '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\tar.exe';
    final packed = await Process.run(tar, [
      '-acf',
      archive.path,
      '-C',
      source.path,
      '.',
    ]);
    expect(packed.exitCode, 0, reason: packed.stderr.toString());
    final content = await Directory('${root.path}/content').create();
    final executable = await ItemInstallation.extractExecutable(
      archive,
      content,
      'Game.exe',
    );
    expect(executable.path, endsWith('Game.exe'));

    final ambiguous = await Directory('${root.path}/ambiguous').create();
    await expectLater(
      ItemInstallation.extractExecutable(archive, ambiguous, ''),
      throwsStateError,
    );
  }, skip: !Platform.isWindows);

  test('Windows staging cleanup removes read-only archive contents', () async {
    final staging = await Directory.systemTemp.createTemp('bigevil-staging-');
    addTearDown(() => ItemInstallation.discardStaging(staging));
    final content = await Directory('${staging.path}/content').create();
    final file = await File('${content.path}/source.cpp')
        .writeAsString('source');
    final attrib =
        '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\attrib.exe';
    for (final path in [file.path, content.path]) {
      final result = await Process.run(attrib, ['+R', path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }
    await ItemInstallation.discardStaging(staging);
    expect(await staging.exists(), isFalse);
  }, skip: !Platform.isWindows);

  test('release rejects wrong host, missing digest and unbounded packages', () {
    const repository = 'owner/repo';
    const asset = 'test.apk';
    final metadata = {
      'name': asset,
      'state': 'uploaded',
      'size': 42,
      'digest': 'sha256:${'a' * 64}',
      'browser_download_url':
          'https://github.com/$repository/releases/download/v1.2.0/$asset',
    };
    Release? select(Map<String, Object> data) => selectRelease(
      {
        'tag_name': 'v1.2.0',
        'assets': [data],
      },
      repository,
      asset,
      '1.0.0',
    );
    expect(select(metadata)?.size, 42);
    expect(() => select({...metadata, 'digest': ''}), throwsStateError);
    expect(
      () => select({...metadata, 'size': maximumPackageBytes + 1}),
      throwsStateError,
    );
    expect(
      () => select({
        ...metadata,
        'browser_download_url': 'https://example.org/test.apk',
      }),
      throwsStateError,
    );
  });

  testWidgets('responsive library fits a small viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: InterfaceLanguage.supportedLocales,
        localizationsDelegates: const [
          Messages.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Column(
            children: [
              DashboardGallery(
                kind: Kind.game,
                entries: [Entry('Corrida', '/games/race', Kind.game)],
                hasSearch: false,
                onOpen: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('BIBLIOTECA DE JOGOS'), findsOneWidget);
    expect(find.text('CORRIDA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop gallery launches only downloaded games', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = List.generate(
      8,
      (i) => Entry('Corrida $i', '/games/race-$i', Kind.game),
    );
    Entry? opened;
    Kind? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: InterfaceLanguage.supportedLocales,
        localizationsDelegates: const [
          Messages.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardNavigation(
                desktop: true,
                selected: null,
                onSelect: (kind) => selected = kind,
                onSettings: null,
              ),
              Expanded(
                child: DashboardGallery(
                  kind: Kind.game,
                  entries: entries,
                  hasSearch: false,
                  onOpen: (entry) => opened = entry,
                  canPlay: (entry) => entry == entries.first,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aplicativos'));
    expect(selected, Kind.app);
    final playButtons = find.widgetWithText(TextButton, 'Jogar');
    expect(tester.widget<TextButton>(playButtons.at(1)).onPressed, isNull);
    await tester.tap(find.text('Jogar').first);
    expect(opened, same(entries.first));
    final gallery = tester.state<ScrollableState>(find.byType(Scrollable));
    await tester.tap(find.byTooltip('Avançar na galeria'));
    await tester.pumpAndSettle();
    expect(gallery.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
