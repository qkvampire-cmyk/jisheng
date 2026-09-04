import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/exchange_record.dart';
import '../providers/exchange_provider.dart';
import '../models/time_range.dart';
import '../theme/app_colors.dart';
import '../widgets/app_appbar.dart';

class ExchangeListPage extends StatefulWidget {
  const ExchangeListPage({super.key});

  @override
  State<ExchangeListPage> createState() => _ExchangeListPageState();
}

class _ExchangeListPageState extends State<ExchangeListPage> {
  TimeRangeSelection _timeRange = const TimeRangeSelection();

  List<ExchangeRecord> get _filteredRecords {
    final provider = context.read<ExchangeProvider>();
    final now = DateTime.now();
    switch (_timeRange.type) {
      case TimeRangeType.all:
        return provider.records;
      case TimeRangeType.thisMonth:
        return provider.records
            .where((r) =>
                r.createTime.year == now.year &&
                r.createTime.month == now.month)
            .toList();
      case TimeRangeType.thisYear:
        return provider.records
            .where((r) => r.createTime.year == now.year)
            .toList();
      case TimeRangeType.last7Days:
        {
          final cutoff = now.subtract(const Duration(days: 7));
          return provider.records
              .where((r) => r.createTime.isAfter(cutoff))
              .toList();
        }
      case TimeRangeType.last30Days:
        {
          final cutoff = now.subtract(const Duration(days: 30));
          return provider.records
              .where((r) => r.createTime.isAfter(cutoff))
              .toList();
        }
      case TimeRangeType.custom:
        {
          if (_timeRange.customStart == null || _timeRange.customEnd == null) {
            return provider.records;
          }
          return provider.records
              .where((r) =>
                  r.createTime.isAfter(_timeRange.customStart!) &&
                  r.createTime.isBefore(
                      _timeRange.customEnd!.add(const Duration(days: 1))))
              .toList();
        }
      case TimeRangeType.trip:
        return provider.records; // 兑换流水无行程概念，不过滤
    }
  }

  Future<void> _showEditDialog({ExchangeRecord? existing}) async {
    final result = await showDialog<ExchangeRecord>(
      context: context,
      builder: (ctx) => _ExchangeRecordDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final provider = context.read<ExchangeProvider>();
    if (existing == null) {
      await provider.addRecord(result);
    } else {
      await provider.updateRecord(result);
    }
  }

  Future<void> _confirmDelete(ExchangeRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这条兑换记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && record.id != null && mounted) {
      await context.read<ExchangeProvider>().deleteRecord(record.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExchangeProvider>();
    final records = _filteredRecords;

    return Scaffold(
      appBar: const AppAppBar(title: '港币存取兑换记录'),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : records.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _ExchangeCard(
                            record: records[index],
                            onTap: () =>
                                _showEditDialog(existing: records[index]),
                            onLongPress: () => _confirmDelete(records[index]),
                          );
                        },
                      ),
          ),
          if (records.isNotEmpty) _buildBottomSummary(provider, records),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 46,
        height: 46,
        child: FloatingActionButton(
          onPressed: () => _showEditDialog(),
          child: const Icon(Icons.add, size: 22),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(color: AppColors.surfaceTint),
      child: Row(
        children: [
          const Text('筛选：', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _timeRange.type.name,
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
                    initialDateRange:
                        (_timeRange.type == TimeRangeType.custom &&
                                _timeRange.customStart != null &&
                                _timeRange.customEnd != null)
                            ? DateTimeRange(
                                start: _timeRange.customStart!,
                                end: _timeRange.customEnd!)
                            : null,
                  );
                  if (picked != null) {
                    setState(() {
                      _timeRange = TimeRangeSelection(
                        type: TimeRangeType.custom,
                        customStart: picked.start,
                        customEnd: picked.end,
                      );
                    });
                  }
                  return;
                }
                final type =
                    TimeRangeType.values.firstWhere((t) => t.name == v!);
                setState(() => _timeRange = TimeRangeSelection(type: type));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 64, color: AppColors.emptyIcon),
          const SizedBox(height: 16),
          const Text('暂无兑换记录',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('点击右下角 + 号添加记录',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBottomSummary(
      ExchangeProvider provider, List<ExchangeRecord> records) {
    final totalHkd = provider.totalHkd(records);
    final totalCny = provider.totalCny(records);
    final totalFee = provider.totalFee(records);
    final avgRate = provider.averageRate(records);
    final pending = provider.pendingCount(records);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${records.length} 笔    取现 ${_fmt(totalHkd)} HKD${totalFee > 0 ? '    手续费 ${_fmt(totalFee)} HKD' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            '到账 ${_fmt(totalCny, decimals: 2)} CNY',
            style: TextStyle(fontSize: 13, color: AppColors.win),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                '平均汇率  ${avgRate.toStringAsFixed(4)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: avgRate >= 0.85 ? AppColors.win : AppColors.loss,
                ),
              ),
              if (pending > 0) ...[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    '$pending 笔待结汇',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade700),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 千分位格式化
  String _fmt(double value, {int decimals = 0}) {
    final fmt =
        NumberFormat(decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}');
    return fmt.format(value);
  }
}

// ========== 单条记录卡片 ==========

class _ExchangeCard extends StatelessWidget {
  final ExchangeRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ExchangeCard({
    required this.record,
    required this.onTap,
    required this.onLongPress,
  });

  String _fmt(double value, {int decimals = 0}) {
    final fmtr =
        NumberFormat(decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}');
    return fmtr.format(value);
  }

  @override
  Widget build(BuildContext context) {
    final isPending = record.bankCny == 0;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：时间 + 备注 + 汇率/待结汇
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(record.createTime),
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    if (record.remark != null && record.remark!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          record.remark!,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          '待结汇',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Text('汇率 ',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                          Text(
                            record.actualRate.toStringAsFixed(4),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: record.actualRate >= 0.85
                                  ? AppColors.win
                                  : AppColors.loss,
                            ),
                          ),
                          if (record.feeHkd > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '手续费 ${_fmt(record.feeHkd)} HKD',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右侧：金额
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_fmt(record.hkdCash)} HKD',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontFeatures: AppColors.tabular,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (isPending)
                    Text(
                      '待结汇',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade400),
                    )
                  else
                    Text(
                      '${_fmt(record.bankCny, decimals: 2)} CNY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.win,
                        fontFeatures: AppColors.tabular,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========== 新增/编辑弹窗 ==========

class _ExchangeRecordDialog extends StatefulWidget {
  final ExchangeRecord? existing;
  const _ExchangeRecordDialog({this.existing});

  @override
  State<_ExchangeRecordDialog> createState() => _ExchangeRecordDialogState();
}

class _ExchangeRecordDialogState extends State<_ExchangeRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hkdController = TextEditingController();
  final _cnyController = TextEditingController();
  final _rateController = TextEditingController();
  final _feeController = TextEditingController();
  final _remarkController = TextEditingController();

  late DateTime _operationTime;
  bool _manualRate = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r != null) {
      _isEditing = true;
      _operationTime = r.createTime;
      _hkdController.text = r.hkdCash.toStringAsFixed(0);
      _cnyController.text = r.bankCny.toStringAsFixed(2);
      _rateController.text = r.actualRate.toStringAsFixed(4);
      _feeController.text = r.feeHkd > 0 ? r.feeHkd.toStringAsFixed(0) : '';
      _remarkController.text = r.remark ?? '';
      _manualRate = true;
    } else {
      _operationTime = DateTime.now();
      _feeController.text = '';
    }
  }

  @override
  void dispose() {
    _hkdController.dispose();
    _cnyController.dispose();
    _rateController.dispose();
    _feeController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _autoCalcRate() {
    if (_manualRate) return;
    final hkd = double.tryParse(_hkdController.text) ?? 0;
    final cny = double.tryParse(_cnyController.text) ?? 0;
    if (hkd > 0 && cny > 0) {
      _rateController.text = (cny / hkd).toStringAsFixed(4);
    } else {
      _rateController.text = '';
    }
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _operationTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_operationTime),
    );
    if (time == null) return;
    setState(() {
      _operationTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final hkd = double.tryParse(_hkdController.text) ?? 0;
    final cny = double.tryParse(_cnyController.text) ?? 0;
    final rate = double.tryParse(_rateController.text) ?? 0;
    final fee = double.tryParse(_feeController.text) ?? 0;

    final record = ExchangeRecord(
      id: widget.existing?.id,
      createTime: _operationTime,
      hkdCash: hkd,
      bankCny: cny,
      actualRate: rate,
      feeHkd: fee,
      remark: _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim(),
    );

    Navigator.pop(context, record);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = !_isEditing;
    return AlertDialog(
      title: Text(isNew ? '新增兑换记录' : '编辑兑换记录'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 操作时间
              _fieldLabel('操作时间'),
              InkWell(
                onTap: _selectDateTime,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(_operationTime),
                        style: const TextStyle(fontSize: 14),
                      ),
                      const Icon(Icons.edit_calendar_outlined, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 取出港币
              _fieldLabel('取出港币（必填）'),
              TextFormField(
                controller: _hkdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '输入港币金额',
                  suffixText: 'HKD',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _autoCalcRate(),
                validator: (v) {
                  if (v == null || v.isEmpty) return '请输入金额';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return '请输入正数';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // 到账人民币（选填，留空为待结汇）
              _fieldLabel('银行卡到账人民币（选填）'),
              TextFormField(
                controller: _cnyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '留空为待结汇',
                  suffixText: 'CNY',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _autoCalcRate(),
              ),
              const SizedBox(height: 14),

              // 实际汇率
              _fieldLabel('本次实际汇率'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rateController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        hintText: '自动计算',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: !_manualRate,
                      style: TextStyle(
                        color: _manualRate
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _manualRate = !_manualRate);
                      if (!_manualRate) _autoCalcRate();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      _manualRate ? '自动' : '手动',
                      style: TextStyle(fontSize: 12, color: AppColors.seed),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 手续费
              _fieldLabel('取现手续费（默认0）'),
              TextFormField(
                controller: _feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '0',
                  suffixText: 'HKD',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final n = double.tryParse(v);
                    if (n == null || n < 0) return '请输入有效数字';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // 备注
              _fieldLabel('备注（选填）'),
              TextFormField(
                controller: _remarkController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: '例：威尼斯人ATM取现',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(isNew ? '保存' : '更新'),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary),
      ),
    );
  }
}
