/// 港币存取兑换流水记录
class ExchangeRecord {
  final int? id;
  final DateTime createTime; // 取现/操作时间
  final double hkdCash; // 取出港币总额（正数）
  final double bankCny; // 银行卡到账人民币
  final double actualRate; // 实际成交汇率 (bankCny / hkdCash)
  final double feeHkd; // 取现手续费（港币，默认0）
  final String? remark; // 备注

  const ExchangeRecord({
    this.id,
    required this.createTime,
    required this.hkdCash,
    required this.bankCny,
    required this.actualRate,
    this.feeHkd = 0,
    this.remark,
  });

  /// 从 hkdCash 和 bankCny 自动计算 actualRate
  factory ExchangeRecord.fromAmounts({
    int? id,
    required DateTime createTime,
    required double hkdCash,
    required double bankCny,
    double feeHkd = 0,
    String? remark,
  }) {
    final rate = hkdCash > 0 ? bankCny / hkdCash : 0.0;
    return ExchangeRecord(
      id: id,
      createTime: createTime,
      hkdCash: hkdCash,
      bankCny: bankCny,
      actualRate: rate,
      feeHkd: feeHkd,
      remark: remark,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'create_time': createTime.millisecondsSinceEpoch,
      'hkd_cash': hkdCash,
      'bank_cny': bankCny,
      'actual_rate': actualRate,
      'fee_hkd': feeHkd,
      'remark': remark,
    };
  }

  factory ExchangeRecord.fromMap(Map<String, dynamic> map) {
    // 容错解析：旧库可能缺列/null（曾导致整张兑换表读成空表、导出空表）
    double numOf(Object? v, [double fallback = 0]) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    final timeRaw = map['create_time'];
    final createTime = timeRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(timeRaw)
        : DateTime.now();
    final hkd = numOf(map['hkd_cash']);
    final cny = numOf(map['bank_cny']);
    final rateRaw = map['actual_rate'];
    final rate = rateRaw == null
        ? (hkd > 0 ? cny / hkd : 0.0)
        : numOf(rateRaw);

    return ExchangeRecord(
      id: map['id'] as int?,
      createTime: createTime,
      hkdCash: hkd,
      bankCny: cny,
      actualRate: rate,
      feeHkd: numOf(map['fee_hkd']),
      remark: map['remark'] as String?,
    );
  }

  ExchangeRecord copyWith({
    int? id,
    DateTime? createTime,
    double? hkdCash,
    double? bankCny,
    double? actualRate,
    double? feeHkd,
    String? remark,
  }) {
    return ExchangeRecord(
      id: id ?? this.id,
      createTime: createTime ?? this.createTime,
      hkdCash: hkdCash ?? this.hkdCash,
      bankCny: bankCny ?? this.bankCny,
      actualRate: actualRate ?? this.actualRate,
      feeHkd: feeHkd ?? this.feeHkd,
      remark: remark ?? this.remark,
    );
  }
}
