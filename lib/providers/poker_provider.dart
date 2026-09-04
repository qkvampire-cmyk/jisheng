import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/poker_record.dart';
import '../models/record_segment.dart';
import '../models/time_range.dart';

class PokerProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<PokerRecord> _records = [];
  List<String> _locations = [];
  double _exchangeRate = 0.8678; // 默认 1 HKD = 0.8678 CNY (2026-07-11 实时中间价)
  String _lastLocation = '';
  String _lastTableType = '';
  TimeRangeSelection _timeRange = const TimeRangeSelection();
  bool _isLoading = false;
  bool _tripEnded = false; // 行程已封顶：新记录自动开新行程

  List<PokerRecord> get records => _records;
  List<String> get locations => _locations;
  double get exchangeRate => _exchangeRate;
  String get lastLocation => _lastLocation;
  String get lastTableType => _lastTableType;
  TimeRangeSelection get timeRange => _timeRange;
  bool get isLoading => _isLoading;
  bool get tripEnded => _tripEnded;

  /// 常用盲注级别
  static const List<String> presetBlinds = [
    '50/100',
    '100/200',
    '200/400',
    '300/600',
    '500/1000',
    '1000/2000',
  ];

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    await _loadExchangeRate();
    await _loadLastLocation();
    await _loadLastTableType();
    await _loadTimeRange();
    await _loadTripEnded();
    await loadRecords();
    await loadLocations();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadExchangeRate() async {
    final prefs = await SharedPreferences.getInstance();
    _exchangeRate = prefs.getDouble('exchange_rate') ?? 0.8678;
  }

  Future<void> _loadLastLocation() async {
    final prefs = await SharedPreferences.getInstance();
    _lastLocation = prefs.getString('last_location') ?? '';
  }

  Future<void> _loadLastTableType() async {
    final prefs = await SharedPreferences.getInstance();
    _lastTableType = prefs.getString('last_table_type') ?? '';
  }

  Future<void> setExchangeRate(double rate) async {
    _exchangeRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('exchange_rate', rate);
    notifyListeners();
  }

  Future<void> setLastLocation(String location) async {
    _lastLocation = location;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_location', location);
  }

  Future<void> setLastTableType(String tableType) async {
    _lastTableType = tableType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_table_type', tableType);
  }

  Future<void> _loadTimeRange() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString('time_range_type') ?? 'all';
    final type = TimeRangeType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => TimeRangeType.all,
    );
    DateTime? customStart;
    final startMs = prefs.getInt('time_range_custom_start');
    if (startMs != null)
      customStart = DateTime.fromMillisecondsSinceEpoch(startMs);
    DateTime? customEnd;
    final endMs = prefs.getInt('time_range_custom_end');
    if (endMs != null) customEnd = DateTime.fromMillisecondsSinceEpoch(endMs);
    List<int>? tripIds;
    final tripStr = prefs.getString('time_range_trip_ids');
    if (tripStr != null && tripStr.isNotEmpty) {
      tripIds = tripStr.split(',').map(int.parse).toList();
    }
    _timeRange = TimeRangeSelection(
        type: type,
        customStart: customStart,
        customEnd: customEnd,
        tripIds: tripIds);
  }

  Future<void> _loadTripEnded() async {
    final prefs = await SharedPreferences.getInstance();
    _tripEnded = prefs.getBool('trip_ended') ?? false;
  }

  Future<void> setTimeRange(TimeRangeSelection range) async {
    _timeRange = range;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('time_range_type', range.type.name);
    if (range.type == TimeRangeType.custom &&
        range.customStart != null &&
        range.customEnd != null) {
      await prefs.setInt(
          'time_range_custom_start', range.customStart!.millisecondsSinceEpoch);
      await prefs.setInt(
          'time_range_custom_end', range.customEnd!.millisecondsSinceEpoch);
    } else {
      await prefs.remove('time_range_custom_start');
      await prefs.remove('time_range_custom_end');
    }
    if (range.type == TimeRangeType.trip) {
      await prefs.setString(
          'time_range_trip_ids', (range.tripIds ?? []).join(','));
    } else {
      await prefs.remove('time_range_trip_ids');
    }
    notifyListeners();
  }

  Future<void> loadRecords() async {
    _records = await _db.getAllRecords();
    notifyListeners();
  }

  Future<void> loadLocations() async {
    _locations = await _db.getAllLocations();
    notifyListeners();
  }

  Future<void> addRecord(PokerRecord record) async {
    var r = record;
    // 行程已封顶：新记录自动开启新行程，并解除封顶
    if (_tripEnded) {
      final newTripId = await _db.maxTripId() + 1;
      r = record.copyWith(tripId: newTripId);
      _tripEnded = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('trip_ended', false);
    }
    await _db.insertRecord(r);
    await loadRecords();
  }

  Future<void> updateRecord(PokerRecord record) async {
    await _db.updateRecord(record);
    await loadRecords();
  }

  Future<void> deleteRecord(int id) async {
    await _db.deleteRecord(id);
    await loadRecords();
  }

  /// 批量导入记录（一个事务，只通知一次）
  Future<void> addRecords(List<PokerRecord> records) async {
    await _db.insertRecords(records);
    await loadRecords();
  }

  Future<void> addLocation(String name) async {
    await _db.addLocation(name);
    await loadLocations();
  }

  // ========== 行程分界 ==========

  /// 当前过滤范围内的行程段（降序，与列表一致）
  List<RecordSegment> get segments => _buildSegments(filteredRecords);

  /// 全部记录的行程段（不受时间范围过滤影响，用于行程选择弹窗）
  List<RecordSegment> get allSegments => _buildSegments(_records);

  /// 按 tripId 连续分组构建行程段；行程编号按时间升序自动编号
  /// （未分组段 tripNo = 0，不占编号）
  List<RecordSegment> _buildSegments(List<PokerRecord> list) {
    final result = <RecordSegment>[];
    for (final r in list) {
      if (result.isEmpty || result.last.tripId != r.tripId) {
        result.add(RecordSegment(
          tripId: r.tripId,
          records: [r],
          netHKD: r.getAmountIn('HKD', _exchangeRate),
        ));
      } else {
        final seg = result.last;
        seg.records.add(r);
        seg.netHKD += r.getAmountIn('HKD', _exchangeRate);
      }
    }
    // 编号：段按最早记录时间升序，非未分组段依次编号
    final ordered = [...result]..sort((a, b) => a.start.compareTo(b.start));
    var no = 0;
    for (final seg in ordered) {
      if (seg.tripId != null) seg.tripNo = ++no;
    }
    return result;
  }

  /// 在 anchor 记录处切分（终止线）：加号位于 anchor 与其下一条之间，
  /// anchor 及以上保留在当前行程，更旧的记录（不含 anchor）封存为新行程
  Future<void> insertBreakAt(PokerRecord anchor) async {
    final segs = segments;
    final seg = segs.firstWhere((s) => s.records.any((r) => r.id == anchor.id));
    final ids = seg.records
        .where((r) => r.recordTime.isBefore(anchor.recordTime))
        .map((r) => r.id)
        .whereType<int>()
        .toList();
    if (ids.isEmpty) return;
    final newTripId = await _db.maxTripId() + 1;
    await _db.assignTrip(ids, newTripId);
    await loadRecords();
  }

  /// 顶部终止线：把当前行程（未分组记录）封存为一趟行程，
  /// 并标记行程已结束 —— 之后新增的记录自动开启新行程
  Future<void> markTripEnded() async {
    final ungrouped = _records
        .where((r) => r.tripId == null)
        .map((r) => r.id)
        .whereType<int>()
        .toList();
    if (ungrouped.isNotEmpty) {
      final newTripId = await _db.maxTripId() + 1;
      await _db.assignTrip(ungrouped, newTripId);
    }
    _tripEnded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trip_ended', true);
    await loadRecords();
  }

  /// 取消封顶（删除顶部终止线）
  Future<void> clearTripEnded() async {
    _tripEnded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('trip_ended', false);
    notifyListeners();
  }

  /// 移动分界线：lineAnchorId = 分界线下方的段（B）最新记录 id
  /// target = 拖拽落点记录；above = 落点在卡片上半（线移到 target 上方）
  /// 边界只能在相邻两段之间移动，越界落点忽略
  Future<void> moveBreak(
      int lineAnchorId, PokerRecord target, bool above) async {
    final segs = segments;
    final bIdx =
        segs.indexWhere((s) => s.records.any((r) => r.id == lineAnchorId));
    if (bIdx <= 0) return; // 无上方段
    final a = segs[bIdx - 1];
    final b = segs[bIdx];
    final tIdx =
        segs.indexWhere((s) => s.records.any((r) => r.id == target.id));
    if (tIdx != bIdx - 1 && tIdx != bIdx) return; // 只调相邻两段边界
    List<int> ids;
    if (tIdx == bIdx - 1) {
      // 落点在上方段 A：above → 线到 T 上方（[T..A尾] 归 B）；否则 → 线到 T 下方（T 之后更旧的归 B）
      ids = (above
              ? a.records.where((r) => !r.recordTime.isAfter(target.recordTime))
              : a.records.where((r) => r.recordTime.isAfter(target.recordTime)))
          .map((r) => r.id)
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) await _db.assignTrip(ids, b.tripId);
    } else {
      // 落点在下方段 B：above → 线到 T 上方（[B头..T 之前] 归 A）；否则 → [B头..T] 归 A
      ids = (above
              ? b.records.where((r) => r.recordTime.isBefore(target.recordTime))
              : b.records
                  .where((r) => !r.recordTime.isAfter(target.recordTime)))
          .map((r) => r.id)
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) await _db.assignTrip(ids, a.tripId);
    }
    await loadRecords();
  }

  /// 删除分界线：下方段整体并入上方段（合并行程）
  Future<void> deleteBreak(int lineAnchorId) async {
    final segs = segments;
    final bIdx =
        segs.indexWhere((s) => s.records.any((r) => r.id == lineAnchorId));
    if (bIdx <= 0) return; // 最顶段/未分组上方无线，无可合并
    final a = segs[bIdx - 1];
    final b = segs[bIdx];
    final ids = b.records.map((r) => r.id).whereType<int>().toList();
    if (ids.isNotEmpty) await _db.assignTrip(ids, a.tripId);
    await loadRecords();
  }

  // ========== 统计计算 ==========

  /// 获取指定月份的记录，null表示全部
  List<PokerRecord> getFilteredRecords(int? year, int? month) {
    if (year == null || month == null) return _records;
    return _records.where((r) {
      return r.recordTime.year == year && r.recordTime.month == month;
    }).toList();
  }

  /// 根据当前选中的时间范围过滤记录
  List<PokerRecord> get filteredRecords {
    final now = DateTime.now();
    switch (_timeRange.type) {
      case TimeRangeType.all:
        return _records;
      case TimeRangeType.thisMonth:
        return _records
            .where((r) =>
                r.recordTime.year == now.year &&
                r.recordTime.month == now.month)
            .toList();
      case TimeRangeType.thisYear:
        return _records.where((r) => r.recordTime.year == now.year).toList();
      case TimeRangeType.last7Days:
        {
          final cutoff = now.subtract(const Duration(days: 7));
          return _records.where((r) => r.recordTime.isAfter(cutoff)).toList();
        }
      case TimeRangeType.last30Days:
        {
          final cutoff = now.subtract(const Duration(days: 30));
          return _records.where((r) => r.recordTime.isAfter(cutoff)).toList();
        }
      case TimeRangeType.custom:
        {
          if (_timeRange.customStart == null || _timeRange.customEnd == null) {
            return _records;
          }
          final start = _timeRange.customStart!;
          final end = _timeRange.customEnd!.add(const Duration(days: 1));
          return _records
              .where((r) =>
                  !r.recordTime.isBefore(start) && r.recordTime.isBefore(end))
              .toList();
        }
      case TimeRangeType.trip:
        {
          final ids = _timeRange.tripIds;
          if (ids == null || ids.isEmpty) return const [];
          return _records.where((r) {
            final t = r.tripId;
            if (t == null) return ids.contains(-1); // -1 = 未分组
            return ids.contains(t);
          }).toList();
        }
    }
  }

  /// 总场次
  int totalSessions(List<PokerRecord> list) => list.length;

  /// 总对局时长
  double totalDuration(List<PokerRecord> list) {
    return list.fold(0, (sum, r) => sum + r.duration);
  }

  /// 盈利场次
  int profitSessions(List<PokerRecord> list) {
    return list.where((r) => r.isProfit).length;
  }

  /// 亏损场次
  int lossSessions(List<PokerRecord> list) {
    return list.where((r) => !r.isProfit).length;
  }

  /// 累计净盈亏（港币）
  double totalNetProfitHKD(List<PokerRecord> list) {
    return list.fold(0, (sum, r) => sum + r.getAmountIn('HKD', _exchangeRate));
  }

  /// 累计净盈亏（人民币）
  double totalNetProfitCNY(List<PokerRecord> list) {
    return list.fold(0, (sum, r) => sum + r.displayCny(_exchangeRate));
  }

  /// 单场最大盈利（港币）
  double maxProfitHKD(List<PokerRecord> list) {
    if (list.isEmpty) return 0;
    final profits = list
        .where((r) => r.isProfit)
        .map((r) => r.getAmountIn('HKD', _exchangeRate));
    if (profits.isEmpty) return 0;
    return profits.reduce((a, b) => a > b ? a : b);
  }

  /// 单场最大亏损（港币，绝对值）
  double maxLossHKD(List<PokerRecord> list) {
    if (list.isEmpty) return 0;
    final losses = list
        .where((r) => !r.isProfit)
        .map((r) => r.getAmountIn('HKD', _exchangeRate).abs());
    if (losses.isEmpty) return 0;
    return losses.reduce((a, b) => a > b ? a : b);
  }

  /// 按场地分组统计盈亏（港币）
  Map<String, double> profitByLocation(List<PokerRecord> list) {
    final Map<String, double> result = {};
    for (final r in list) {
      result[r.location] =
          (result[r.location] ?? 0) + r.getAmountIn('HKD', _exchangeRate);
    }
    return result;
  }

  /// 获取所有可用的月份列表（倒序）
  List<DateTime> getAvailableMonths() {
    final Set<String> months = {};
    for (final r in _records) {
      months.add('${r.recordTime.year}-${r.recordTime.month}');
    }
    final sorted = months.toList()..sort((a, b) => b.compareTo(a));
    return sorted.map((s) {
      final parts = s.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]));
    }).toList();
  }
}
