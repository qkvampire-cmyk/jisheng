import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/poker_record.dart';
import '../providers/poker_provider.dart';
import '../theme/app_colors.dart';
import 'record_edit_page.dart';

/// 牌谱复盘页 — 只展示有牌谱备注的记录
class HandHistoryPage extends StatelessWidget {
  const HandHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PokerProvider>();
    final handRecords = provider.records
        .where((r) => r.handNotes != null && r.handNotes!.isNotEmpty)
        .toList();

    if (handRecords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildChipIcon(),
            const SizedBox(height: 16),
            const Text('暂无牌谱记录',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('记账时展开「牌局详情」即可记录',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecordEditPage(),
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('记一局'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.seed,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: handRecords.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final record = handRecords[index];
        return _HandCard(record: record);
      },
    );
  }

  /// 自绘筹码：浅绿外圈 + 墨绿滚边 + 墨绿内圈 + 白色芯
  Widget _buildChipIcon() {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.chipOuter,
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.seed, width: 3),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.seed,
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HandCard extends StatelessWidget {
  final PokerRecord record;

  const _HandCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PokerProvider>();
    final rate = provider.exchangeRate;
    final isProfit = record.isProfit;
    final color = isProfit ? AppColors.win : AppColors.loss;

    final hkd = record.getAmountIn('HKD', rate);
    final cny = record.displayCny(rate);

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecordEditPage(existingRecord: record),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：时间 + 金额
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm')
                            .format(record.recordTime),
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${record.location} · ${record.blindLevel}${record.tableType != null ? ' · ${record.tableType}' : ''}',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isProfit ? '+' : '-'}${hkd.abs().toStringAsFixed(0)} HKD',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: color,
                          fontFeatures: AppColors.tabular,
                        ),
                      ),
                      Text(
                        '${isProfit ? '+' : '-'}${cny.abs().toStringAsFixed(0)} CNY',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            fontFeatures: AppColors.tabular),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 牌谱备注
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  record.handNotes!,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
