import 'dart:ffi' show Abi;

import 'updates.dart';

typedef ItemVersion = ({String tag, DateTime? publishedAt, String? revision});
typedef ItemPackage = ({
  String name,
  Uri url,
  int size,
  String? digest,
  ItemVersion version,
});

bool isNewerItemVersion(ItemVersion candidate, ItemVersion installed) {
  if (candidate.tag == installed.tag) {
    return candidate.revision != null &&
        installed.revision != null &&
        candidate.revision != installed.revision;
  }
  if (versionPattern.hasMatch(candidate.tag) &&
      versionPattern.hasMatch(installed.tag)) {
    return isNewer(candidate.tag, installed.tag);
  }
  final published = candidate.publishedAt;
  final previous = installed.publishedAt;
  return published != null && previous != null && published.isAfter(previous);
}

ItemPackage? selectItemPackage(
  Map<String, dynamic> release,
  String repository,
  Abi abi,
) {
  final tag = release['tag_name'];
  final assets = release['assets'];
  if (tag is! String ||
      tag.isEmpty ||
      assets is! List ||
      release['draft'] == true ||
      release['prerelease'] == true) {
    return null;
  }
  ItemPackage? selected;
  var bestScore = 0;
  for (final asset in assets) {
    if (asset is! Map || asset['state'] != 'uploaded') continue;
    final name = asset['name'];
    final size = asset['size'];
    if (name is! String ||
        !Updater.isDownloadName(name) ||
        size is! int ||
        size <= 0 ||
        size > maximumItemBytes) {
      continue;
    }
    final address = asset['browser_download_url'];
    final url = address is String ? Uri.tryParse(address) : null;
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        url.hasQuery ||
        url.hasFragment) {
      continue;
    }
    final parts = url.pathSegments;
    if (parts.take(2).join('/').toLowerCase() != repository.toLowerCase() ||
        parts.skip(2).join('/') != 'releases/download/$tag/$name')
      continue;
    final digest = asset['digest'];
    if (digest != null &&
        (digest is! String ||
            !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest))) {
      continue;
    }
    final score = _packageScore(name.toLowerCase(), abi);
    if (score <= bestScore) continue;
    bestScore = score;
    final published = release['published_at'];
    final id = asset['id'];
    selected = (
      name: name,
      url: url,
      size: size,
      digest: digest is String ? digest.substring(7).toLowerCase() : null,
      version: (
        tag: tag,
        publishedAt: published is String ? DateTime.tryParse(published) : null,
        revision: digest is String
            ? digest.toLowerCase()
            : id is int
            ? id.toString()
            : null,
      ),
    );
  }
  return selected;
}

int _packageScore(String name, Abi abi) {
  bool token(String pattern) => RegExp(
    r'(?:^|[^a-z0-9])'
    '(?:$pattern)'
    r'(?=[^a-z0-9]|$)',
  ).hasMatch(name);
  if (token('source|src|symbols|debug')) return 0;
  final namedArchitecture = switch (abi) {
    Abi.androidArm || Abi.linuxArm => 'armeabi-v7a|armv7l?|armhf|arm',
    Abi.androidArm64 ||
    Abi.linuxArm64 ||
    Abi.windowsArm64 => 'arm64-v8a|arm64|aarch64',
    Abi.windowsIA32 => 'win32|x86|ia32|i[3-6]86',
    Abi.androidIA32 || Abi.linuxIA32 => 'x86|ia32|i[3-6]86',
    Abi.windowsX64 => 'win64|x86[-_]64|x64|amd64',
    Abi.androidX64 || Abi.linuxX64 => 'x86[-_]64|x64|amd64',
    _ => null,
  };
  if (namedArchitecture == null) return 0;
  final architectureMatches = token(namedArchitecture);
  if (!architectureMatches &&
      token(
        'armeabi-v7a|armv7l?|armhf|arm|arm64-v8a|arm64|aarch64|'
        'win32|win64|x86[-_]64|x64|amd64|x86|ia32|i[3-6]86|riscv64|ppc64le|s390x',
      )) {
    return 0;
  }
  // The x86 token also occurs at the start of x86_64. Likewise, arm can
  // occur in an incompatible name that contains another architecture token.
  if ((abi == Abi.androidIA32 ||
          abi == Abi.linuxIA32 ||
          abi == Abi.windowsIA32) &&
      token('x86[-_]64|x64|amd64|win64'))
    return 0;
  final architectureScore = architectureMatches ? 2 : 1;
  if (abi == Abi.androidArm ||
      abi == Abi.androidArm64 ||
      abi == Abi.androidIA32 ||
      abi == Abi.androidX64) {
    if (name.endsWith('.apk')) return 30 + architectureScore;
    return token('android') && name.endsWith('.zip')
        ? 10 + architectureScore
        : 0;
  }
  if (abi == Abi.windowsArm64 ||
      abi == Abi.windowsIA32 ||
      abi == Abi.windowsX64) {
    if (token('linux|android|darwin|macos|osx')) return 0;
    if (name.endsWith('.msi')) return 30 + architectureScore;
    if (name.endsWith('.exe')) return 20 + architectureScore;
    if (token('windows|win|win32|win64') &&
        RegExp(r'\.(zip|rar)$').hasMatch(name)) {
      return 10 + architectureScore;
    }
    return 0;
  }
  if (token('windows|win|android|darwin|macos|osx')) return 0;
  if (name.endsWith('.deb')) return 40 + architectureScore;
  if (name.endsWith('.appimage')) return 30 + architectureScore;
  if (name.endsWith('.rpm')) return 20 + architectureScore;
  if (token('linux') &&
      RegExp(r'\.(tar\.(gz|xz|bz2|zst)|tgz|zip|rar)$').hasMatch(name)) {
    return 10 + architectureScore;
  }
  return 0;
}
