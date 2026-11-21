import 'dart:ffi' show Abi;

import 'entry_status.dart';
import 'item_download.dart';
import 'item_installation.dart';
import 'library.dart';
import 'updates.dart';

class ItemUpdates {
  final _offeredInstallers = <String, ItemVersion>{};

  Future<void> check(
    List<Entry> entries, {
    required bool Function() active,
    required void Function(Entry, String, bool) onUpdated,
    required void Function(Entry, Object) onError,
  }) async {
    final releases = <String, Future<Map<String, dynamic>?>>{};
    for (final entry in entries) {
      if (!active()) return;
      final repository =
          EntryStatus.repository(entry.repositoryUrl) ??
          EntryStatus.repository(entry.downloadUrl);
      if (repository == null) continue;
      try {
        final installed = await installedVersion(entry);
        if (installed == null || installed.tag.isEmpty) continue;
        final release = await releases.putIfAbsent(
          repository.toLowerCase(),
          () => Updater.latestRelease(repository),
        );
        if (release == null || !active()) continue;
        final package = selectItemPackage(
          release,
          repository,
          Abi.current(),
          platforms: entry.platforms,
        );
        if (package == null ||
            !isNewerItemVersion(package.version, installed)) {
          continue;
        }
        final key = ItemInstallation.key(entry);
        if (_offeredInstallers[key] == package.version) continue;
        final current = await installedVersion(entry);
        if (current == null ||
            !active() ||
            !isNewerItemVersion(package.version, current))
          continue;
        final file = await ItemInstallation.downloadAndInstall(
          entry,
          package.url,
          package.name,
          (_) {},
          () {
            if (!active()) throw StateError('Launcher is not active');
          },
          size: package.size,
          digest: package.digest,
          github: true,
          version: package.version,
        );
        if (file == null) _offeredInstallers[key] = package.version;
        onUpdated(entry, package.version.tag, file != null);
        if (file == null) return;
      } catch (error) {
        onError(entry, error);
      }
    }
  }

  static Future<ItemVersion?> installedVersion(Entry entry) async {
    final portable = await ItemInstallation.portable(entry);
    if (portable != null) {
      return portable.version ?? (tag: '', publishedAt: null, revision: null);
    }
    if (!EntryStatus.hasInstallationId(entry)) return null;
    final tag = await EntryStatus.installedVersion(entry);
    return tag == null ? null : (tag: tag, publishedAt: null, revision: null);
  }
}
