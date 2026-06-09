class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion; // "1.0.21"
  final String currentVersion; // "1.0.20"
  final String releaseNotes; // GitHub release body (markdown)
  final String downloadUrl; // https://github.com/.../releases/tag/v1.0.21

  const UpdateInfo({
    required this.hasUpdate,
    this.latestVersion = '',
    this.currentVersion = '',
    this.releaseNotes = '',
    this.downloadUrl = '',
  });

  /// Shorthand for error/silent-skip cases.
  factory UpdateInfo.noUpdate(String current) =>
      UpdateInfo(hasUpdate: false, currentVersion: current);
}
