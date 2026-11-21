import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'entry_status.dart';
import 'item_download.dart';
import 'library.dart';
import 'localization.dart';
import 'updates.dart';

class ItemInstallation {
  static final _active = <String, Future<File?>>{};

  static String key(Entry entry) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            entry.kind.name,
            entry.name,
            entry.repositoryUrl,
            entry.downloadUrl,
          ]),
        ),
      )
      .toString();

  static Future<Directory> _directory(Entry entry) async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/installed/${key(entry)}');
  }

  // Returns the executable for a portable installation, or null when the
  // package was handed off to the system installer.
  static Future<File?> downloadAndInstall(
    Entry entry,
    Uri address,
    String name,
    void Function(double?) progress,
    void Function() installing, {
    int? size,
    String? digest,
    bool github = false,
    ItemVersion? version,
  }) {
    final id = key(entry);
    return _active.putIfAbsent(id, () async {
      try {
        return await _install(
          entry,
          address,
          name,
          progress,
          installing,
          size: size,
          digest: digest,
          github: github,
          version: version,
        );
      } finally {
        _active.remove(id);
      }
    });
  }

  static Future<File?> _install(
    Entry entry,
    Uri address,
    String name,
    void Function(double?) progress,
    void Function() installing, {
    required int? size,
    required String? digest,
    required bool github,
    required ItemVersion? version,
  }) async {
    if (!Updater.isDownloadName(name)) {
      throw LocalizedFailure((messages) => messages.invalidAddress);
    }
    final root = Platform.isAndroid
        ? Directory('${(await getApplicationCacheDirectory()).path}/updates')
        : await _directory(entry);
    await root.create(recursive: true);
    final staging = await root.createTemp('.install-');
    var keep = false;
    try {
      final file = await Updater.downloadItem(
        address,
        File('${staging.path}/$name'),
        progress,
        size: size,
        digest: digest,
        github: github,
      );
      installing();
      final lowerName = name.toLowerCase();
      final systemPackage =
          Platform.isAndroid ||
          (Platform.isWindows &&
              (lowerName.endsWith('.msi') ||
                  (lowerName.endsWith('.exe') &&
                      (entry.windowsUninstallKey.isNotEmpty ||
                          RegExp(r'setup|installer|install\.exe$')
                              .hasMatch(lowerName))))) ||
          (Platform.isLinux && RegExp(r'\.(deb|rpm)$').hasMatch(lowerName));
      if (systemPackage) {
        var installer = file;
        if (Platform.isAndroid) {
          if (lowerName.endsWith('.zip')) {
            final path = await Library.android.invokeMethod<String>(
              'extractItemApk',
              {'archive': file.path, 'executable': entry.executable},
            );
            if (path == null)
              throw LocalizedFailure(
                (messages) => messages.itemExtractionFailed,
              );
            installer = File(path);
            await file.delete();
          } else if (!lowerName.endsWith('.apk')) {
            throw LocalizedFailure(
              (messages) => messages.unsupportedItemPackage,
            );
          }
        }
        // Keep Linux packages available if there is no associated installer.
        keep = Platform.isLinux;
        await _openInstaller(installer);
        // System installers can read the package after the handoff returns.
        keep = true;
        return null;
      }
      final File executable;
      if (RegExp(r'\.(zip|rar|tgz|tar\.(gz|xz|bz2|zst))$')
          .hasMatch(lowerName)) {
        final content = await Directory('${staging.path}/content').create();
        executable = await extractExecutable(file, content, entry.executable);
        await file.delete();
      } else if (await _isExecutable(file)) {
        executable = file;
      } else {
        throw LocalizedFailure((messages) => messages.unsupportedItemPackage);
      }
      if (Platform.isLinux) {
        final result = await Process.run('/usr/bin/chmod', [
          'u+x',
          '--',
          executable.path,
        ]);
        if (result.exitCode != 0)
          throw FileSystemException('chmod failed', executable.path);
      }
      final relative = executable.path.substring(staging.path.length + 1);
      await File('${staging.path}/launch.json').writeAsString(
        jsonEncode({
          'executable': relative,
          if (version != null) ...{
            'tag': version.tag,
            'publishedAt': version.publishedAt?.toIso8601String(),
            'revision': version.revision,
          },
        }),
        flush: true,
      );
      final suffix = staging.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      final published = await staging.rename(
        '${root.path}/${suffix.substring(1)}',
      );
      keep = true;
      return File('${published.path}/$relative');
    } finally {
      if (!keep) await discardStaging(staging);
    }
  }

  static Future<void> discardStaging(Directory staging) async {
    try {
      if (!await staging.exists()) return;
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        if (!Platform.isWindows) rethrow;
        final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        final attrib = '$root\\System32\\attrib.exe';
        await for (final item in staging.list(
          recursive: true,
          followLinks: false,
        )) {
          if (item is File || item is Directory) {
            await Process.run(attrib, ['-R', '-H', '-S', item.path]);
          }
        }
        await Process.run(attrib, ['-R', '-H', '-S', staging.path]);
        await staging.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Could not remove temporary item installation',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> _openInstaller(File file) async {
    if (Platform.isAndroid) {
      await Library.android.invokeMethod<void>('installItem', file.path);
    } else if (Platform.isWindows) {
      final isMsi = file.path.toLowerCase().endsWith('.msi');
      await Process.start(
        isMsi ? 'msiexec.exe' : file.path,
        isMsi ? ['/i', file.path] : [],
        workingDirectory: file.parent.path,
        mode: ProcessStartMode.detached,
      );
    } else if (!await launchUrl(
      file.uri,
      mode: LaunchMode.externalApplication,
    )) {
      throw LocalizedFailure(
        (messages) => messages.openLinuxPackage(file.path),
      );
    }
  }

  static Future<({File file, ItemVersion? version})?> portable(
    Entry entry,
  ) async {
    try {
      final root = await _directory(entry);
      if (!await root.exists()) return null;
      ({File file, ItemVersion? version})? latest;
      DateTime? installedAt;
      await for (final item in root.list(followLinks: false)) {
        if (item is! Directory ||
            !item.uri.pathSegments
                .where((part) => part.isNotEmpty)
                .last
                .startsWith('install-'))
          continue;
        final manifest = File('${item.path}/launch.json');
        if (!await manifest.exists()) continue;
        final data = jsonDecode(await manifest.readAsString());
        final relative = data is Map ? data['executable'] : data;
        if (relative is! String || !_safePath(relative)) continue;
        final file = File('${item.path}/$relative');
        if (!await file.exists()) continue;
        final resolved = await file.resolveSymbolicLinks();
        final directory = await item.resolveSymbolicLinks();
        if (!resolved.startsWith('$directory${Platform.pathSeparator}'))
          continue;
        final timestamp = await manifest.lastModified();
        if (installedAt == null || timestamp.isAfter(installedAt)) {
          installedAt = timestamp;
          final tag = data is Map ? data['tag'] : null;
          final publishedAt = data is Map ? data['publishedAt'] : null;
          final revision = data is Map ? data['revision'] : null;
          latest = (
            file: file,
            version: tag is String
                ? (
                    tag: tag,
                    publishedAt: publishedAt is String
                        ? DateTime.tryParse(publishedAt)
                        : null,
                    revision: revision is String ? revision : null,
                  )
                : null,
          );
        }
      }
      return latest;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> canPlay(Entry entry) async {
    if (await portable(entry) != null) return true;
    if (!EntryStatus.hasInstallationId(entry) ||
        (!Platform.isAndroid && !Library.isWebLink(entry.target)))
      return false;
    try {
      return await EntryStatus.installedVersion(entry) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> launch(Entry entry) async {
    final file = (await portable(entry))?.file;
    if (file != null) {
      await Process.start(
        file.path,
        [],
        workingDirectory: file.parent.path,
        mode: ProcessStartMode.detached,
      );
    } else if (await canPlay(entry)) {
      if (Platform.isAndroid) {
        await Library.android.invokeMethod<void>(
          'launch',
          entry.androidPackage,
        );
      } else {
        await Library.open(entry);
      }
    } else {
      throw LocalizedFailure((messages) => messages.noItemExecutable);
    }
  }

  static bool _safePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(normalized))
      return false;
    return normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .every(
          (part) =>
              part != '..' &&
              !part.endsWith('.') &&
              !part.endsWith(' ') &&
              !RegExp(
                r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)',
                caseSensitive: false,
              ).hasMatch(part),
        );
  }

  static Future<File> extractExecutable(
    File archive,
    Directory content,
    String configured,
  ) async {
    final tar = Platform.isWindows
        ? '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\tar.exe'
        : '/usr/bin/bsdtar';
    if (!await File(tar).exists()) {
      throw LocalizedFailure((messages) => messages.archiveExtractorMissing);
    }
    final listing = await Process.run(tar, ['-tf', archive.path]);
    final details = await Process.run(tar, ['-tvf', archive.path]);
    final paths = const LineSplitter().convert(listing.stdout.toString());
    final types = const LineSplitter().convert(details.stdout.toString());
    if (listing.exitCode != 0 ||
        details.exitCode != 0 ||
        paths.isEmpty ||
        paths.length > 100000 ||
        paths.length != types.length ||
        paths.any((name) => !_safePath(name)) ||
        types.any(
          (line) =>
              line.isEmpty ||
              !'-d'.contains(line[0]) ||
              line.contains(' link to '),
        )) {
      throw LocalizedFailure((messages) => messages.itemExtractionFailed);
    }
    var expanded = 0;
    final sizeColumn = RegExp(r'^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s');
    for (final line in types) {
      final size = int.tryParse(sizeColumn.firstMatch(line)?.group(1) ?? '');
      if (size == null || size > maximumItemBytes - expanded) {
        throw LocalizedFailure((messages) => messages.itemExtractionFailed);
      }
      expanded += size;
    }
    final result = await Process.run(tar, [
      '-xf',
      archive.path,
      '-C',
      content.path,
      '-k',
      '--safe-writes',
      '--no-same-owner',
      '--no-same-permissions',
      '--no-acls',
      '--no-xattrs',
      '--no-fflags',
    ]);
    if (result.exitCode != 0) {
      throw LocalizedFailure((messages) => messages.itemExtractionFailed);
    }
    final candidates = <File>[];
    final preferred = configured.replaceAll('\\', '/');
    if (preferred.isNotEmpty && !_safePath(preferred)) {
      throw LocalizedFailure((messages) => messages.noItemExecutable);
    }
    await for (final item in content.list(
      recursive: true,
      followLinks: false,
    )) {
      if (item is Link)
        throw LocalizedFailure((messages) => messages.itemExtractionFailed);
      if (item is! File) continue;
      final relative = item.path
          .substring(content.path.length + 1)
          .replaceAll('\\', '/');
      if ((preferred.isEmpty || relative == preferred) &&
          await _isExecutable(item, allowScript: preferred.isNotEmpty)) {
        candidates.add(item);
      }
    }
    if (candidates.isEmpty && preferred.isEmpty) {
      throw LocalizedFailure((messages) => messages.archiveHasNoExecutable);
    }
    if (candidates.length != 1) {
      throw LocalizedFailure((messages) => messages.noItemExecutable);
    }
    return candidates.single;
  }

  static Future<bool> _isExecutable(
    File file, {
    bool allowScript = false,
  }) async {
    if (Platform.isWindows && !file.path.toLowerCase().endsWith('.exe'))
      return false;
    if (!Platform.isWindows && !Platform.isLinux) return false;
    final reader = await file.open();
    try {
      final header = await reader.read(4);
      if (Platform.isWindows)
        return header.length >= 2 && header[0] == 77 && header[1] == 90;
      if (allowScript &&
          header.length >= 2 &&
          header[0] == 35 &&
          header[1] == 33) {
        return true;
      }
      return header.length == 4 &&
          header[0] == 127 &&
          header[1] == 69 &&
          header[2] == 76 &&
          header[3] == 70;
    } finally {
      await reader.close();
    }
  }
}
