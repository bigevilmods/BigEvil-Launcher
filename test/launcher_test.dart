import 'dart:io';

import 'package:bigevil_launcher/dashboard.dart';
import 'package:bigevil_launcher/entry_details.dart';
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

  testWidgets('details render stored metadata and offline and online actions', (
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
      backgroundPath: null,
    );
    expect(Entry.fromJson(entry.toJson()).toJson(), entry.toJson());
    expect(filterEntries([entry], 'studio', null), [entry]);
    expect(Library.webUri('javascript:alert(1)'), isNull);
    Entry? opened;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: InterfaceLanguage.supportedLocales,
        localizationsDelegates: const [
          Messages.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: EntryDetails(
          entry: entry,
          onOpen: (value) async => opened = value,
        ),
      ),
    );
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('Pistas para corrida.'), findsOneWidget);
    expect(find.text('Repositório'), findsOneWidget);
    expect(find.text('Baixar'), findsOneWidget);
    expect(find.text('Jogar online'), findsOneWidget);
    await tester.tap(find.text('Jogar'));
    expect(opened, same(entry));
  });

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

  testWidgets('responsive library and editor fit a small viewport', (
    tester,
  ) async {
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
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<Entry>(
                    context: context,
                    builder: (_) => const EntryEditor(),
                  ),
                  child: const Text('Novo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('BIBLIOTECA DE JOGOS'), findsOneWidget);
    expect(find.text('CORRIDA'), findsOneWidget);
    await tester.tap(find.text('Novo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um nome.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop gallery scrolls and launches the selected game', (
    tester,
  ) async {
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aplicativos'));
    expect(selected, Kind.app);
    await tester.tap(find.text('Jogar').first);
    expect(opened, same(entries.first));
    final gallery = tester.state<ScrollableState>(find.byType(Scrollable));
    await tester.tap(find.byTooltip('Avançar na galeria'));
    await tester.pumpAndSettle();
    expect(gallery.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
