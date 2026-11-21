import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'library.dart';
import 'localization.dart';

const currentVersion = String.fromEnvironment(
  'BIGEVIL_VERSION',
  defaultValue: '1.3.0',
);
const defaultRepository = String.fromEnvironment(
  'BIGEVIL_REPOSITORY',
  defaultValue: 'bigevilmods/BigEvil-Launcher',
);
final repositoryPattern = RegExp(r'^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$');
final versionPattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');
const maximumPackageBytes = 512 * 1024 * 1024;

bool isNewer(String candidate, String installed) {
  final next = versionPattern.firstMatch(candidate);
  final current = versionPattern.firstMatch(installed);
  if (next == null || current == null) return false;
  for (var i = 1; i <= 3; i++) {
    final comparison = BigInt.parse(next[i]!)
        .compareTo(BigInt.parse(current[i]!));
    if (comparison != 0) return comparison > 0;
  }
  return false;
}

class Release {
  const Release(this.version, this.name, this.url, this.digest, this.size);

  final String version;
  final String name;
  final Uri url;
  final String digest;
  final int size;
}

Release? selectRelease(
  Map<String, dynamic> data,
  String repository,
  String asset,
  String installedVersion,
) {
  final tag = data['tag_name'];
  if (tag is! String ||
      !isNewer(tag, installedVersion) ||
      data['draft'] == true ||
      data['prerelease'] == true)
    return null;
  final expected =
      'https://github.com/$repository/releases/download/$tag/$asset';
  for (final item in data['assets'] as List<dynamic>? ?? const []) {
    if (item is! Map || item['name'] != asset || item['state'] != 'uploaded')
      continue;
    final url = item['browser_download_url'];
    final digest = item['digest'];
    final size = item['size'];
    if (url is String &&
        url.toLowerCase() == expected.toLowerCase() &&
        digest is String &&
        RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) &&
        size is int &&
        size > 0 &&
        size <= maximumPackageBytes) {
      return Release(
        tag,
        asset,
        Uri.parse(url),
        digest.substring(7).toLowerCase(),
        size,
      );
    }
  }
  throw LocalizedFailure((messages) => messages.noReleaseAsset(tag));
}

class Updater {
  static String? get asset => Platform.isAndroid
      ? 'BigEvil-Launcher-android.apk'
      : switch (Abi.current()) {
          Abi.windowsX64 => 'BigEvil-Launcher-windows-x64.exe',
          Abi.linuxX64 => 'BigEvil-Launcher-linux-x64.deb',
          _ => null,
        };

  static String resolveRepository(String value) =>
      value.isEmpty ? defaultRepository : value;

  static Future<File> _settings() async =>
      File('${(await getApplicationSupportDirectory()).path}/repository.txt');

  static Future<String> repository() async {
    final file = await _settings();
    final saved = await file.exists() ? (await file.readAsString()).trim() : '';
    return resolveRepository(saved);
  }

  static Future<void> saveRepository(String value) async {
    final file = await _settings();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'BigEvil-Launcher/$currentVersion';

  static Future<Release?> check(String repository) async {
    final package = asset;
    if (package == null || !repositoryPattern.hasMatch(repository)) return null;
    final client = _client();
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
      );
      request.followRedirects = false;
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 404) {
        throw LocalizedFailure((messages) => messages.repoNotFound);
      }
      if (response.statusCode != 200) {
        throw LocalizedFailure(
          (messages) => messages.githubHttpError(response.statusCode),
        );
      }
      final body = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        body.add(chunk);
        if (body.length > 2 * 1024 * 1024)
          throw LocalizedFailure((messages) => messages.githubResponseLimit);
      }
      return selectRelease(
        jsonDecode(utf8.decode(body.takeBytes())) as Map<String, dynamic>,
        repository,
        package,
        currentVersion,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<File> download(
    Release release,
    void Function(double) progress,
  ) async {
    final cache = await getApplicationCacheDirectory();
    final directory = Directory('${cache.path}/updates/${release.version}');
    await directory.create(recursive: true);
    final output = File('${directory.path}/${release.name}');
    if (await output.exists() &&
        await output.length() == release.size &&
        (await sha256.bind(output.openRead()).first).toString() ==
            release.digest) {
      progress(1);
      return output;
    }
    final staging = await directory.createTemp('.download-');
    final partial = File('${staging.path}/package');
    final client = _client();
    try {
      var url = release.url;
      HttpClientResponse? response;
      for (var i = 0; i < 5; i++) {
        final request = await client.getUrl(url);
        request.followRedirects = false;
        final result = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if (result.statusCode == 200) {
          response = result;
          break;
        }
        final location = result.headers.value(HttpHeaders.locationHeader);
        if (![301, 302, 303, 307, 308].contains(result.statusCode) ||
            location == null) {
          throw LocalizedFailure(
            (messages) => messages.downloadHttpError(result.statusCode),
          );
        }
        await result.drain<void>().timeout(const Duration(seconds: 10));
        url = url.resolve(location);
        if (url.scheme != 'https' ||
            url.userInfo.isNotEmpty ||
            (url.host != 'github.com' &&
                !url.host.endsWith('.githubusercontent.com'))) {
          throw LocalizedFailure((messages) => messages.invalidRedirect);
        }
      }
      if (response == null)
        throw LocalizedFailure((messages) => messages.redirectLimit);
      var received = 0;
      final stopwatch = Stopwatch()..start();
      final writer = await partial.open(mode: FileMode.write);
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > release.size)
            throw LocalizedFailure((messages) => messages.invalidPackageSize);
          await writer.writeFrom(chunk);
          if (stopwatch.elapsedMilliseconds >= 100) {
            progress(received / release.size);
            stopwatch.reset();
          }
        }
      } finally {
        await writer.close();
      }
      if (received != release.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              release.digest) {
        throw LocalizedFailure((messages) => messages.invalidChecksum);
      }
      progress(1);
      return await partial.rename(output.path);
    } finally {
      client.close(force: true);
      await staging.delete(recursive: true);
    }
  }

  static Future<void> install(File file) async {
    if (Platform.isAndroid) {
      await Library.android.invokeMethod<void>('install', file.path);
    } else if (Platform.isWindows) {
      await Process.start(file.path, [], mode: ProcessStartMode.detached);
      exit(0);
    } else if (!await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    )) {
      throw LocalizedFailure(
        (messages) => messages.openLinuxPackage(file.path),
      );
    }
  }
}
