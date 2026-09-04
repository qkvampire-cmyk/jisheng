import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/poker_record.dart';
import '../models/record_segment.dart';
import '../models/time_range.dart';
import '../providers/poker_provider.dart';
import '../providers/table_timer_provider.dart';
import '../theme/app_colors.dart';
import 'record_edit_page.dart';

class RecordListPage extends StatefulWidget {
  const RecordListPage({super.key});

  @override
  State<RecordListPage> createState() => _RecordListPageState();
}

class _RecordListPageState extends State<RecordListPage> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;

  @override
  void dispose() {
    _scrollController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PokerProvider>();
    final segments = provider.segments;

    return Column(
      children: [
        _buildFilterBar(context, provider),
        const _TableTimerBar(),
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : segments.isEmpty
                  ? _buildEmptyState()
                  : _buildList(provider, segments),
        ),
        if (segments.isNotEmpty)
          _buildBottomSummary(provider, _allRecords(segments)),
      ],
    );
  }

  List<PokerRecord> _allRecords(List<RecordSegment> segments) =>
      [for (final s in segments) ...s.records];

  /// 按行程段构建列表：段内记录卡片 + 段内加线间隙 + 段尾分界线
  Widget _buildList(PokerProvider provider, List<RecordSegment> segments) {
    final children = <Widget>[];
    // 列表最顶部：未封顶 → 终止线加号；已封顶 → 终止条（新记录将自动开新行程）
    if (provider.tripEnded) {
      children.add(_TripEndedBar(
        onCancel: () => provider.clearTripEnded(),
      ));
    } else {
      children.add(_InsertGap(
        record: segments.first.records.first,
        onInsert: () => provider.markTripEnded(),
      ));
    }
    for (var s = 0; s < segments.length; s++) {
      final seg = segments[s];
      final recs = seg.records;
      for (var i = 0; i < recs.length; i++) {
        children.add(_DragTargetCard(
          record: recs[i],
          onBreakDropped: (anchor, target, above) =>
              provider.moveBreak(anchor, target, above),
        ));
        if (i < recs.length - 1) {
          children.add(_InsertGap(
            record: recs[i],
            onInsert: () => provider.insertBreakAt(recs[i]),
          ));
        }
      }
      // 段尾分界线（描述本段）；最后一段的尾线为纯展示条，不可拖
      final isLast = s == segments.length - 1;
      final lineAnchorId = isLast ? null : segments[s + 1].records.first.id;
      children.add(_BreakBar(
        segment: seg,
        lineAnchorId: lineAnchorId,
        onDelete: isLast
            ? null
            : () => _confirmDeleteBreak(context, provider, lineAnchorId!, seg),
        onDragUpdate: _handleDragUpdate,
        onDragStopped: _stopAutoScroll,
      ));
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: children,
    );
  }

  // ========== 拖拽自动滚动 ==========

  void _handleDragUpdate(DragUpdateDetails d) {
    final dy = d.globalPosition.dy;
    final h = MediaQuery.of(context).size.height;
    if (dy < 120) {
      _startAutoScroll(-10);
    } else if (dy > h - 120) {
      _startAutoScroll(10);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(int delta) {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final c = _scrollController;
      if (!c.hasClients) return;
      final next = c.offset + delta;
      if (next <= 0) {
        c.jumpTo(0);
        _stopAutoScroll();
      } else if (next >= c.position.maxScrollExtent) {
        c.jumpTo(c.position.maxScrollExtent);
        _stopAutoScroll();
      } else {
        c.jumpTo(next);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  /// 行程多选弹窗（-1 = 未分组），确认后应用 trip 过滤
  Future<void> _pickTrips(BuildContext context, List<int>? current) async {
    final provider = context.read<PokerProvider>();
    final segs = provider.allSegments;
    if (segs.isEmpty) return;
    final selected = <int>{...?current};

    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('选择行程'),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final seg in segs)
                    CheckboxListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        seg.isUngrouped ? '未分组' : '行程 ${seg.tripNo}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${DateFormat('M/d').format(seg.start)}–${DateFormat('M/d').format(seg.end)} · ${seg.days}天 · ${seg.netHKD >= 0 ? '+' : ''}${seg.netHKD.abs().toStringAsFixed(0)} HKD',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                      value: selected.contains(seg.tripId ?? -1),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          selected.add(seg.tripId ?? -1);
                        } else {
                          selected.remove(seg.tripId ?? -1);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, selected.toList()),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && context.mounted) {
      await provider.setTimeRange(
        TimeRangeSelection(type: TimeRangeType.trip, tripIds: result),
      );
    }
  }

  Future<void> _confirmDeleteBreak(BuildContext context, PokerProvider provider,
      int lineAnchorId, RecordSegment seg) async {
    final label = seg.isUngrouped ? '未分组' : '行程 ${seg.tripNo}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分界？'),
        content: Text('删除后，下方相邻记录段将并入「$label」，合并为一个行程'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('合并'),
          ),
        ],
      ),
    );
    if (ok == true) await provider.deleteBreak(lineAnchorId);
  }

  Widget _buildFilterBar(BuildContext context, PokerProvider provider) {
    final range = provider.timeRange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(color: AppColors.surfaceTint),
      child: Row(
        children: [
          const Text('时间范围：', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: range.type.name,
              isDense: true,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('全部数据')),
                DropdownMenuItem(value: 'thisMonth', child: Text('本月')),
                DropdownMenuItem(value: 'thisYear', child: Text('今年')),
                DropdownMenuItem(value: 'last7Days', child: Text('近7天')),
                DropdownMenuItem(value: 'last30Days', child: Text('近30天')),
                DropdownMenuItem(value: 'custom', child: Text('自定义')),
                DropdownMenuItem(value: 'trip', child: Text('按行程')),
              ],
              onChanged: (v) async {
                if (v == 'custom') {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: (range.type == TimeRangeType.custom &&
                            range.customStart != null &&
                            range.customEnd != null)
                        ? DateTimeRange(
                            start: range.customStart!, end: range.customEnd!)
                        : null,
                  );
                  if (picked != null && context.mounted) {
                    context.read<PokerProvider>().setTimeRange(
                          TimeRangeSelection(
                            type: TimeRangeType.custom,
                            customStart: picked.start,
                            customEnd: picked.end,
                          ),
                        );
                  }
                  return;
                }
                if (v == 'trip') {
                  if (context.mounted) {
                    await _pickTrips(context, range.tripIds);
                  }
                  return;
                }
                if (context.mounted) {
                  final type =
                      TimeRangeType.values.firstWhere((t) => t.name == v!);
                  context.read<PokerProvider>().setTimeRange(
                        TimeRangeSelection(type: type),
                      );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64, color: AppColors.emptyIcon),
          const SizedBox(height: 16),
          Text('暂无记账记录',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          Text('点击右下角 + 号添加第一条记录',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBottomSummary(
      PokerProvider provider, List<PokerRecord> records) {
    final sessions = provider.totalSessions(records);
    final netHKD = provider.totalNetProfitHKD(records);
    final netCNY = provider.totalNetProfitCNY(records);
    final hkdColor = netHKD >= 0 ? AppColors.win : AppColors.loss;
    final cnyColor = netCNY >= 0 ? AppColors.win : AppColors.loss;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text('本区间 $sessions 场',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${netHKD >= 0 ? '+' : ''}${netHKD.toStringAsFixed(0)} HKD',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hkdColor,
                    fontFeatures: AppColors.tabular),
              ),
              const SizedBox(height: 2),
              Text(
                '${netCNY >= 0 ? '+' : ''}${netCNY.toStringAsFixed(0)} CNY',
                style: TextStyle(
                    fontSize: 12,
                    color: cnyColor,
                    fontFeatures: AppColors.tabular),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 插入位置高亮指示线（拖拽悬停时显示在卡片上/下边缘）
class _InsertIndicator extends StatelessWidget {
  const _InsertIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.seed,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// 账单卡片 — 点击进编辑页；同时作为行程分界线拖拽落点（悬停高亮插入位置）
class _DragTargetCard extends StatefulWidget {
  final PokerRecord record;
  final void Function(int lineAnchorId, PokerRecord target, bool above)
      onBreakDropped;

  const _DragTargetCard({required this.record, required this.onBreakDropped});

  @override
  State<_DragTargetCard> createState() => _DragTargetCardState();
}

class _DragTargetCardState extends State<_DragTargetCard> {
  final GlobalKey _cardKey = GlobalKey();
  bool _hoverUp = false;
  bool _hoverDown = false;

  /// 指针在卡片上半 → 线插到卡片上方（above=true）
  bool _isAbove(Offset globalPos) {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return true;
    final centerY = box.localToGlobal(Offset(0, box.size.height / 2)).dy;
    return globalPos.dy < centerY;
  }

  void _setHover(Offset globalPos) {
    final above = _isAbove(globalPos);
    if (above != _hoverUp || !above != _hoverDown) {
      setState(() {
        _hoverUp = above;
        _hoverDown = !above;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final provider = context.read<PokerProvider>();
    final rate = provider.exchangeRate;
    final isProfit = record.isProfit;
    final color = isProfit ? AppColors.win : AppColors.loss;
    final hkdAmount = record.getAmountIn('HKD', rate);
    final cnyAmount = record.displayCny(rate);

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) {
        _setHover(d.offset);
        return true;
      },
      onMove: (d) => _setHover(d.offset),
      onLeave: (_) {
        if (_hoverUp || _hoverDown) {
          setState(() {
            _hoverUp = false;
            _hoverDown = false;
          });
        }
      },
      onAcceptWithDetails: (d) {
        final above = _isAbove(d.offset);
        setState(() {
          _hoverUp = false;
          _hoverDown = false;
        });
        widget.onBreakDropped(d.data, record, above);
      },
      builder: (context, candidates, _) {
        final dragging = candidates.isNotEmpty;
        return Column(
          children: [
            if (dragging && _hoverUp) const _InsertIndicator(),
            Card(
              key: _cardKey,
              elevation: 1,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecordEditPage(existingRecord: record),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${DateFormat('yyyy-MM-dd HH:mm').format(record.recordTime)} · ${record.duration.toStringAsFixed(1)}h',
                              style: TextStyle(
                                  fontSize: 14, color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${record.location} · ${record.blindLevel}',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isProfit ? '+' : '-'}${hkdAmount.abs().toStringAsFixed(0)} HKD',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: color,
                              fontFeatures: AppColors.tabular,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${isProfit ? '+' : '-'}${cnyAmount.abs().toStringAsFixed(0)} CNY',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontFeatures: AppColors.tabular),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (dragging && _hoverDown) const _InsertIndicator(),
          ],
        );
      },
    );
  }
}

/// 顶部终止条：行程已封顶，新记录将自动开启新行程；× 取消封顶
class _TripEndedBar extends StatelessWidget {
  final VoidCallback onCancel;
  const _TripEndedBar({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 13, color: AppColors.seed),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '行程已结束 · 新记录将开启新行程',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.seed),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 13, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// 段内加线间隙：右侧小 + 按钮，点击 = 在该记录下方插入行程终止线
class _InsertGap extends StatelessWidget {
  final PokerRecord record;
  final VoidCallback onInsert;

  const _InsertGap({required this.record, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          onTap: onInsert,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 24,
            height: 12,
            alignment: Alignment.center,
            child: Icon(Icons.add,
                size: 12, color: AppColors.textMuted.withValues(alpha: 0.55)),
          ),
        ),
      ),
    );
  }
}

/// 行程分界线：通栏窄条，左侧行程信息 + 右侧小计盈亏
/// 长按拖动可调整边界位置；右侧 × 删除分界（合并行程）
class _BreakBar extends StatelessWidget {
  final RecordSegment segment;
  final int? lineAnchorId; // null = 底部纯展示条（不可拖/不可删）
  final VoidCallback? onDelete;
  final void Function(DragUpdateDetails details)? onDragUpdate;
  final VoidCallback? onDragStopped;

  const _BreakBar({
    required this.segment,
    this.lineAnchorId,
    this.onDelete,
    this.onDragUpdate,
    this.onDragStopped,
  });

  Widget _buildContent({bool floating = false}) {
    final seg = segment;
    final label = seg.isUngrouped ? '未分组' : '行程 ${seg.tripNo}';
    final dateRange =
        '${DateFormat('M/d').format(seg.start)}–${DateFormat('M/d').format(seg.end)}';
    final net = seg.netHKD;
    final netColor = net >= 0 ? AppColors.win : AppColors.loss;
    final isUngrouped = seg.isUngrouped;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isUngrouped ? AppColors.surfaceTint : AppColors.chipOuter,
        borderRadius: BorderRadius.circular(6),
        boxShadow: floating
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(
            lineAnchorId == null ? Icons.more_horiz : Icons.drag_indicator,
            size: 14,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$label · $dateRange · ${seg.days}天',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color:
                    isUngrouped ? AppColors.textMuted : AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${net >= 0 ? '+' : ''}${net.abs().toStringAsFixed(0)} HKD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isUngrouped ? AppColors.textMuted : netColor,
              fontFeatures: AppColors.tabular,
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 13, color: AppColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (lineAnchorId == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _buildContent(),
      );
    }
    return LongPressDraggable<int>(
      data: lineAnchorId,
      feedback: Material(
        type: MaterialType.transparency,
        child: _buildContent(floating: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _buildContent(),
        ),
      ),
      onDragUpdate: onDragUpdate,
      onDragEnd: (_) => onDragStopped?.call(),
      onDraggableCanceled: (_, __) => onDragStopped?.call(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _buildContent(),
      ),
    );
  }
}

/// 上桌计时条 — 筛选栏下方通栏
/// 未计时：一行「上桌计时」按钮；计时中：墨绿底实时走秒 + 「下桌」
class _TableTimerBar extends StatefulWidget {
  const _TableTimerBar();

  @override
  State<_TableTimerBar> createState() => _TableTimerBarState();
}

class _TableTimerBarState extends State<_TableTimerBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker(context.read<TableTimerProvider>());
  }

  /// 计时中每秒刷新走秒显示；停止计时则停掉 ticker（只重建本组件，不影响列表）
  void _syncTicker(TableTimerProvider timer) {
    if (timer.isRunning && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!timer.isRunning && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = context.watch<TableTimerProvider>();
    _syncTicker(timer);
    if (timer.isRunning) return _buildRunning(context, timer);
    return _buildIdle(context);
  }

  /// 未计时状态：低调的「上桌计时」按钮
  Widget _buildIdle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: OutlinedButton.icon(
          onPressed: () => context.read<TableTimerProvider>().start(),
          icon: const Icon(Icons.timer_outlined, size: 18),
          label: const Text('打卡', style: TextStyle(fontSize: 14)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.seed,
            side: BorderSide(color: AppColors.seed.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  /// 计时中状态：墨绿底 + 实时走秒 + 上桌中 + 下桌按钮
  Widget _buildRunning(BuildContext context, TableTimerProvider timer) {
    final d = timer.elapsed;
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.seed,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '工时',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$hh:$mm:$ss',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: AppColors.tabular,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 28,
            child: FilledButton(
              onPressed: () => _finish(context),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.seed,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 28),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: const Text('收工'),
            ),
          ),
        ],
      ),
    );
  }

  /// 下桌：兜底确认（不足5分钟=疑似误触 / 超12小时=疑似忘按）→ 停止计时 → 跳新增记账页（时长自动填）
  Future<void> _finish(BuildContext context) async {
    final timer = context.read<TableTimerProvider>();
    final d = timer.elapsed;

    if (d < const Duration(minutes: 5) || d > const Duration(hours: 12)) {
      final hint = d < const Duration(minutes: 5)
          ? '本次计时不足 5 分钟，确定收工吗？'
          : '本次计时已超过 12 小时，确定收工吗？';
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('收工记一局？'),
          content: Text(hint),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消本次计时'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'finish'),
              child: const Text('收工'),
            ),
          ],
        ),
      );
      if (action == 'cancel') {
        await timer.cancel();
        return;
      }
      if (action == null) return; // 点外部关闭 → 保持计时
    }

    final duration = await timer.stop();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordEditPage(
          initialDuration: duration.inMinutes / 60.0,
        ),
      ),
    );
  }
}
