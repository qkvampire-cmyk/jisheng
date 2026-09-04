import 'poker_record.dart';

/// 行程段：按 tripId 连续分组的一段记录（列表降序排列，段内记录同属一个行程）
class RecordSegment {
  /// 行程 id；null = 未分组
  final int? tripId;

  /// 段内记录（降序，与账单列表一致）
  final List<PokerRecord> records;

  /// 段内最早记录时间（records 为降序，最后一条 = 最旧）
  DateTime get start => records.last.recordTime;

  /// 段内最晚记录时间（records 为降序，第一条 = 最新）
  DateTime get end => records.first.recordTime;

  /// 段内净盈亏（港币）
  double netHKD;

  /// 行程编号（按时间升序自动编号，1 起；0 = 未分组）
  int tripNo;

  /// 行程持续天数（首尾跨度 +1）
  int get days => end.difference(start).inDays + 1;

  RecordSegment({
    required this.tripId,
    required this.records,
    required this.netHKD,
  }) : tripNo = 0;

  bool get isUngrouped => tripId == null;
}
