class AppConfig {
  static const int currentVersion = 1;

  final int version;
  final String appVersion;
  final String exportedAt;
  final Map<String, dynamic> settings;

  const AppConfig({
    required this.version,
    required this.appVersion,
    required this.exportedAt,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'appVersion': appVersion,
    'exportedAt': exportedAt,
    'settings': settings,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('配置文件格式无效：缺少版本信息');
    }
    if (version != currentVersion) {
      throw FormatException('配置文件版本 $version 不受支持');
    }

    return AppConfig(
      version: version,
      appVersion: json['appVersion'] as String? ?? '',
      exportedAt: json['exportedAt'] as String? ?? '',
      settings: Map<String, dynamic>.from(json['settings'] as Map? ?? {}),
    );
  }
}
