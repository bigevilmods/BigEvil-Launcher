import 'dart:io';

import 'library.dart';
import 'updates.dart';

class EntryStatus {
  static String? repository(String address) {
    final uri = Library.webUri(address);
    if (uri == null || uri.host != 'github.com' || uri.hasPort) return null;
    final parts = uri.pathSegments.toList();
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    if (parts.length != 2) return null;
    final slug =
        '${parts.first}/${parts.last.replaceFirst(RegExp(r'\.git$'), '')}';
    return repositoryPattern.hasMatch(slug) ? slug : null;
  }

  static bool hasInstallationId(Entry entry) {
    if (Platform.isAndroid) return entry.androidPackage.isNotEmpty;
    if (Platform.isWindows) return entry.windowsUninstallKey.isNotEmpty;
    return Platform.isLinux && entry.linuxPackage.isNotEmpty;
  }

  // Null means no installation was found. An empty version means installed
  // with no reported version.
  static Future<String?> installedVersion(Entry entry) async {
    if (Platform.isAndroid) {
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')
          .hasMatch(entry.androidPackage)) {
        throw const FormatException('Invalid Android package ID');
      }
      return Library.android.invokeMethod<String>(
        'installedVersion',
        entry.androidPackage,
      );
    }
    if (Platform.isLinux) {
      if (!RegExp(r'^[a-z0-9][a-z0-9+.-]+$').hasMatch(entry.linuxPackage)) {
        throw const FormatException('Invalid Debian package ID');
      }
      final result = await Process.run('/usr/bin/dpkg-query', [
        '-W',
        r'-f=${db:Status-Status}\t${Version}',
        '--',
        entry.linuxPackage,
      ]);
      if (result.exitCode == 1) return null;
      if (result.exitCode != 0) throw StateError('dpkg-query failed');
      final fields = result.stdout.toString().split('\t');
      return fields.first == 'installed' ? fields.last.trim() : null;
    }
    final key = entry.windowsUninstallKey;
    if (!RegExp(r'^[\w .{}()+-]+$').hasMatch(key)) {
      throw const FormatException('Invalid Windows uninstall key');
    }
    for (final hive in ['HKCU', 'HKLM']) {
      for (final view in ['/reg:64', '/reg:32']) {
        final result = await Process.run('reg.exe', [
          'query',
          '$hive\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$key',
          view,
        ]);
        if (result.exitCode == 1) continue;
        if (result.exitCode != 0) throw StateError('Registry query failed');
        return RegExp(
              r'^\s*DisplayVersion\s+REG_\w+\s+(.+)$',
              multiLine: true,
            ).firstMatch(result.stdout.toString())?.group(1)?.trim() ??
            '';
      }
    }
    return null;
  }

  static Future<String?> latestVersion(String repository) async {
    final release = await Updater.latestRelease(repository);
    final tag = release?['tag_name'];
    return tag is String &&
            tag.isNotEmpty &&
            release?['draft'] != true &&
            release?['prerelease'] != true
        ? tag
        : null;
  }
}
