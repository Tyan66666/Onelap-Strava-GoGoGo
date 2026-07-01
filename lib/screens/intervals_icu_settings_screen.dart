import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class IntervalsIcuSettingsScreen extends StatefulWidget {
  const IntervalsIcuSettingsScreen({super.key, this.settingsService});

  final SettingsService? settingsService;

  @override
  State<IntervalsIcuSettingsScreen> createState() =>
      _IntervalsIcuSettingsScreenState();
}

class _IntervalsIcuSettingsScreenState
    extends State<IntervalsIcuSettingsScreen> {
  late final SettingsService _settingsService;
  final _athleteIdController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _settingsService = widget.settingsService ?? SettingsService();
    _load();
  }

  Future<void> _load() async {
    final values = await _settingsService.loadSettings();
    if (!mounted) {
      return;
    }
    _athleteIdController.text =
        values[SettingsService.keyIntervalsIcuAthleteId] ?? '';
    _apiKeyController.text =
        values[SettingsService.keyIntervalsIcuApiKey] ?? '';
    setState(() {
      _loading = false;
    });
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _save() async {
    _dismissKeyboard();

    final athleteId = _athleteIdController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (athleteId.isEmpty || apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写 Athlete ID 和 API Key')),
        );
      }
      return;
    }

    try {
      await _settingsService.saveSettings({
        SettingsService.keyIntervalsIcuAthleteId: athleteId,
        SettingsService.keyIntervalsIcuApiKey: apiKey,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Intervals.icu 设置已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
      }
    }
  }

  @override
  void dispose() {
    _athleteIdController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Intervals.icu 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _athleteIdController,
            decoration: const InputDecoration(
              labelText: 'Athlete ID',
              hintText: 'i12345',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '在 Intervals.icu 设置 > Developer 中生成 API Key',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _save,
            child: const Text('保存 Intervals.icu 设置'),
          ),
        ],
      ),
    );
  }
}
