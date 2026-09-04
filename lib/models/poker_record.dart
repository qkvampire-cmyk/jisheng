/// 单局账目记录实体
class PokerRecord {
  final int? id;
  final DateTime recordTime; // 记账时间
  final double duration; // 对局时长（小时）
  final String location; // 场次地点
  final String currency; // 原始币种：HKD / CNY
  final double amount; // 原始盈亏金额（正数盈利，负数亏损）
  final String blindLevel; // 盲注级别
  final String? remark; // 备注
  final double? cnyAmount; // 录入时的人民币金额（null 表示旧数据，用当前汇率换算）
  final String? tableType; // 桌型（如 8人桌 / 9人桌）
  final String? handNotes; // 牌谱备注
  final int? tripId; // 所属行程 id（null = 未分组）

  const PokerRecord({
    this.id,
    required this.recordTime,
    required this.duration,
    required this.location,
    required this.currency,
    required this.amount,
    this.cnyAmount,
    required this.blindLevel,
    this.remark,
    this.tableType,
    this.handNotes,
    this.tripId,
  });

  /// 是否盈利（不含保本）
  bool get isProfit => amount > 0;

  /// 根据汇率计算另一币种金额
  double getAmountIn(String targetCurrency, double exchangeRate) {
    if (currency == targetCurrency) return amount;
    if (targetCurrency == 'HKD') {
      // CNY -> HKD
      return amount / exchangeRate;
    } else {
      // HKD -> CNY
      return amount * exchangeRate;
    }
  }

  /// 展示用的人民币金额：优先使用录入时存储的 cnyAmount，否则用当前汇率计算
  double displayCny(double currentRate) {
    return cnyAmount ?? getAmountIn('CNY', currentRate);
  }

  /// 地点 → 默认桌型映射
  static const Map<String, String> locationDefaultTableType = {
    '威尼斯人 (Venetian)': '9人桌',
    '永利 (Wynn)': '9人桌',
    '美狮美高梅 (MGM)': '8人桌',
    '上葡京 (Lisboa Palace)': '8人桌',
  };

  /// 根据地点返回默认桌型
  static String getDefaultTableType(String location) {
    return locationDefaultTableType[location] ?? '9人桌';
  }

  /// 桌型可选值列表
  static const List<String> tableTypeOptions = ['8人桌', '9人桌'];

  /// 静态换算工具方法，无需创建临时记录
  static double convertAmount(double amount, String fromCurrency,
      String toCurrency, double exchangeRate) {
    if (fromCurrency == toCurrency) return amount;
    if (toCurrency == 'HKD') return amount / exchangeRate;
    return amount * exchangeRate;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'record_time': recordTime.millisecondsSinceEpoch,
      'duration': duration,
      'location': location,
      'currency': currency,
      'amount': amount,
      'cny_amount': cnyAmount,
      'blind_level': blindLevel,
      'remark': remark,
      'table_type': tableType,
      'hand_notes': handNotes,
      'trip_id': tripId,
    };
  }

  factory PokerRecord.fromMap(Map<String, dynamic> map) {
    return PokerRecord(
      id: map['id'] as int?,
      recordTime:
          DateTime.fromMillisecondsSinceEpoch(map['record_time'] as int),
      duration: (map['duration'] as num).toDouble(),
      location: map['location'] as String,
      currency: map['currency'] as String,
      amount: (map['amount'] as num).toDouble(),
      cnyAmount: (map['cny_amount'] as num?)?.toDouble(),
      blindLevel: map['blind_level'] as String,
      remark: map['remark'] as String?,
      tableType: map['table_type'] as String?,
      handNotes: map['hand_notes'] as String?,
      tripId: map['trip_id'] as int?,
    );
  }

  PokerRecord copyWith({
    int? id,
    DateTime? recordTime,
    double? duration,
    String? location,
    String? currency,
    double? amount,
    double? cnyAmount,
    String? blindLevel,
    String? remark,
    String? tableType,
    String? handNotes,
    int? tripId,
  }) {
    return PokerRecord(
      id: id ?? this.id,
      recordTime: recordTime ?? this.recordTime,
      duration: duration ?? this.duration,
      location: location ?? this.location,
      currency: currency ?? this.currency,
      amount: amount ?? this.amount,
      cnyAmount: cnyAmount ?? this.cnyAmount,
      blindLevel: blindLevel ?? this.blindLevel,
      remark: remark ?? this.remark,
      tableType: tableType ?? this.tableType,
      handNotes: handNotes ?? this.handNotes,
      tripId: tripId ?? this.tripId,
    );
  }
}
