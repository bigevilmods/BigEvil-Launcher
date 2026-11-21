import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'l10n/generated/messages.dart';

export 'l10n/generated/messages.dart';

enum InterfaceLanguage {
  system(null),
  ptBR(Locale('pt', 'BR')),
  english(Locale('en')),
  spanish(Locale('es'));

  const InterfaceLanguage(this.locale);

  final Locale? locale;

  static const supportedLocales = [
    Locale('pt', 'BR'),
    Locale('en'),
    Locale('es'),
  ];

  String label(Messages messages) => switch (this) {
    system => messages.systemLanguage,
    ptBR => 'Português (Brasil)',
    english => 'English',
    spanish => 'Español',
  };
}

class LanguagePreference {
  const LanguagePreference(this.file);

  final File file;

  static Future<LanguagePreference> forApp() async => LanguagePreference(
    File('${(await getApplicationSupportDirectory()).path}/language.txt'),
  );

  Future<InterfaceLanguage> load() async {
    if (!await file.exists()) return InterfaceLanguage.system;
    final name = (await file.readAsString()).trim();
    return InterfaceLanguage.values
            .where((language) => language.name == name)
            .firstOrNull ??
        InterfaceLanguage.system;
  }

  Future<void> save(InterfaceLanguage language) async {
    await file.parent.create(recursive: true);
    final temporary = await file.parent.createTemp('.language-');
    final staged = File('${temporary.path}/language.txt');
    try {
      await staged.writeAsString(language.name, flush: true);
      await staged.rename(file.path);
    } finally {
      if (await staged.exists()) await staged.delete();
      await temporary.delete();
    }
  }
}

extension LocalizedContext on BuildContext {
  Messages get messages => Messages.of(this);
}

class LocalizedFailure extends StateError {
  LocalizedFailure(this.translate) : super('Launcher operation failed');

  final String Function(Messages) translate;
}

String localizedError(Messages messages, Object error) {
  if (error is LocalizedFailure) return error.translate(messages);
  if (error is PlatformException) {
    return switch (error.code) {
      'app_unavailable' => messages.androidAppUnavailable,
      'install_permission' => messages.androidInstallPermission,
      _ => error.message ?? error.code,
    };
  }
  return error.toString();
}
