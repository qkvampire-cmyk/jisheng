/// 时间筛选类型
enum TimeRangeType {
  all,
  thisMonth,
  thisYear,
  last7Days,
  last30Days,
  custom,
  trip, // 按行程（多选）
}

/// 时间筛选选择
class TimeRangeSelection {
  final TimeRangeType type;
  final DateTime? customStart;
  final DateTime? customEnd;

  /// 选中的行程 id 列表（trip 类型时生效；-1 代表未分组）
  final List<int>? tripIds;

  const TimeRangeSelection({
    this.type = TimeRangeType.all,
    this.customStart,
    this.customEnd,
    this.tripIds,
  });

  TimeRangeSelection copyWith({
    TimeRangeType? type,
    DateTime? customStart,
    DateTime? customEnd,
    List<int>? tripIds,
    bool clearCustom = false,
    bool clearTrip = false,
  }) {
    return TimeRangeSelection(
      type: type ?? this.type,
      customStart: clearCustom ? null : (customStart ?? this.customStart),
      customEnd: clearCustom ? null : (customEnd ?? this.customEnd),
      tripIds: clearTrip ? null : (tripIds ?? this.tripIds),
    );
  }
}
