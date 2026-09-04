import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/exchange_record.dart';

class ExchangeProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<ExchangeRecord> _records = [];
  bool _isLoading = false;

  List<ExchangeRecord> get records => _records;
  bool get isLoading => _isLoading;

  Future<void> loadRecords() async {
    _isLoading = true;
    notifyListeners();

    _records = await _db.getAllExchangeRecords();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addRecord(ExchangeRecord record) async {
    await _db.insertExchangeRecord(record);
    await loadRecords();
  }

  /// 批量导入兑换记录
  Future<void> addRecords(List<ExchangeRecord> records) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert('exchange_records', r.toMap()..remove('id'));
    }
    await batch.commit(continueOnError: false);
    await loadRecords();
  }

  Future<void> updateRecord(ExchangeRecord record) async {
    await _db.updateExchangeRecord(record);
    await loadRecords();
  }

  Future<void> deleteRecord(int id) async {
    await _db.deleteExchangeRecord(id);
    await loadRecords();
  }

  /// 按时间范围过滤记录
  List<ExchangeRecord> filterByTimeRange({
    DateTime? start,
    DateTime? end,
  }) {
    var filtered = _records;
    if (start != null) {
      filtered = filtered.where((r) => r.createTime.isAfter(start)).toList();
    }
    if (end != null) {
      filtered = filtered.where((r) => r.createTime.isBefore(end)).toList();
    }
    return filtered;
  }

  // ========== 统计 ==========

  double totalHkd(List<ExchangeRecord> list) {
    return list.fold(0, (sum, r) => sum + r.hkdCash);
  }

  double totalCny(List<ExchangeRecord> list) {
    // 只统计已结汇的记录（bankCny > 0）
    return list
        .where((r) => r.bankCny > 0)
        .fold(0, (sum, r) => sum + r.bankCny);
  }

  double totalFee(List<ExchangeRecord> list) {
    return list.fold(0, (sum, r) => sum + r.feeHkd);
  }

  /// 已结汇的记录数
  int settledCount(List<ExchangeRecord> list) {
    return list.where((r) => r.bankCny > 0).length;
  }

  /// 待结汇的记录数
  int pendingCount(List<ExchangeRecord> list) {
    return list.where((r) => r.bankCny == 0).length;
  }

  double averageRate(List<ExchangeRecord> list) {
    final settled = list.where((r) => r.bankCny > 0).toList();
    if (settled.isEmpty) return 0;
    final totalH = totalHkd(settled);
    if (totalH == 0) return 0;
    return totalCny(settled) / totalH;
  }
}
