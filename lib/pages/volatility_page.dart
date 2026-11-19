import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/poker_provider.dart';
import '../providers/volatility_provider.dart';
import '../theme/app_colors.dart';
import '../utils/volatility_calculator.dart';

/// 波动分析页 — 累计盈亏曲线（主角）+ EV理论线 + 峰值/回撤标注 + 下风期诊断
class VolatilityPage extends StatefulWidget {
  const VolatilityPage({super.key});

  @override
  State<VolatilityPage> createState() => _VolatilityPageState();
}

class _VolatilityPageState extends State<VolatilityPage> {
  final _handsController = TextEditingController();
  final _muController = TextEditingController();
  bool _manualMuMode = false;

  @override
  void initState() {
    super.initState();
    final vol = context.read<VolatilityProvider>();
    _handsController.text = vol.handsPerHour.toStringAsFixed(0);
    _muController.text = vol.manualMuValue.toStringAsFixed(0);
    _manualMuMode = vol.manualMu;
  }

  @override
  void dispose() {
    _handsController.dispose();
    _muController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PokerProvider>();
    final volProvider = context.watch<VolatilityProvider>();
    final records = provider.filteredRecords;

    if (records.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.waves, size: 56, color: AppColors.emptyIcon),
            SizedBox(height: 16),
            Text('暂无账目记录',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            SizedBox(height: 8),
            Text('记账后这里会显示你的累计盈亏曲线',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    final result = computeVolatility(
      records: records,
      exchangeRate: provider.exchangeRate,
      handsPerHour: volProvider.handsPerHour,
      manualMu: volProvider.effectiveManualMu,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 波动图
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _LegendLine('累计盈亏'),
                    _LegendDash('EV理论线'),
                    _LegendItem(Color(0x33DC2626), '当前回撤'),
                  ],
                ),
              ),
              SizedBox(
                height: 320,
                child: CustomPaint(
                  painter: _VolatilityChartPainter(result),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 三个数字卡
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: '累计盈亏',
                value: '${result.totalHkd >= 0 ? '+' : '-'}'
                    '${result.totalHkd.abs().toStringAsFixed(0)}',
                subtitle: '${result.totalBb >= 0 ? '+' : '-'}'
                    '${result.totalBb.abs().toStringAsFixed(0)}bb',
                color: result.totalHkd >= 0 ? AppColors.win : AppColors.loss,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: '当前回撤',
                value: result.drawdownHkd <= 0.5
                    ? '—'
                    : '-${result.drawdownHkd.toStringAsFixed(0)}',
                subtitle: result.currentDrawdown > 0.5
                    ? '-${result.currentDrawdown.toStringAsFixed(0)}bb'
                    : null,
                color: result.drawdownHkd > 0.5
                    ? AppColors.loss
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: '下风概率',
                value: result.insufficient || result.currentDrawdown <= 0.5
                    ? '—'
                    : '${(result.drawdownProb * 100).toStringAsFixed(1)}%',
                color: result.drawdownProb <= 0.02 &&
                        result.currentDrawdown > 0.5 &&
                        !result.insufficient
                    ? AppColors.loss
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 诊断卡
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.insufficient
                      ? Icons.info_outline
                      : (result.currentDrawdown <= 0.5
                          ? Icons.trending_up
                          : (result.drawdownProb > 0.02
                              ? Icons.waves
                              : Icons.warning_amber_rounded)),
                  size: 20,
                  color: result.drawdownProb <= 0.02 &&
                          result.currentDrawdown > 0.5 &&
                          !result.insufficient
                      ? AppColors.loss
                      : AppColors.seed,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _diagnosis(result),
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 参数（点击展开调整）
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            shape: const Border(),
            title: Row(
              children: [
                const Icon(Icons.tune,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '参数 · 手数${volProvider.handsPerHour.toStringAsFixed(0)}手/h · μ=${result.mu.toStringAsFixed(0)}(${result.muManual ? '手动' : '自动'})',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('手数/小时（现场节奏）',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _handsController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '默认 25',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('真实赢率 μ (bb/100)',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('自动估计')),
                  ButtonSegment(value: true, label: Text('手动填写')),
                ],
                selected: {_manualMuMode},
                onSelectionChanged: (s) =>
                    setState(() => _manualMuMode = s.first),
                showSelectedIcon: false,
              ),
              if (_manualMuMode) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _muController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '例如 30',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveParams,
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('σ 自动从账目计算；μ 手动填保守值（如 30）更不容易误报。',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 参数脚注
        Text(
          _footnote(result, volProvider),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  String _diagnosis(VolatilityResult r) {
    if (r.insufficient) {
      return '样本不足（有效 ${r.sessionCount} 场），曲线仅供参考；记录越多越准。';
    }
    if (r.currentDrawdown <= 0.5) {
      return '当前处于累计盈亏历史高点，无回撤。继续按计划打即可。';
    }
    final pct = (r.drawdownProb * 100).toStringAsFixed(1);
    final ddHkd = r.drawdownHkd.toStringAsFixed(0);
    final ddBb = r.currentDrawdown.toStringAsFixed(0);
    final muTxt = r.mu.toStringAsFixed(0);
    if (r.drawdownProb > 0.1) {
      return '当前回撤 -$ddHkd HKD（-$ddBb bb），按真实赢率 $muTxt bb/100，出现概率约 $pct%，属常见波动，无需调整。';
    }
    if (r.drawdownProb > 0.02) {
      return '当前回撤 -$ddHkd HKD（-$ddBb bb），出现概率约 $pct%，偏深下风但仍在正常范围。';
    }
    return '当前回撤 -$ddHkd HKD（-$ddBb bb），出现概率仅 $pct%，已超出正常波动范围，建议检查打法或换环境。';
  }

  String _footnote(VolatilityResult r, VolatilityProvider v) {
    final muSrc = r.muManual ? '手动' : '自动';
    final muTxt = r.mu.toStringAsFixed(0);
    final hands = r.totalHands.toStringAsFixed(0);
    return '基于 ${r.sessionCount} 场 / $hands 手 · μ=$muTxt($muSrc) · σ=${r.sigma.toStringAsFixed(0)} · 手数${v.handsPerHour.toStringAsFixed(0)}手/h · 卡片HKD、图与概率bb口径 · 参数可展开上方卡片调整';
  }

  Future<void> _saveParams() async {
    final hands = double.tryParse(_handsController.text);
    final mu = double.tryParse(_muController.text);
    if (hands == null || hands <= 0 || hands > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的手数/小时（1-100）')),
      );
      return;
    }
    if (_manualMuMode && (mu == null || mu <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的赢率（bb/100）')),
      );
      return;
    }
    final vol = context.read<VolatilityProvider>();
    await vol.setHandsPerHour(hands);
    if (_manualMuMode) {
      await vol.setManualMu(true);
      await vol.setManualMuValue(mu!);
    } else {
      await vol.setManualMu(false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('波动参数已保存')),
      );
    }
  }
}

/// 数字指标卡
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _MetricCard(
      {required this.label,
      required this.value,
      this.subtitle,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: AppColors.tabular,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 图例色块项
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendItem(this.color, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(text,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// 图例曲线项
class _LegendLine extends StatelessWidget {
  final String text;

  const _LegendLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 2.5, color: const Color(0xFF3F3A36)),
        const SizedBox(width: 4),
        Text(text,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// 图例虚线项
class _LegendDash extends StatelessWidget {
  final String text;

  const _LegendDash(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('┄┄┄',
            style: TextStyle(
                fontSize: 11, color: Color(0xFF6B7280), letterSpacing: -1)),
        const SizedBox(width: 4),
        Text(text,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// 波动图绘制：累计盈亏曲线（主角）+ EV 虚线 + 峰值/当前回撤标注
class _VolatilityChartPainter extends CustomPainter {
  final VolatilityResult r;

  // 莫兰迪调
  static const _curve = Color(0xFF3F3A36); // 暖深灰
  static const _evLine = Color(0xFF6B7280); // 加深，与零线明确区分
  static const _zeroLine = Color(0xFFE0DCD6); // 浅色实线（不再是虚线）
  static const _ddFill = Color(0x1ADC2626); // 当前回撤区间填充 10% 红
  static const _sessionDot = Color(0x406B7280); // 每场结束点 25% 灰

  _VolatilityChartPainter(this.r);

  @override
  void paint(Canvas canvas, Size size) {
    if (r.totalHands <= 0 || r.cumBb.length < 2) return;

    const padL = 58.0, padR = 10.0, padT = 12.0, padB = 34.0;
    final w = size.width, h = size.height;
    final plotW = w - padL - padR, plotH = h - padT - padB;

    // EV 理论线采样点
    final ev =
        List<double>.generate(81, (i) => r.mu * (r.totalHands * i / 80) / 100);

    // 曲线是主角：Y 轴按累计曲线自适应；EV 端点只允许把跨度撑到曲线的 1.6 倍以内
    var minV = 0.0, maxV = 0.0;
    for (final v in r.cumBb) {
      minV = min(minV, v);
      maxV = max(maxV, v);
    }
    final curveSpan = max(1.0, maxV - minV);
    final evEnd = r.mu * r.blockCount; // EV 线终点（bb）
    var lo = min(minV, min(0.0, evEnd));
    var hi = max(maxV, max(0.0, evEnd));
    final limit = curveSpan * 1.6;
    if (hi - lo > limit) {
      final mid = (minV + maxV) / 2;
      lo = mid - limit / 2;
      hi = mid + limit / 2;
    }
    // 上下各留 10% 余量
    final pad = (hi - lo) * 0.10;
    minV = lo - pad;
    maxV = hi + pad;

    double xOf(double hands) => padL + (hands / r.totalHands) * plotW;
    double yOf(double v) => padT + (maxV - v) / (maxV - minV) * plotH;

    // 历史峰值 / 当前回撤区间（峰值之后 → 现在）
    var peakIdx = 0;
    for (var i = 1; i < r.cumBb.length; i++) {
      if (r.cumBb[i] > r.cumBb[peakIdx]) peakIdx = i;
    }
    final peakVal = r.cumBb[peakIdx];

    // 绘图区裁剪：EV 线超出范围时不会画到坐标轴/图例区
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padL, padT, plotW, plotH));

    // 当前回撤区间填充（峰值 → 现在的曲线下方），浅红
    if (r.cumBb.last < peakVal - 0.5 && peakIdx < r.cumBb.length - 1) {
      final dd = Path()..moveTo(xOf(r.cumHands[peakIdx]), yOf(peakVal));
      for (var i = peakIdx + 1; i < r.cumBb.length; i++) {
        dd.lineTo(xOf(r.cumHands[i]), yOf(r.cumBb[i]));
      }
      dd.lineTo(xOf(r.cumHands.last), yOf(peakVal));
      dd.close();
      canvas.drawPath(dd, Paint()..color = _ddFill);
    }

    // 零线（浅色实线，避免与 EV 虚线混淆）
    final zeroY = yOf(0);
    if (zeroY >= padT && zeroY <= h - padB) {
      canvas.drawLine(
          Offset(padL, zeroY),
          Offset(w - padR, zeroY),
          Paint()
            ..color = _zeroLine
            ..strokeWidth = 1);
    }

    // EV 虚线（加深加粗）
    final evPaint = Paint()
      ..color = _evLine
      ..strokeWidth = 1.6;
    for (var i = 0; i < 80; i++) {
      _dashLine(canvas, Offset(xOf(r.totalHands * i / 80), yOf(ev[i])),
          Offset(xOf(r.totalHands * (i + 1) / 80), yOf(ev[i + 1])), evPaint);
    }

    // 累计曲线（主角，加粗）
    final curvePaint = Paint()
      ..color = _curve
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pathCurve = Path();
    for (var i = 0; i < r.cumBb.length; i++) {
      final p = Offset(xOf(r.cumHands[i]), yOf(r.cumBb[i]));
      if (i == 0) {
        pathCurve.moveTo(p.dx, p.dy);
      } else {
        pathCurve.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(pathCurve, curvePaint);

    // 每场结束点（淡灰小点，体现单场颗粒度；点太密时省略避免糊成一片）
    if (r.cumBb.length <= 90) {
      final dotPaint = Paint()..color = _sessionDot;
      for (var i = 1; i < r.cumBb.length; i++) {
        canvas.drawCircle(
            Offset(xOf(r.cumHands[i]), yOf(r.cumBb[i])), 1.7, dotPaint);
      }
    }

    // 终点圆点
    final end = Offset(xOf(r.cumHands.last), yOf(r.cumBb.last));
    canvas.drawCircle(end, 4, Paint()..color = AppColors.seed);
    canvas.drawCircle(
        end,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // 峰值标记（墨绿小点 + 白边）
    final peakPt = Offset(xOf(r.cumHands[peakIdx]), yOf(peakVal));
    if (peakIdx > 0) {
      canvas.drawCircle(peakPt, 3.4, Paint()..color = AppColors.seed);
      canvas.drawCircle(
          peakPt,
          3.4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }

    canvas.restore(); // 结束绘图区裁剪

    // 轴刻度
    final labelStyle = TextStyle(
        fontSize: 10, color: AppColors.textMuted.withValues(alpha: 0.9));
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String txt, Offset pos, {bool right = false}) {
      tp.text = TextSpan(text: txt, style: labelStyle);
      tp.layout();
      tp.paint(canvas, right ? pos - Offset(tp.width, 0) : pos);
    }

    // Y：max / 0 / min（右对齐到绘图区左缘）
    void yTick(double v) {
      tp.text = TextSpan(text: v.toStringAsFixed(0), style: labelStyle);
      tp.layout();
      tp.paint(canvas, Offset(padL - 6 - tp.width, yOf(v) - 8));
    }

    // Y 刻度标数据真实边界（lo/hi），10% 留白只影响画布位置
    yTick(hi);
    if (lo < 0 && hi > 0) yTick(0);
    yTick(lo);

    // 峰值标注（贴在峰值点上方；顶部没空间则翻到点下方）
    if (peakIdx > 0) {
      tp.text = TextSpan(
          text: '峰值 ${peakVal.toStringAsFixed(0)}',
          style: TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600));
      tp.layout();
      var lx = peakPt.dx - tp.width / 2;
      lx = lx.clamp(padL, max(padL, w - padR - tp.width)).toDouble();
      var ly = peakPt.dy - 11 - tp.height;
      if (ly < padT) ly = peakPt.dy + 9;
      tp.paint(canvas, Offset(lx, ly));
    }
    // X：0 / ½ / 总手数
    label('0', Offset(padL, h - padB + 6));
    label((r.totalHands / 2).toStringAsFixed(0),
        Offset(xOf(r.totalHands / 2) - 14, h - padB + 6));
    label(r.totalHands.toStringAsFixed(0), Offset(w - padR - 34, h - padB + 6));

    // Y 轴单位（垂直）
    final yUnitTp = TextPainter(
      text: const TextSpan(
          text: '盈亏 (bb)',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(10, padT + plotH / 2);
    canvas.rotate(-pi / 2);
    yUnitTp.paint(canvas, Offset(-yUnitTp.width / 2, 0));
    canvas.restore();

    // X 轴单位（底部居中）
    final xUnitTp = TextPainter(
      text: const TextSpan(
          text: '手数（估）',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      textDirection: TextDirection.ltr,
    )..layout();
    xUnitTp.paint(
        canvas, Offset(padL + plotW / 2 - xUnitTp.width / 2, h - padB + 20));
  }

  /// 沿线段画虚线
  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0, gap = 4.0;
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len <= 0) return;
    final ux = dx / len, uy = dy / len;
    var d = 0.0;
    while (d < len) {
      final e = min(d + dash, len);
      canvas.drawLine(Offset(a.dx + ux * d, a.dy + uy * d),
          Offset(a.dx + ux * e, a.dy + uy * e), paint);
      d = e + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _VolatilityChartPainter oldDelegate) =>
      oldDelegate.r != r;
}
