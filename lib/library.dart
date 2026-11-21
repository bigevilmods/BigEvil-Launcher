import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'entry.dart';
export 'entry.dart';

class Library {
  static const android = MethodChannel('bigevil/android');
  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/library.json');

  static Future<String> importCover(XFile source) async {
    const limit = 8 * 1024 * 1024;
    if (await source.length() > limit) {
      throw const FormatException('Escolha uma imagem de até 8 MiB.');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length > limit) {
      throw const FormatException('Escolha uma imagem de até 8 MiB.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final image = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (image.width > 4096 || image.height > 4096) {
          throw const FormatException(
            'Use uma imagem de até 4096 × 4096 pixels.',
          );
        }
      } finally {
        image.dispose();
      }
    } finally {
      buffer.dispose();
    }
    final directory = Directory('${(await _file()).parent.path}/covers');
    await directory.create(recursive: true);
    final file = File('${directory.path}/${sha256.convert(bytes)}.img');
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<List<Entry>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    return data
        .map((item) => Entry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<Entry> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = await file.parent.createTemp('.library-');
    try {
      final staged = File('${temporary.path}/library.json');
      await staged.writeAsString(jsonEncode(entries), flush: true);
      await staged.rename(file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  static Future<List<Entry>> installedAndroidApps() async {
    final items = await android.invokeListMethod<Map<Object?, Object?>>('apps');
    return (items ?? [])
        .map(
          (item) => Entry(
            item['name'] as String,
            item['package'] as String,
            Kind.app,
          ),
        )
        .toList();
  }

  static bool isWebLink(String value) => webUri(value) != null;

  static Uri? webUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      return null;
    return uri;
  }

  static Future<void> openWebLink(String address) async {
    final uri = webUri(address);
    if (uri == null) throw const FormatException('Endereço web inválido.');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('O sistema não abriu o link.');
    }
  }

  static Future<void> open(Entry entry) async {
    final target = entry.target;
    if (isWebLink(target)) {
      await openWebLink(target);
      return;
    }
    if (Platform.isAndroid) {
      await android.invokeMethod<void>('launch', target);
      return;
    }
    if (!await File(target).exists()) {
      throw StateError('O arquivo foi movido ou excluído.');
    }
    if (Platform.isLinux && target.endsWith('.desktop')) {
      final result = await Process.run('gio', [
        'launch',
        File(target).absolute.path,
      ]);
      if (result.exitCode == 0) return;
      throw StateError('O sistema não abriu o atalho.');
    }
    if (Platform.isWindows && target.toLowerCase().endsWith('.lnk')) {
      if (await launchUrl(
        Uri.file(target),
        mode: LaunchMode.externalApplication,
      ))
        return;
      throw StateError('O sistema não abriu o atalho.');
    }
    final file = File(target).absolute;
    await Process.start(
      file.path,
      [],
      workingDirectory: file.parent.path,
      mode: ProcessStartMode.detached,
    );
  }
}
