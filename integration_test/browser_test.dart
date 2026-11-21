import 'dart:io';

import 'package:bigevil_launcher/online_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the embedded desktop browser runs WebAssembly', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>BigEvil browser test</title>',
      );
      await request.response.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineBrowser(
          title: 'Teste do navegador',
          initialUrl: Uri.http('127.0.0.1:${server.port}', '/'),
        ),
      ),
    );
    final probe = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == 'Verificar WebAssembly, WebGL e outros recursos',
    );
    final timeout = DateTime.now().add(const Duration(seconds: 25));
    while (tester.widget<IconButton>(probe).onPressed == null &&
        DateTime.now().isBefore(timeout)) {
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    expect(find.byType(MaterialBanner), findsNothing);
    expect(tester.widget<IconButton>(probe).onPressed, isNotNull);
    await tester.tap(probe);
    final result = find.text('WebAssembly: Disponível');
    while (result.evaluate().isEmpty && DateTime.now().isBefore(timeout)) {
      await tester.pump(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    expect(result, findsOneWidget);
    expect(find.textContaining('WebGL 2:'), findsOneWidget);
    for (final widget in tester.widgetList<Text>(
      find.textContaining(RegExp(r'^Web(?:Assembly|GL)')),
    )) {
      debugPrint(widget.data);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !(Platform.isWindows || Platform.isLinux));
}
