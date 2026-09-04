import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/exchange_record.dart';
import '../models/poker_record.dart';

class ExcelExporter {
  static Future<String> exportRecords(
    List<PokerRecord> records,
    double exchangeRate, {
    List<ExchangeRecord> exchangeRecords = const [],
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['PokerRecords'];

    // 行程编号映射（与账单页一致：非未分组段按最早记录时间升序编号）
    final tripNos = _buildTripNumbers(records);

    // 表头
    final headers = [
      '行程',
      '记账时间',
      '对局时长(小时)',
      '场次地点',
      '盲注级别',
      '原始币种',
      '原始金额',
      '港币金额',
      '人民币金额',
      '备注',
      '桌型',
      '牌谱备注',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // 数据行
    for (final r in records) {
      final hkd = r.getAmountIn('HKD', exchangeRate);
      final cny = r.displayCny(exchangeRate);
      final tripNo = r.tripId == null ? null : tripNos[r.tripId];
      sheet.appendRow([
        TextCellValue(tripNo != null ? '行程$tripNo' : '未分组'),
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(r.recordTime)),
        DoubleCellValue(r.duration),
        TextCellValue(r.location),
        TextCellValue(r.blindLevel),
        TextCellValue(r.currency),
        DoubleCellValue(r.amount),
        DoubleCellValue(double.parse(hkd.toStringAsFixed(2))),
        DoubleCellValue(double.parse(cny.toStringAsFixed(2))),
        TextCellValue(r.remark ?? ''),
        TextCellValue(r.tableType ?? ''),
        TextCellValue(r.handNotes ?? ''),
      ]);
    }

    // 汇总行
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('汇总统计')]);
    final totalSessions = records.length;
    final totalHours = records.fold<double>(0, (s, r) => s + r.duration);
    final totalHKD = records.fold<double>(
        0, (s, r) => s + r.getAmountIn('HKD', exchangeRate));
    final totalCNY =
        records.fold<double>(0, (s, r) => s + r.displayCny(exchangeRate));

    sheet.appendRow([TextCellValue('总场次'), IntCellValue(totalSessions)]);
    sheet.appendRow([TextCellValue('总时长(小时)'), DoubleCellValue(totalHours)]);
    sheet.appendRow([
      TextCellValue('累计净盈亏(HKD)'),
      DoubleCellValue(double.parse(totalHKD.toStringAsFixed(2)))
    ]);
    sheet.appendRow([
      TextCellValue('累计净盈亏(CNY)'),
      DoubleCellValue(double.parse(totalCNY.toStringAsFixed(2)))
    ]);
    sheet.appendRow(
        [TextCellValue('汇率(1HKD=?CNY)'), DoubleCellValue(exchangeRate)]);

    // 港币兑换记录 sheet
    final exSheet = excel['兑换记录'];
    const exHeaders = ['操作时间', '港币金额', '人民币到账', '实际汇率', '手续费(港币)', '备注'];
    exSheet.appendRow(exHeaders.map((h) => TextCellValue(h)).toList());
    for (final r in exchangeRecords) {
      exSheet.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(r.createTime)),
        DoubleCellValue(r.hkdCash),
        DoubleCellValue(r.bankCny),
        DoubleCellValue(double.parse(r.actualRate.toStringAsFixed(4))),
        DoubleCellValue(r.feeHkd),
        TextCellValue(r.remark ?? ''),
      ]);
    }

    // 保存到临时目录后调用系统分享
    final directory = await getTemporaryDirectory();
    final fileName =
        'poker_records_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final filePath = '${directory.path}/$fileName';

    final fileBytes = excel.save();
    final file = File(filePath);
    await file.writeAsBytes(fileBytes!);

    // 调用系统分享
    await Share.shareXFiles(
      [XFile(filePath)],
      text: '德州扑克记账数据导出',
    );

    return filePath;
  }

  /// 构建 tripId → 行程编号 映射（非未分组段按段内最早记录时间升序编号）
  static Map<int, int> _buildTripNumbers(List<PokerRecord> records) {
    final tripNos = <int, int>{};
    // 按 tripId 连续分组（records 为时间降序）
    final segs = <List<PokerRecord>>[];
    for (final r in records) {
      if (segs.isEmpty || segs.last.first.tripId != r.tripId) {
        segs.add([r]);
      } else {
        segs.last.add(r);
      }
    }
    final ordered = [...segs]
      ..sort((a, b) => a.last.recordTime.compareTo(b.last.recordTime));
    var no = 0;
    for (final s in ordered) {
      final tid = s.first.tripId;
      if (tid != null) tripNos[tid] = ++no;
    }
    return tripNos;
  }
}
