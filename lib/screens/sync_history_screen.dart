import 'package:flutter/material.dart';
import '../models/sync_record.dart';
import '../services/state_store.dart';

class SyncHistoryScreen extends StatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  final _stateStore = StateStore();
  List<SyncRecord> _records = [];
  bool _loading = true;
  String? _error;

  // Filter state
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showStrava = true;
  bool _showXingzhe = true;
  bool _showSuccess = true;
  bool _showFailed = true;
  bool _showDeduped = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _stateStore.loadSyncRecords(
        from: _fromDate,
        to: _toDate?.add(const Duration(days: 1)),
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (picked != null && mounted) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _load();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _load();
  }

  List<SyncRecord> get _filteredRecords {
    return _records.where((record) {
      // Platform filter
      final hasStrava =
          record.uploadedToStrava &&
          record.platformResults.any((r) => r.platform == SyncPlatform.strava);
      final hasXingzhe =
          record.uploadedToXingzhe &&
          record.platformResults.any((r) => r.platform == SyncPlatform.xingzhe);

      if (!_showStrava && hasStrava) return false;
      if (!_showXingzhe && hasXingzhe) return false;

      // Status filter — show record if any matching platform result qualifies
      final matchingResults = record.platformResults.where((r) {
        if (r.platform == SyncPlatform.strava && !record.uploadedToStrava) {
          return false;
        }
        if (r.platform == SyncPlatform.xingzhe && !record.uploadedToXingzhe) {
          return false;
        }
        if (r.status == SyncStatus.success && !_showSuccess) return false;
        if (r.status == SyncStatus.failed && !_showFailed) return false;
        if (r.status == SyncStatus.deduped && !_showDeduped) return false;
        return true;
      }).toList();

      return matchingResults.isNotEmpty;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'clear') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('确认清空'),
                    content: const Text('确定清空所有同步记录？此操作不可恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text(
                          '清空',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _stateStore.clearHistory();
                  _load();
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'clear', child: Text('清空历史记录')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- filter bar ----
          _buildFilterBar(),

          // ---- content ----
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : _filteredRecords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text(
                          '暂无同步记录',
                          style: TextStyle(color: Colors.grey),
                        ),
                        if (_fromDate != null || _toDate != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _clearDateFilter,
                            child: const Text('清除日期筛选'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _filteredRecords.length,
                    itemBuilder: (ctx, idx) =>
                        _buildRecordTile(_filteredRecords[idx]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range row
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _showDateRangePicker,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(
                  _fromDate != null && _toDate != null
                      ? '${_formatDate(_fromDate!)} - ${_formatDate(_toDate!)}'
                      : '选择日期范围',
                ),
              ),
              if (_fromDate != null || _toDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: _clearDateFilter,
                  tooltip: '清除日期',
                ),
              const Spacer(),
              Text(
                '${_filteredRecords.length} 条记录',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Platform filter chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('Strava'),
                selected: _showStrava,
                onSelected: (v) => setState(() => _showStrava = v),
              ),
              FilterChip(
                label: const Text('行者'),
                selected: _showXingzhe,
                onSelected: (v) => setState(() => _showXingzhe = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('成功'),
                selected: _showSuccess,
                selectedColor: Colors.green[100],
                onSelected: (v) => setState(() => _showSuccess = v),
              ),
              FilterChip(
                label: const Text('失败'),
                selected: _showFailed,
                selectedColor: Colors.red[100],
                onSelected: (v) => setState(() => _showFailed = v),
              ),
              FilterChip(
                label: const Text('已同步'),
                selected: _showDeduped,
                selectedColor: Colors.orange[100],
                onSelected: (v) => setState(() => _showDeduped = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(SyncRecord record) {
    // Determine overall sync status for the record
    final hasSuccess = record.platformResults.any(
      (r) => r.status == SyncStatus.success,
    );
    final hasFailed = record.platformResults.any(
      (r) => r.status == SyncStatus.failed,
    );
    final Color rowColor;
    if (hasFailed) {
      rowColor = Colors.red.shade50;
    } else if (hasSuccess) {
      rowColor = Colors.green.shade50;
    } else {
      rowColor = Colors.orange.shade50;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: rowColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: date · distance · ascent
            Row(
              children: [
                // Date badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.displayDate,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Distance
                if (record.distanceM != null) ...[
                  Icon(Icons.straighten, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 3),
                  Text(
                    record.displayDistance,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                // Ascent
                if (record.ascentM != null) ...[
                  Icon(Icons.trending_up, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 3),
                  Text(
                    record.displayAscent,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const Spacer(),
                // Source filename
                Expanded(
                  flex: 2,
                  child: Text(
                    record.sourceFilename,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Platform sync results row
            Row(
              children: record.platformResults.map((result) {
                final isStrava = result.platform == SyncPlatform.strava;
                final platformLabel = isStrava ? 'Strava' : '行者';
                final platformColor = isStrava ? Colors.orange : Colors.teal;
                final statusColor = _statusColor(result.status);
                final statusLabel = _statusLabel(result.status);
                final isSuccess = result.status == SyncStatus.success;
                final isFailed = result.status == SyncStatus.failed;

                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: isStrava ? 8 : 0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha((0.12 * 255).round()),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusColor.withAlpha((0.3 * 255).round()),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              platformLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: platformColor.shade700,
                              ),
                            ),
                            const Spacer(),
                            // Status icon
                            if (isSuccess)
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              )
                            else if (isFailed)
                              const Icon(
                                Icons.error,
                                size: 14,
                                color: Colors.red,
                              )
                            else if (result.status == SyncStatus.deduped)
                              Icon(
                                Icons.sync,
                                size: 14,
                                color: Colors.orange.shade600,
                              )
                            else
                              const Icon(
                                Icons.schedule,
                                size: 14,
                                color: Colors.grey,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                        if (result.remoteActivityId != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            '#${result.remoteActivityId}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                        if (result.errorMessage != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            result.errorMessage!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(SyncStatus status) {
    switch (status) {
      case SyncStatus.success:
        return '成功';
      case SyncStatus.failed:
        return '失败';
      case SyncStatus.deduped:
        return '已同步';
      case SyncStatus.pending:
        return '待处理';
    }
  }

  Color _statusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
      case SyncStatus.deduped:
        return Colors.orange;
      case SyncStatus.pending:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
