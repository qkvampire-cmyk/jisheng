import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/poker_record.dart';
import '../models/time_range.dart';
import '../providers/poker_provider.dart';
import '../theme/app_colors.dart';
import 'record_edit_page.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PokerProvider>();
    final filteredRecords = provider.filteredRecords;

    return Column(
      children: [
        // 时间筛选栏
        _buildFilterBar(context, provider),
        // 统计内容
        Expanded(
          child: filteredRecords.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bar_chart_outlined,
                          size: 64, color: AppColors.emptyIcon),
                      const SizedBox(height: 16),
                      Text('暂无数据',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 16)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      16, 16, 16, kBottomNavigationBarHeight + 16),
                  children: [
                    _buildNetHeroCard(provider, filteredRecords),
                    const SizedBox(height: 16),
                    _buildSummaryCard(provider, filteredRecords),
                    const SizedBox(height: 16),
                    _buildExtremesCard(provider, filteredRecords, context),
                    const SizedBox(height: 16),
                    _buildLocationStats(provider, filteredRecords),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context, PokerProvider provider) {
    final range = provider.timeRange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(color: AppColors.surfaceTint),
      child: Row(
        children: [
          const Text('统计范围：', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: range.type.name,
              isDense: true,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('全部数据')),
                DropdownMenuItem(value: 'thisMonth', child: Text('本月')),
                DropdownMenuItem(value: 'thisYear', child: Text('今年')),
                DropdownMenuItem(value: 'last7Days', child: Text('近7天')),
                DropdownMenuItem(value: 'last30Days', child: Text('近30天')),
                DropdownMenuItem(value: 'custom', child: Text('自定义')),
              ],
              onChanged: (v) async {
                if (v == 'custom') {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: (range.type == TimeRangeType.custom &&
                            range.customStart != null &&
                            range.customEnd != null)
                        ? DateTimeRange(
                            start: range.customStart!,
                            end: range.customEnd!,
                          )
                        : null,
                  );
                  if (picked != null && context.mounted) {
                    context.read<PokerProvider>().setTimeRange(
                          TimeRangeSelection(
                            type: TimeRangeType.custom,
                            customStart: picked.start,
                            customEnd: picked.end,
                          ),
                        );
                  }
                  return;
                }
                if (context.mounted) {
                  final type =
                      TimeRangeType.values.firstWhere((t) => t.name == v!);
                  context
                      .read<PokerProvider>()
                      .setTimeRange(TimeRangeSelection(type: type));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(PokerProvider provider, List<PokerRecord> records) {
    final totalSessions = provider.totalSessions(records);
    final totalHours = provider.totalDuration(records);
    final profitCount = provider.profitSessions(records);
    final lossCount = provider.lossSessions(records);
    final winRate = totalSessions > 0
        ? (profitCount / totalSessions * 100).toStringAsFixed(1)
        : '0';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '整体汇总',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('总场次', '$totalSessions 场'),
                _buildStatItem('总时长', '${totalHours.toStringAsFixed(1)} h'),
                _buildStatItem('胜率', '$winRate%'),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('盈利场次', '$profitCount 场', color: AppColors.win),
                _buildStatItem('亏损场次', '$lossCount 场', color: AppColors.loss),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 净盈亏 Hero 卡：墨绿渐变 + 顶部聚光，全页第一视觉焦点
  Widget _buildNetHeroCard(PokerProvider provider, List<PokerRecord> records) {
    final netHKD = provider.totalNetProfitHKD(records);
    final netCNY = provider.totalNetProfitCNY(records);
    final totalSessions = provider.totalSessions(records);
    final winRate = totalSessions > 0
        ? (provider.profitSessions(records) / totalSessions * 100)
            .toStringAsFixed(1)
        : '0';
    final isWin = netHKD >= 0;
    final sign = isWin ? '+' : '-';

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.heroGradient),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '累计净盈亏 (HKD)',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  '$sign${netHKD.abs().toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: isWin ? AppColors.win : AppColors.loss,
                    fontFeatures: AppColors.tabular,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${netCNY >= 0 ? '+' : ''}${netCNY.toStringAsFixed(0)} CNY',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    fontFeatures: AppColors.tabular,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: Colors.black.withValues(alpha: 0.1),
                ),
                const SizedBox(height: 10),
                Text(
                  '累计 $totalSessions 场 · 胜率 $winRate%',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtremesCard(
      PokerProvider provider, List<PokerRecord> records, BuildContext context) {
    final maxProfit = provider.maxProfitHKD(records);
    final maxLoss = provider.maxLossHKD(records);

    // 找到对应的记录
    final profitRecord = records.where((r) => r.isProfit).toList()
      ..sort((a, b) => b
          .getAmountIn('HKD', provider.exchangeRate)
          .compareTo(a.getAmountIn('HKD', provider.exchangeRate)));
    final lossRecord = records.where((r) => !r.isProfit).toList()
      ..sort((a, b) => a
          .getAmountIn('HKD', provider.exchangeRate)
          .compareTo(b.getAmountIn('HKD', provider.exchangeRate)));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '单场极值（港币）',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                GestureDetector(
                  onTap: profitRecord.isNotEmpty
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecordEditPage(
                                  existingRecord: profitRecord.first),
                            ),
                          );
                        }
                      : null,
                  child: Column(
                    children: [
                      const Text('最大盈利',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted)),
                      const SizedBox(height: 6),
                      Text(
                        '+${maxProfit.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.win,
                          fontFeatures: AppColors.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey.shade100),
                GestureDetector(
                  onTap: lossRecord.isNotEmpty
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecordEditPage(
                                  existingRecord: lossRecord.first),
                            ),
                          );
                        }
                      : null,
                  child: Column(
                    children: [
                      const Text('最大亏损',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted)),
                      const SizedBox(height: 6),
                      Text(
                        '-${maxLoss.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.loss,
                          fontFeatures: AppColors.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationStats(
      PokerProvider provider, List<PokerRecord> records) {
    final locationStats = provider.profitByLocation(records);
    if (locationStats.isEmpty) return const SizedBox.shrink();

    final sortedEntries = locationStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '各场地盈亏（港币）',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...sortedEntries.map((entry) {
              final isPositive = entry.value >= 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 14)),
                    Text(
                      '${isPositive ? '+' : ''}${entry.value.toStringAsFixed(0)} HKD',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isPositive ? AppColors.win : AppColors.loss,
                        fontFeatures: AppColors.tabular,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
