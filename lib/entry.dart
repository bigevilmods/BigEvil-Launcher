enum Kind { game, app }

class Entry {
  Entry(
    this.name,
    this.target,
    this.kind, {
    this.coverPath,
    this.backgroundPath,
    this.description = '',
    this.developer = '',
    this.repositoryUrl = '',
    this.downloadUrl = '',
    this.onlineUrl = '',
    this.androidPackage = '',
    this.windowsUninstallKey = '',
    this.linuxPackage = '',
    this.executable = '',
    Iterable<String> platforms = const [],
  }) : platforms = List.unmodifiable(_platforms(platforms)),
       searchKey = '$name $target $developer'.toLowerCase();

  final String name;
  final String target;
  final Kind kind;
  final String? coverPath;
  final String? backgroundPath;
  final String description;
  final String developer;
  final String repositoryUrl;
  final String downloadUrl;
  final String onlineUrl;
  final String androidPackage;
  final String windowsUninstallKey;
  final String linuxPackage;
  final String executable;
  final List<String> platforms;
  final String searchKey;

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    json['name'] as String,
    json['target'] as String? ?? '',
    Kind.values.byName(json['kind'] as String),
    coverPath: json['coverPath'] as String?,
    backgroundPath: json['backgroundPath'] as String?,
    description: json['description'] as String? ?? '',
    developer: json['developer'] as String? ?? '',
    repositoryUrl: json['repositoryUrl'] as String? ?? '',
    downloadUrl: json['downloadUrl'] as String? ?? '',
    onlineUrl: json['onlineUrl'] as String? ?? '',
    androidPackage: json['androidPackage'] as String? ?? '',
    windowsUninstallKey: json['windowsUninstallKey'] as String? ?? '',
    linuxPackage: json['linuxPackage'] as String? ?? '',
    executable: json['executable'] as String? ?? '',
    platforms: switch (json['plataforma']) {
      final String name => [name],
      final List values => values.whereType<String>(),
      _ => const [],
    },
  );

  static Iterable<String> _platforms(Iterable<String> names) sync* {
    final seen = <String>{};
    for (final name in names) {
      final label = name.trim();
      if (label.isNotEmpty && seen.add(label.toLowerCase())) yield label;
    }
  }

  Map<String, Object> toJson() => {
    'name': name,
    'target': target,
    'kind': kind.name,
    if (coverPath case final path?) 'coverPath': path,
    if (backgroundPath case final path?) 'backgroundPath': path,
    if (description.isNotEmpty) 'description': description,
    if (developer.isNotEmpty) 'developer': developer,
    if (repositoryUrl.isNotEmpty) 'repositoryUrl': repositoryUrl,
    if (downloadUrl.isNotEmpty) 'downloadUrl': downloadUrl,
    if (onlineUrl.isNotEmpty) 'onlineUrl': onlineUrl,
    if (androidPackage.isNotEmpty) 'androidPackage': androidPackage,
    if (windowsUninstallKey.isNotEmpty)
      'windowsUninstallKey': windowsUninstallKey,
    if (linuxPackage.isNotEmpty) 'linuxPackage': linuxPackage,
    if (executable.isNotEmpty) 'executable': executable,
    if (platforms.isNotEmpty) 'plataforma': platforms,
  };
}

Iterable<Entry> filterEntries(
  Iterable<Entry> entries,
  String text,
  Kind? kind, {
  String? platform,
}) {
  final query = text.trim().toLowerCase();
  final platformKey = platform?.toLowerCase();
  return entries.where(
    (entry) =>
        (kind == null || entry.kind == kind) &&
        (platformKey == null ||
            entry.platforms.any((name) => name.toLowerCase() == platformKey)) &&
        (entry.searchKey.contains(query) ||
            entry.platforms.any((name) => name.toLowerCase().contains(query))),
  );
}
