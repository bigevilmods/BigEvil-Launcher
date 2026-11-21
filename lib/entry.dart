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
  }) : searchKey = '$name $target $developer'.toLowerCase();

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
  final String searchKey;

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    json['name'] as String,
    json['target'] as String,
    Kind.values.byName(json['kind'] as String),
    coverPath: json['coverPath'] as String?,
    backgroundPath: json['backgroundPath'] as String?,
    description: json['description'] as String? ?? '',
    developer: json['developer'] as String? ?? '',
    repositoryUrl: json['repositoryUrl'] as String? ?? '',
    downloadUrl: json['downloadUrl'] as String? ?? '',
    onlineUrl: json['onlineUrl'] as String? ?? '',
  );

  Map<String, String> toJson() => {
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
  };
}

Iterable<Entry> filterEntries(
  Iterable<Entry> entries,
  String text,
  Kind? kind,
) {
  final query = text.trim().toLowerCase();
  return entries.where(
    (entry) =>
        (kind == null || entry.kind == kind) && entry.searchKey.contains(query),
  );
}
