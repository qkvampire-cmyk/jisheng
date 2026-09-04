import 'dart:math';
import '../models/poker_record.dart';

/// 盲注级别字符串 → 大盲注金额（HKD）
/// "50/100" → 100，"100/200" → 200；无法解析返回 null
double? bbValueOf(String blindLevel) {
  final parts = blindLevel.split('/');
  if (parts.length != 2) return null;
  final bb = double.tryParse(parts[1].trim());
  return (bb != null && bb > 0) ? bb : null;
}

/// 波动分析结果
class VolatilityResult {
  /// 真实赢率（bb/100）：手动值或当前范围赢率估计
  final double mu;

  /// 标准差（bb/100），加权残差法围绕 μ 从当前范围估计
  final double sigma;

  /// 当前范围累计盈亏（bb）
  final double totalBb;

  /// 当前范围累计盈亏（HKD，原始币种口径）
  final double totalHkd;

  /// 当前范围估算总手数
  final double totalHands;

  /// 当前范围有效场次
  final int sessionCount;

  /// 当前范围总块数（100手=1块）
  final double blockCount;

  /// 每场结束时的累计手数（含起点 0）
  final List<double> cumHands;

  /// 每场结束时的累计盈亏（bb）
  final List<double> cumBb;

  /// 当前回撤（bb）：当前范围历史峰值 − 当前累计，≥0
  final double currentDrawdown;

  /// 当前回撤（HKD）：当前范围累计 HKD 峰值 − 当前累计 HKD，≥0
  final double drawdownHkd;

  /// 蒙特卡洛：终点回撤 ≥ 当前回撤的路径比例（0~1）
  final double drawdownProb;

  /// mu 来源：true=手动，false=自动
  final bool muManual;

  /// 样本是否不足（有效场次 < 5 或 块数 < 3）
  final bool insufficient;

  /// 未能解析盲注级别而被跳过的记录数（当前范围）
  final int skippedCount;

  const VolatilityResult({
    required this.mu,
    required this.sigma,
    required this.totalBb,
    required this.totalHkd,
    required this.totalHands,
    required this.sessionCount,
    required this.blockCount,
    required this.cumHands,
    required this.cumBb,
    required this.currentDrawdown,
    required this.drawdownHkd,
    required this.drawdownProb,
    required this.muManual,
    required this.insufficient,
    required this.skippedCount,
  });
}

/// 内部归一化结果
class _Normalized {
  final List<(PokerRecord, double, double, double)>
      valid; // (record, bb, hands, blocks)
  final double blockCount;
  final double totalBb;
  final int skipped;

  _Normalized(this.valid, this.blockCount, this.totalBb, this.skipped);
}

_Normalized _normalize(
    List<PokerRecord> records, double exchangeRate, double handsPerHour) {
  final valid = <(PokerRecord, double, double, double)>[];
  var skipped = 0;
  for (final r in records) {
    final bbValue = bbValueOf(r.blindLevel);
    if (bbValue == null) {
      skipped++;
      continue;
    }
    final hkd = r.getAmountIn('HKD', exchangeRate);
    final bb = hkd / bbValue;
    final hands = r.duration * handsPerHour;
    valid.add((r, bb, hands, hands / 100));
  }
  final blockCount = valid.fold<double>(0, (s, e) => s + e.$4);
  final totalBb = valid.fold<double>(0, (s, e) => s + e.$2);
  return _Normalized(valid, blockCount, totalBb, skipped);
}

/// 加权残差法估计 σ（每 100 手盈亏标准差，bb/100）
double _estimateSigma(List<(PokerRecord, double, double, double)> valid,
    double blockCount, double mu) {
  if (blockCount < 1) return 0;
  var residSum = 0.0;
  for (final e in valid) {
    final resid = e.$2 - mu * e.$4;
    residSum += resid * resid / e.$4;
  }
  return sqrt(residSum / (blockCount - 1));
}

/// 计算波动分析。
///
/// μ 自动 = 当前范围赢率（bb/100），手动 = 手动值；σ 围绕同一 μ 加权残差估计；
/// 曲线/回撤/概率全部基于当前范围（records），同一口径。
VolatilityResult computeVolatility({
  required List<PokerRecord> records,
  required double exchangeRate,
  required double handsPerHour,
  double? manualMu, // null = 自动估计（当前范围赢率）
}) {
  final cur = _normalize(records, exchangeRate, handsPerHour);

  final n = cur.valid.length;
  final blockCount = cur.blockCount;
  final totalBb = cur.totalBb;
  final totalHands = cur.blockCount * 100;
  // 当前范围累计 HKD（原始币种口径，直接累加）
  var totalHkd = 0.0;
  for (final e in cur.valid) {
    totalHkd += e.$1.getAmountIn('HKD', exchangeRate);
  }

  if (n < 2 || blockCount < 1) {
    return VolatilityResult(
      mu: manualMu ?? 0,
      sigma: 0,
      totalBb: totalBb,
      totalHkd: totalHkd,
      totalHands: totalHands,
      sessionCount: n,
      blockCount: blockCount,
      cumHands: const [0],
      cumBb: const [0],
      currentDrawdown: 0,
      drawdownHkd: 0,
      drawdownProb: 1,
      muManual: manualMu != null,
      insufficient: true,
      skippedCount: cur.skipped,
    );
  }

  // μ：自动 = 当前范围赢率，手动 = 手动值；σ 围绕同一 μ 加权残差估计
  final mu = manualMu ?? totalBb / blockCount;
  final sigma = _estimateSigma(cur.valid, blockCount, mu);

  // 累计曲线（按时间排序，当前范围）
  cur.valid.sort((a, b) => a.$1.recordTime.compareTo(b.$1.recordTime));
  final cumHands = <double>[0];
  final cumBb = <double>[0];
  var hAcc = 0.0, bAcc = 0.0, peak = 0.0;
  var hkdAcc = 0.0, hkdPeak = 0.0;
  for (final e in cur.valid) {
    hAcc += e.$3;
    bAcc += e.$2;
    hkdAcc += e.$1.getAmountIn('HKD', exchangeRate);
    cumHands.add(hAcc);
    cumBb.add(bAcc);
    if (bAcc > peak) peak = bAcc;
    if (hkdAcc > hkdPeak) hkdPeak = hkdAcc;
  }
  final currentDrawdown = max(0.0, peak - bAcc);
  final drawdownHkd = max(0.0, hkdPeak - hkdAcc);

  // 蒙特卡洛：终点回撤分布（块级随机游走，按当前范围块数）
  final prob = _drawdownProb(blockCount, mu, sigma, currentDrawdown);

  return VolatilityResult(
    mu: mu,
    sigma: sigma,
    totalBb: totalBb,
    totalHkd: totalHkd,
    totalHands: totalHands,
    sessionCount: n,
    blockCount: blockCount,
    cumHands: cumHands,
    cumBb: cumBb,
    currentDrawdown: currentDrawdown,
    drawdownHkd: drawdownHkd,
    drawdownProb: prob,
    muManual: manualMu != null,
    insufficient: n < 5 || blockCount < 3,
    skippedCount: cur.skipped,
  );
}

/// 蒙特卡洛：K 块随机游走（每块 ~ N(mu, sigma)），
/// 统计"路径终点相对其历史峰值的回撤 ≥ target"的路径比例。
double _drawdownProb(double k, double mu, double sigma, double target) {
  if (target <= 0) return 1.0;
  if (sigma <= 0) return 0.0;
  final blocks = k.round();
  if (blocks < 1) return 1.0;

  const paths = 5000;
  final rng = Random(42); // 固定种子：结果可复现
  var hit = 0;
  for (var p = 0; p < paths; p++) {
    var cum = 0.0, peak = 0.0, endDrawdown = 0.0;
    for (var b = 0; b < blocks; b++) {
      cum += _norm(rng, mu, sigma);
      if (cum > peak) peak = cum;
    }
    endDrawdown = peak - cum;
    if (endDrawdown >= target) hit++;
  }
  return hit / paths;
}

/// Box-Muller 正态采样
double _norm(Random rng, double mean, double std) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0 - 1e-12);
  final u2 = rng.nextDouble();
  final z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  return mean + z * std;
}
