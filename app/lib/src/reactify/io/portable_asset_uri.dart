class PortableAssetUriPolicy {
  const PortableAssetUriPolicy();

  String makePortable({
    required String projectLocation,
    required String assetLocation,
  }) {
    if (assetLocation.trim().isEmpty || isExternal(assetLocation)) {
      return assetLocation;
    }
    final windows =
        _isWindowsPath(projectLocation) || _isWindowsPath(assetLocation);
    final projectUri = _fileUri(projectLocation, windows);
    final assetUri = _fileUri(assetLocation, windows);
    if (projectUri.scheme != 'file' || assetUri.scheme != 'file') {
      return assetLocation;
    }
    if (projectUri.authority.toLowerCase() !=
        assetUri.authority.toLowerCase()) {
      return assetUri.toString();
    }
    final projectSegments = [...projectUri.pathSegments]..removeLast();
    final assetSegments = assetUri.pathSegments;
    if (windows &&
        projectSegments.isNotEmpty &&
        assetSegments.isNotEmpty &&
        projectSegments.first.toLowerCase() !=
            assetSegments.first.toLowerCase()) {
      return assetUri.toString();
    }
    var common = 0;
    while (common < projectSegments.length &&
        common < assetSegments.length &&
        _sameSegment(projectSegments[common], assetSegments[common], windows)) {
      common += 1;
    }
    final relativeSegments = <String>[
      for (var index = common; index < projectSegments.length; index += 1) '..',
      ...assetSegments.skip(common),
    ];
    if (relativeSegments.isEmpty) {
      return './';
    }
    return Uri(pathSegments: relativeSegments).toString();
  }

  String resolve({required String projectLocation, required String storedUri}) {
    if (storedUri.trim().isEmpty || isExternal(storedUri)) {
      return storedUri;
    }
    final parsed = Uri.tryParse(storedUri);
    final windows = _isWindowsPath(projectLocation);
    if (parsed != null && parsed.scheme == 'file') {
      return parsed.toFilePath(windows: windows);
    }
    if (_isAbsolutePath(storedUri)) {
      return storedUri;
    }
    final projectUri = _fileUri(projectLocation, windows);
    final directory = projectUri.resolve('.');
    return directory.resolve(storedUri).toFilePath(windows: windows);
  }

  bool isExternal(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty || _isWindowsPath(value)) {
      return false;
    }
    return uri.scheme != 'file';
  }

  Uri _fileUri(String value, bool windows) {
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.scheme == 'file') {
      return parsed;
    }
    return Uri.file(value, windows: windows);
  }

  bool _sameSegment(String left, String right, bool windows) {
    return windows ? left.toLowerCase() == right.toLowerCase() : left == right;
  }

  bool _isAbsolutePath(String value) {
    return value.startsWith('/') ||
        value.startsWith('\\\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  bool _isWindowsPath(String value) {
    return value.startsWith('\\\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }
}
