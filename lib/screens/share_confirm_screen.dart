import 'package:flutter/material.dart';

import '../models/shared_fit_draft.dart';
import '../models/shared_fit_event.dart';
import '../services/fit_upload_coordinator.dart';
import '../services/share_navigation_coordinator.dart';
import '../services/shared_fit_upload_service.dart';

enum _ShareConfirmState {
  preflight,
  preflightFailure,
  confirm,
  uploading,
  missingConfiguration,
  invalidFile,
  failure,
  partialSuccess,
  success,
  error,
}

class ShareConfirmScreen extends StatefulWidget {
  const ShareConfirmScreen({
    super.key,
    required this.event,
    required this.uploadService,
    required this.uploadActivity,
    this.successFeedbackDuration = const Duration(milliseconds: 1200),
    this.onOpenSettings,
    this.onDismissToHome,
  });

  final SharedFitEvent event;
  final SharedFitUploadService uploadService;
  final ShareFlowUploadActivity uploadActivity;
  final Duration successFeedbackDuration;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onDismissToHome;

  @override
  State<ShareConfirmScreen> createState() => _ShareConfirmScreenState();
}

class _ShareConfirmScreenState extends State<ShareConfirmScreen> {
  late _ShareConfirmState _state;
  String? _message;
  String _targetLabel = '';

  SharedFitDraft? get _draft => widget.event.draft;

  @override
  void initState() {
    super.initState();
    if (widget.event.type == SharedFitEventType.error) {
      _state = _ShareConfirmState.error;
      _message = widget.event.message;
      return;
    }

    _state = _ShareConfirmState.preflight;
    _loadUploadPlan();
  }

  Future<void> _loadUploadPlan() async {
    try {
      final FitUploadPlan plan = await widget.uploadService.loadUploadPlan();
      if (!mounted) {
        return;
      }

      setState(() {
        _targetLabel = plan.targetLabel.trim();
        _state = plan.hasMissingConfiguration
            ? _ShareConfirmState.missingConfiguration
            : _ShareConfirmState.confirm;
      });
    } on Exception {
      if (!mounted) {
        return;
      }

      setState(() {
        _state = _ShareConfirmState.preflightFailure;
        _message = '无法读取上传目标配置，请返回首页后重试。';
      });
    }
  }

  Future<void> _upload() async {
    final SharedFitDraft? draft = _draft;
    if (draft == null) {
      return;
    }

    setState(() {
      _state = _ShareConfirmState.uploading;
      _message = null;
    });
    widget.uploadActivity.startUpload();

    try {
      final SharedFitUploadResult result = await widget.uploadService
          .uploadDraft(draft);
      if (!mounted) {
        return;
      }

      switch (result.status) {
        case SharedFitUploadStatus.missingConfiguration:
          setState(() => _state = _ShareConfirmState.missingConfiguration);
          return;
        case SharedFitUploadStatus.invalidFile:
          setState(() => _state = _ShareConfirmState.invalidFile);
          return;
        case SharedFitUploadStatus.success:
          setState(() {
            _state = _ShareConfirmState.success;
            _message = result.message;
          });
          await Future<void>.delayed(widget.successFeedbackDuration);
          if (!mounted) {
            return;
          }
          widget.onDismissToHome?.call();
          return;
        case SharedFitUploadStatus.partialSuccess:
          setState(() {
            _state = _ShareConfirmState.partialSuccess;
            _message = result.message;
          });
          await Future<void>.delayed(widget.successFeedbackDuration);
          if (!mounted) {
            return;
          }
          widget.onDismissToHome?.call();
          return;
        case SharedFitUploadStatus.failure:
          setState(() {
            _state = _ShareConfirmState.failure;
            _message = result.message ?? '上传失败';
          });
          return;
      }
    } finally {
      widget.uploadActivity.finishUpload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SharedFitDraft? draft = _draft;
    final String displayName = draft?.displayName ?? 'shared.fit';

    return Scaffold(
      appBar: AppBar(title: const Text('共享 FIT 文件')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _title(displayName),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _description(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_state == _ShareConfirmState.preflight ||
                    _state == _ShareConfirmState.uploading) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
                const SizedBox(height: 24),
                ..._buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case _ShareConfirmState.preflight:
        return const <Widget>[Text('正在检查上传目标...', textAlign: TextAlign.center)];
      case _ShareConfirmState.preflightFailure:
        return <Widget>[
          TextButton(
            onPressed: widget.onDismissToHome,
            child: const Text('返回首页'),
          ),
        ];
      case _ShareConfirmState.confirm:
        return <Widget>[
          ElevatedButton(onPressed: _upload, child: Text(_confirmButtonText())),
        ];
      case _ShareConfirmState.uploading:
        return const <Widget>[Text('上传中...', textAlign: TextAlign.center)];
      case _ShareConfirmState.missingConfiguration:
        return <Widget>[
          ElevatedButton(
            onPressed: widget.onOpenSettings,
            child: const Text('去设置'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onDismissToHome,
            child: const Text('返回首页'),
          ),
        ];
      case _ShareConfirmState.invalidFile:
      case _ShareConfirmState.error:
      case _ShareConfirmState.partialSuccess:
      case _ShareConfirmState.success:
        return <Widget>[
          TextButton(
            onPressed: widget.onDismissToHome,
            child: const Text('返回首页'),
          ),
        ];
      case _ShareConfirmState.failure:
        return <Widget>[
          ElevatedButton(onPressed: _upload, child: const Text('重新上传')),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onDismissToHome,
            child: const Text('返回首页'),
          ),
        ];
    }
  }

  String _title(String displayName) {
    switch (_state) {
      case _ShareConfirmState.preflight:
      case _ShareConfirmState.preflightFailure:
      case _ShareConfirmState.confirm:
      case _ShareConfirmState.uploading:
      case _ShareConfirmState.missingConfiguration:
        return displayName;
      case _ShareConfirmState.failure:
        return '上传失败';
      case _ShareConfirmState.invalidFile:
        return '文件无效';
      case _ShareConfirmState.partialSuccess:
        return '部分成功';
      case _ShareConfirmState.success:
        return '上传成功';
      case _ShareConfirmState.error:
        return '共享失败';
    }
  }

  String _description() {
    switch (_state) {
      case _ShareConfirmState.preflight:
        return '正在检查上传目标和配置，请稍候。';
      case _ShareConfirmState.preflightFailure:
        return _message ?? '无法读取上传目标配置，请返回首页后重试。';
      case _ShareConfirmState.confirm:
        return '确认将这个 FIT 文件${_uploadTargetPhrase()}。';
      case _ShareConfirmState.uploading:
        return '正在上传共享的 FIT 文件，请稍候。';
      case _ShareConfirmState.missingConfiguration:
        return '缺少 ${_targetDescription()} 必需配置，请先前往设置完成授权。';
      case _ShareConfirmState.invalidFile:
        return '这个共享文件不是可上传的 FIT 文件。';
      case _ShareConfirmState.failure:
        return _message ?? '上传失败，请重试。';
      case _ShareConfirmState.partialSuccess:
        return _message ?? 'FIT 文件已上传，部分目标同步失败。';
      case _ShareConfirmState.success:
        return _message ?? 'FIT 文件已经上传到 $_targetLabel。';
      case _ShareConfirmState.error:
        return _message ?? '无法读取共享的 FIT 文件。';
    }
  }

  String _confirmButtonText() {
    return _uploadActionLabel();
  }

  String _uploadTargetPhrase() {
    if (_targetLabel.isEmpty) {
      return '上传';
    }

    return _targetLabel == '行者' ? '上传到行者' : '上传到 $_targetLabel';
  }

  String _uploadActionLabel() {
    return _targetLabel.isEmpty ? '上传' : _uploadTargetPhrase();
  }

  String _targetDescription() {
    return _targetLabel.isEmpty ? '上传目标' : _targetLabel;
  }
}
