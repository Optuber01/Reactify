class AppAssetManifestEntry {
  const AppAssetManifestEntry({
    required this.originalPath,
    required this.appAssetPath,
    required this.kind,
    required this.family,
    this.aliases = const [],
  });

  final String originalPath;
  final String appAssetPath;
  final String kind;
  final String family;
  final List<String> aliases;
}

class AppAssetManifest {
  AppAssetManifest({required this.generatedOn, required this.entries}) {
    for (final entry in entries.values) {
      _appAssetPaths.add(entry.appAssetPath);
      _appAssetPaths.addAll(entry.aliases);
    }
  }

  final String generatedOn;
  final Map<String, AppAssetManifestEntry> entries;
  final Set<String> _appAssetPaths = {};

  factory AppAssetManifest.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as Map<String, dynamic>;
    return AppAssetManifest(
      generatedOn: json['generated_on'] as String,
      entries: {
        for (final entry in rawEntries.entries)
          entry.key: AppAssetManifestEntry(
            originalPath: entry.key,
            appAssetPath:
                (entry.value as Map<String, dynamic>)['app_asset_path']
                    as String,
            kind: (entry.value as Map<String, dynamic>)['kind'] as String,
            family: (entry.value as Map<String, dynamic>)['family'] as String,
            aliases:
                ((entry.value as Map<String, dynamic>)['aliases']
                        as List<dynamic>?)
                    ?.cast<String>() ??
                const [],
          ),
      },
    );
  }

  AppAssetManifestEntry? operator [](String originalPath) =>
      entries[originalPath];

  bool containsAppAsset(String appAssetPath) {
    return _appAssetPaths.contains(appAssetPath);
  }
}
