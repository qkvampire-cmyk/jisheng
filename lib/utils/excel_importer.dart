import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../models/exchange_record.dart';
import '../models/poker_record.dart';

/// 导入结果汇总
class ImportResult {
  final List<PokerRecord> newRecords;
  final int duplicateCount;
  final int failedCount;
  final List<String> failedDetails;

  /// 导入的兑换记录（换机备份还原用）
  final List<ExchangeRecord> newExchangeRecords;
  final int exchangeDuplicateCount;
  final String? errorMessage;

  ImportResult({
    required this.newRecords,
    required this.duplicateCount,
    required this.failedCount,
    required this.failedDetails,
    this.newExchangeRecords = const [],
    this.exchangeDuplicateCount = 0,
    this.errorMessage,
  });
}

/// Excel 导入工具
class ExcelImporter {
  // 列名 → 匹配关键词（中英文混合，用户表格千变万化）
  static const Map<String, List<String>> _columnKeywords = {
    'time': ['时间', '日期', 'date', 'time'],
    'amount': ['金额', '盈亏', '筹码', 'result', 'amount', 'profit', 'win', 'loss'],
    'blind': ['盲注', '盲', 'blind', '级别', 'stake', 'level'],
    'currency': ['币种', '货币', 'currency', '币别'],
    'location': ['地点', '赌场', '场地', 'location', 'casino', 'place', 'venue'],
    'duration': ['时长', '小时', 'duration', 'hour', 'length', 'time'],
    'remark': ['备注', '说明', 'remark', 'note', 'comment', 'memo'],
    'trip': ['行程', 'trip'],
  };

  static const List<String> _requiredColumns = ['time', 'amount', 'blind'];

  /// 从 Excel 字节流导入，返回结果
  static Future<ImportResult> importFromBytes(
    List<int> bytes,
    List<PokerRecord> existingRecords, {
    List<ExchangeRecord> existingExchangeRecords = const [],
  }) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.sheets.isEmpty) {
        return _error('文件为空或无法读取');
      }

      final sheet = excel.sheets.values.first;
      if (sheet.rows.isEmpty) {
        return _error('工作表为空');
      }

      // 找表头行（扫描前 N 行）
      final headerRow = _findHeaderRow(sheet);
      if (headerRow == null) {
        return _error('无法识别表头行。\n请确保表格第一行包含「时间」「金额」「盲注」等列名');
      }

      final columnMap = _matchColumns(headerRow);

      // 检查必填列
      final missingRequired =
          _requiredColumns.where((c) => !columnMap.containsKey(c)).toList();
      if (missingRequired.isNotEmpty) {
        final names =
            missingRequired.map((c) => _columnKeywords[c]!.first).join('、');
        return _error('缺少必填列：$names\n请确保表格包含这些列（名称不要求完全一致）');
      }

      // 构建已有记录的去重 key 集合
      final existingKeys = existingRecords.map((r) => _dedupKey(r)).toSet();

      // 行程还原：现有最大行程 id 基础上递增分配
      // 同一「行程」标记的记录共用同一 trip_id，未分组/空 = null
      final maxTripId = existingRecords.fold<int>(
          0, (m, r) => r.tripId != null && r.tripId! > m ? r.tripId! : m);
      final tripIdByLabel = <String, int>{};
      var nextTripId = maxTripId + 1;

      final newRecords = <PokerRecord>[];
      int duplicateCount = 0;
      int failedCount = 0;
      final failedDetails = <String>[];

      // ===== 兑换记录 sheet 解析（换机备份还原）=====
      final exchangeRecords = <ExchangeRecord>[];
      int exchangeDupCount = 0;
      final exSheet = _findExchangeSheet(excel);
      if (exSheet != null) {
        final existingExKeys =
            existingExchangeRecords.map((r) => _exDedupKey(r)).toSet();
        final exHeader = _findHeaderRow(exSheet);
        if (exHeader != null) {
          final exColMap = _matchExchangeColumns(exHeader);
          final exHeaderIndex = exSheet.rows.indexOf(exHeader);
          for (int i = exHeaderIndex + 1; i < exSheet.rows.length; i++) {
            final row = exSheet.rows[i];
            if (row.every((c) =>
                c == null || (c.value?.toString().trim() ?? '').isEmpty)) {
              continue;
            }
            try {
              final er = _parseExchangeRow(row, exColMap);
              if (er == null) continue;
              final key = _exDedupKey(er);
              if (existingExKeys.contains(key)) {
                exchangeDupCount++;
                continue;
              }
              exchangeRecords.add(er);
              existingExKeys.add(key);
            } catch (_) {
              // 单行解析失败跳过，不阻塞整体导入
            }
          }
        }
      }

      // 从表头下一行开始解析数据
      final headerIndex = sheet.rows.indexOf(headerRow);
      for (int i = headerIndex + 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        // 跳过全空行
        if (row.every(
            (c) => c == null || (c.value?.toString().trim() ?? '').isEmpty)) {
          continue;
        }

        try {
          var record = _parseRow(row, columnMap);
          if (record == null) {
            failedCount++;
            failedDetails.add('第 ${i + 1} 行：关键字段为空（时间/金额/盲注）');
            continue;
          }

          // 行程还原：按「行程」列分组，同组记录分配同一 trip_id
          final tripLabel =
              (_getCellValue(row, columnMap, 'trip')?.toString().trim() ?? '');
          if (tripLabel.isNotEmpty && !tripLabel.contains('未分组')) {
            final tid =
                tripIdByLabel.putIfAbsent(tripLabel, () => nextTripId++);
            record = record.copyWith(tripId: tid);
          }

          final key = _dedupKey(record);
          if (existingKeys.contains(key)) {
            duplicateCount++;
            continue;
          }

          newRecords.add(record);
          existingKeys.add(key); // 同批次去重
        } catch (e) {
          failedCount++;
          failedDetails.add('第 ${i + 1} 行：$e');
        }
      }

      return ImportResult(
        newRecords: newRecords,
        duplicateCount: duplicateCount,
        failedCount: failedCount,
        failedDetails: failedDetails,
        newExchangeRecords: exchangeRecords,
        exchangeDuplicateCount: exchangeDupCount,
      );
    } catch (e) {
      return _error('文件解析失败：$e\n请确认文件是有效的 Excel 表格 (.xlsx) 格式');
    }
  }

  static ImportResult _error(String msg) {
    return ImportResult(
      newRecords: [],
      duplicateCount: 0,
      failedCount: 0,
      failedDetails: [],
      errorMessage: msg,
    );
  }

  /// 扫描前 5 行，找关键词匹配最多的作为表头
  static List<Data?>? _findHeaderRow(Sheet sheet) {
    int bestScore = 0;
    List<Data?>? bestRow;
    final limit = sheet.rows.length > 5 ? 5 : sheet.rows.length;

    for (int i = 0; i < limit; i++) {
      final row = sheet.rows[i];
      int score = 0;
      for (final cell in row) {
        if (cell == null) continue;
        final text = cell.value?.toString().toLowerCase() ?? '';
        for (final keywords in _columnKeywords.values) {
          if (keywords.any((kw) => text.contains(kw.toLowerCase()))) {
            score++;
          }
        }
      }
      // 至少匹配 2 个关键词才算有效表头
      if (score > bestScore && score >= 2) {
        bestScore = score;
        bestRow = row;
      }
    }
    return bestRow;
  }

  /// 关键词贪心匹配列 → 列索引
  static Map<String, int> _matchColumns(List<Data?> headerRow) {
    final Map<String, int> assignment = {};
    final assignedCols = <int>{};

    for (final key in _columnKeywords.keys) {
      int bestCol = -1;
      int bestScore = 0;

      for (int col = 0; col < headerRow.length; col++) {
        if (assignedCols.contains(col)) continue;
        final cell = headerRow[col];
        if (cell == null) continue;
        final text = cell.value?.toString().toLowerCase() ?? '';

        int score = 0;
        for (final kw in _columnKeywords[key]!) {
          if (text.contains(kw.toLowerCase())) score++;
        }

        if (score > bestScore) {
          bestScore = score;
          bestCol = col;
        }
      }

      if (bestCol >= 0 && bestScore > 0) {
        assignment[key] = bestCol;
        assignedCols.add(bestCol);
      }
    }

    return assignment;
  }

  /// 解析单行数据，返回 PokerRecord 或 null（关键字段缺失）
  static PokerRecord? _parseRow(List<Data?> row, Map<String, int> colMap) {
    // 时间（必填）
    final time = _getCellValue(row, colMap, 'time');
    if (time == null) return null;
    final recordTime = _parseDateTime(time);
    if (recordTime == null) return null;

    // 金额（必填，支持正负号/文本盈亏表述）
    final amountVal = _getCellValue(row, colMap, 'amount');
    if (amountVal == null) return null;
    final amount = _parseAmount(amountVal);
    if (amount == null) return null;

    // 盲注（必填）
    final blindVal = _getCellValue(row, colMap, 'blind');
    if (blindVal == null) return null;
    final blind = blindVal.toString().trim();
    if (blind.isEmpty) return null;

    // 币种（选填，默认 HKD）
    String currency = 'HKD';
    final curVal = _getCellValue(row, colMap, 'currency');
    if (curVal != null) {
      final t = curVal.toString().trim().toUpperCase();
      if (t.contains('CNY') ||
          t.contains('CN') ||
          t.contains('人民币') ||
          t.contains('RMB')) {
        currency = 'CNY';
      }
    }

    // 地点（选填，默认威尼斯人）
    String location = '威尼斯人 (Venetian)';
    final locVal = _getCellValue(row, colMap, 'location');
    if (locVal != null) {
      final t = locVal.toString().trim();
      if (t.isNotEmpty) location = t;
    }

    // 时长（选填，默认 0）
    double duration = 0;
    final durVal = _getCellValue(row, colMap, 'duration');
    if (durVal != null) {
      duration = _parseDouble(durVal) ?? 0;
    }

    // 备注（选填）
    String? remark;
    final remVal = _getCellValue(row, colMap, 'remark');
    if (remVal != null) {
      final t = remVal.toString().trim();
      if (t.isNotEmpty) remark = t;
    }

    return PokerRecord(
      recordTime: recordTime,
      duration: duration,
      location: location,
      currency: currency,
      amount: amount,
      blindLevel: blind,
      remark: remark,
    );
  }

  /// 安全获取单元格值
  static dynamic _getCellValue(
      List<Data?> row, Map<String, int> colMap, String key) {
    final col = colMap[key];
    if (col == null || col >= row.length) return null;
    final cell = row[col];
    if (cell == null) return null;
    return cell.value;
  }

  /// 解析日期，支持 Excel 序列号 / 多种文本格式
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    // Excel DateTimeCellValue
    if (value is DateTime) return value;

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    // 尝试常见格式
    const formats = [
      'yyyy-MM-dd HH:mm',
      'yyyy/MM/dd HH:mm',
      'yyyy-MM-ddTHH:mm',
      'yyyy/MM/ddTHH:mm',
      'yyyy-M-d HH:mm',
      'yyyy/M/d HH:mm',
      'MM/dd/yyyy HH:mm',
      'yyyy-MM-dd',
      'yyyy/MM/dd',
    ];

    for (final fmt in formats) {
      try {
        return DateFormat(fmt).parseStrict(text);
      } catch (_) {}
    }

    // 兜底：宽松解析
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parse(text);
    } catch (_) {
      return null;
    }
  }

  /// 解析金额，支持正负数、文本表述（赢/输/盈利/亏损）
  static double? _parseAmount(dynamic value) {
    if (value == null) return null;

    // 数字类型直接返回
    if (value is double) return value;
    if (value is int) return value.toDouble();

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    // 去掉千位分隔符
    final clean = text.replaceAll(',', '').replaceAll('，', '').trim();

    // 尝试直接解析
    final direct = double.tryParse(clean);
    if (direct != null) return direct;

    // 含正负号的文本（"+1000" / " -500"）
    if (clean.startsWith('+') || clean.startsWith('-')) {
      final num = double.tryParse(clean.replaceAll(RegExp(r'[^\d.\-+]'), ''));
      if (num != null) return num;
    }

    // 文本表述：赢了/盈利 +1000、输了/亏损 -500
    final lower = clean.toLowerCase();
    final isLoss =
        ['输', '亏损', '亏', 'lose', 'loss'].any((w) => lower.contains(w));
    final isWin =
        ['赢', '盈利', '赚', 'win', 'profit'].any((w) => lower.contains(w));

    // 提取数字
    final numMatch = RegExp(r'[\d.]+').firstMatch(clean);
    if (numMatch == null) return null;
    final num = double.tryParse(numMatch.group(0)!);
    if (num == null) return null;

    if (isLoss) return -num.abs();
    if (isWin) return num.abs();
    // 纯数字未知状态，默认正数（盈利）
    return num.abs();
  }

  /// 解析 double
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    final clean =
        value.toString().trim().replaceAll(',', '').replaceAll('，', '');
    return double.tryParse(clean);
  }

  /// 去重 key：时间(到分钟) + 地点 + 金额 + 盲注
  static String _dedupKey(PokerRecord r) {
    final t = r.recordTime;
    final timeStr =
        '${t.year}-${_pad(t.month)}-${_pad(t.day)} ${_pad(t.hour)}:${_pad(t.minute)}';
    return '$timeStr|${r.location}|${r.amount}|${r.blindLevel}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ========== 兑换记录 sheet 解析 ==========

  static const Map<String, List<String>> _exColumnKeywords = {
    'ex_time': ['操作时间', '时间', '日期', 'date', 'time'],
    'ex_hkd': ['港币', 'hkd', '取出', '取现', '金额'],
    'ex_cny': ['人民币', '到账', 'cny', 'rmb'],
    'ex_rate': ['汇率', 'rate'],
    'ex_fee': ['手续费', 'fee'],
    'ex_remark': ['备注', 'remark', 'note', 'comment', 'memo'],
  };

  /// 查找兑换记录 sheet（按 sheet 名包含「兑换」或 exchange 识别）
  static Sheet? _findExchangeSheet(Excel excel) {
    for (final entry in excel.sheets.entries) {
      final name = entry.key.toLowerCase();
      if (name.contains('兑换') || name.contains('exchange')) {
        return entry.value;
      }
    }
    return null;
  }

  /// 兑换表头列匹配（与账目表头逻辑一致）
  static Map<String, int> _matchExchangeColumns(List<Data?> headerRow) {
    final assignment = <String, int>{};
    final assignedCols = <int>{};
    for (final key in _exColumnKeywords.keys) {
      int bestCol = -1;
      int bestScore = 0;
      for (int col = 0; col < headerRow.length; col++) {
        if (assignedCols.contains(col)) continue;
        final cell = headerRow[col];
        if (cell == null) continue;
        final text = cell.value?.toString().toLowerCase() ?? '';
        int score = 0;
        for (final kw in _exColumnKeywords[key]!) {
          if (text.contains(kw.toLowerCase())) score++;
        }
        if (score > bestScore) {
          bestScore = score;
          bestCol = col;
        }
      }
      if (bestCol >= 0 && bestScore > 0) {
        assignment[key] = bestCol;
        assignedCols.add(bestCol);
      }
    }
    return assignment;
  }

  /// 解析兑换单行；时间/港币金额缺失返回 null
  static ExchangeRecord? _parseExchangeRow(
      List<Data?> row, Map<String, int> colMap) {
    final timeVal = _getCellValue(row, colMap, 'ex_time');
    final createTime = _parseDateTime(timeVal);
    if (createTime == null) return null;

    final hkdVal = _getCellValue(row, colMap, 'ex_hkd');
    final hkdCash = _parseDouble(hkdVal);
    if (hkdCash == null) return null;

    final bankCny = _parseDouble(_getCellValue(row, colMap, 'ex_cny')) ?? 0;
    final rateVal = _parseDouble(_getCellValue(row, colMap, 'ex_rate'));
    final feeHkd = _parseDouble(_getCellValue(row, colMap, 'ex_fee')) ?? 0;
    final remarkVal = _getCellValue(row, colMap, 'ex_remark');
    final remark = remarkVal?.toString().trim().isEmpty == true
        ? null
        : remarkVal?.toString().trim();

    if (rateVal != null && rateVal > 0) {
      return ExchangeRecord(
        createTime: createTime,
        hkdCash: hkdCash,
        bankCny: bankCny,
        actualRate: rateVal,
        feeHkd: feeHkd,
        remark: remark,
      );
    }
    return ExchangeRecord.fromAmounts(
      createTime: createTime,
      hkdCash: hkdCash,
      bankCny: bankCny,
      feeHkd: feeHkd,
      remark: remark,
    );
  }

  /// 兑换去重 key：时间(到分钟) + 港币金额 + 人民币到账 + 汇率
  static String _exDedupKey(ExchangeRecord r) {
    final t = r.createTime;
    final timeStr =
        '${t.year}-${_pad(t.month)}-${_pad(t.day)} ${_pad(t.hour)}:${_pad(t.minute)}';
    return '$timeStr|${r.hkdCash}|${r.bankCny}|${r.actualRate}';
  }
}
