import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/poker_record.dart';
import '../providers/poker_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_appbar.dart';

class RecordEditPage extends StatefulWidget {
  final PokerRecord? existingRecord;

  /// 新增模式下的预填时长（小时）——上桌计时下桌后自动带入
  final double? initialDuration;

  const RecordEditPage({super.key, this.existingRecord, this.initialDuration});

  @override
  State<RecordEditPage> createState() => _RecordEditPageState();
}

class _RecordEditPageState extends State<RecordEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _durationController = TextEditingController();
  final _blindController = TextEditingController();
  final _remarkController = TextEditingController();
  final _locationTextController = TextEditingController();

  late DateTime _recordTime;
  String _selectedLocation = '';
  String _selectedCurrency = 'HKD';
  bool _isProfit = true;
  String _selectedBlind = '';
  bool _defaultsInitialized = false;
  String _selectedTableType = '';
  final _handNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final record = widget.existingRecord;
    if (record != null) {
      _recordTime = record.recordTime;
      _selectedLocation = record.location;
      _selectedCurrency = record.currency;
      _isProfit = record.amount >= 0;
      _amountController.text = record.amount.abs().toStringAsFixed(0);
      _durationController.text = record.duration.toString();
      _selectedBlind = record.blindLevel;
      _blindController.text = record.blindLevel;
      _remarkController.text = record.remark ?? '';
      _selectedTableType = record.tableType ?? '';
      _handNotesController.text = record.handNotes ?? '';
    } else {
      _recordTime = DateTime.now();
      _durationController.text = widget.initialDuration != null
          ? widget.initialDuration!.toStringAsFixed(1)
          : '3.0';
    }
    // 默认值初始化（等一帧确保 Provider 数据就绪）
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaults());
  }

  void _initDefaults() {
    if (!mounted || _defaultsInitialized) return;
    final provider = context.read<PokerProvider>();
    final locations = provider.locations;
    var changed = false;
    if (_selectedLocation.isEmpty && locations.isNotEmpty) {
      // 优先用上次选的地点，没有则默认威尼斯人
      final defaultLoc = provider.lastLocation.isNotEmpty
          ? provider.lastLocation
          : '威尼斯人 (Venetian)';
      _selectedLocation =
          locations.contains(defaultLoc) ? defaultLoc : locations.first;
      changed = true;
    }
    if (_selectedBlind.isEmpty) {
      _selectedBlind = PokerProvider.presetBlinds[0];
      changed = true;
    }
    if (_selectedTableType.isEmpty) {
      final remembered = provider.lastTableType;
      if (remembered.isNotEmpty &&
          PokerRecord.tableTypeOptions.contains(remembered)) {
        _selectedTableType = remembered;
      } else {
        _selectedTableType = PokerRecord.getDefaultTableType(_selectedLocation);
      }
      changed = true;
    }
    if (changed) {
      setState(() {});
    }
    _defaultsInitialized = true;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _durationController.dispose();
    _blindController.dispose();
    _remarkController.dispose();
    _handNotesController.dispose();
    _locationTextController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _recordTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_recordTime),
    );
    if (time == null) return;

    setState(() {
      _recordTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _showAddLocationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增地点'),
        content: TextField(
          controller: _locationTextController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入赌场名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = _locationTextController.text.trim();
              if (name.isNotEmpty) {
                context.read<PokerProvider>().addLocation(name);
                setState(() => _selectedLocation = name);
              }
              _locationTextController.clear();
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择场次地点')),
      );
      return;
    }
    if (_selectedBlind.isEmpty && _blindController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或输入盲注级别')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    final signedAmount = _isProfit ? amount : -amount;
    final duration = double.tryParse(_durationController.text) ?? 0;
    final blind = _blindController.text.trim().isEmpty
        ? _selectedBlind
        : _blindController.text.trim();

    final provider = context.read<PokerProvider>();

    // 计算录入时的离岸人民币金额
    final double? entryCnyAmount;
    if (_selectedCurrency == 'CNY') {
      entryCnyAmount = signedAmount;
    } else {
      entryCnyAmount = signedAmount * provider.exchangeRate;
    }

    final record = PokerRecord(
      id: widget.existingRecord?.id,
      recordTime: _recordTime,
      duration: duration,
      location: _selectedLocation,
      currency: _selectedCurrency,
      amount: signedAmount,
      cnyAmount: entryCnyAmount,
      blindLevel: blind,
      remark: _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim(),
      tableType: _selectedTableType.isNotEmpty ? _selectedTableType : null,
      handNotes: _handNotesController.text.trim().isEmpty
          ? null
          : _handNotesController.text.trim(),
    );

    if (widget.existingRecord == null) {
      await provider.addRecord(record);
      // 记住本次选的地点，下次新增默认用这个
      await provider.setLastLocation(record.location);
      // 记住本次选的桌型
      if (_selectedTableType.isNotEmpty) {
        await provider.setLastTableType(_selectedTableType);
      }
    } else {
      await provider.updateRecord(record);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PokerProvider>();
    final locations = provider.locations;

    return Scaffold(
      appBar: AppAppBar(
        title: widget.existingRecord == null ? '新增记账' : '编辑记录',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 记账时间
            _buildSectionTitle('记账时间'),
            InkWell(
              onTap: _selectDateTime,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border:
                      Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(_recordTime),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Icon(Icons.edit_calendar_outlined, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 对局时长
            _buildSectionTitle('对局时长（小时）'),
            TextFormField(
              controller: _durationController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '例如 3.5',
                border: OutlineInputBorder(),
                suffixText: '小时',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return '请输入时长';
                if (double.tryParse(v) == null) return '请输入有效数字';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 场次地点
            _buildSectionTitle('场次地点'),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedLocation.isEmpty ? null : _selectedLocation,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: locations.map((loc) {
                      return DropdownMenuItem(value: loc, child: Text(loc));
                    }).toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedLocation = v ?? '';
                        // 切换地点时自动更新默认桌型
                        if (_selectedLocation.isNotEmpty) {
                          _selectedTableType = PokerRecord.getDefaultTableType(
                              _selectedLocation);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showAddLocationDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '新增地点',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 币种选择
            _buildSectionTitle('币种'),
            _buildPillSegment(
              leftLabel: '港币 HKD',
              rightLabel: '人民币 CNY',
              leftSelected: _selectedCurrency == 'HKD',
              rightSelected: _selectedCurrency == 'CNY',
              onLeft: () => setState(() => _selectedCurrency = 'HKD'),
              onRight: () => setState(() => _selectedCurrency = 'CNY'),
              fillColor: AppColors.seed,
            ),
            const SizedBox(height: 8),

            // 输赢状态
            _buildSectionTitle('输赢状态'),
            _buildPillSegment(
              leftLabel: '盈利',
              rightLabel: '亏损',
              leftSelected: _isProfit,
              rightSelected: !_isProfit,
              onLeft: () => setState(() => _isProfit = true),
              onRight: () => setState(() => _isProfit = false),
              fillColor: AppColors.win,
              rightFillColor: AppColors.loss,
            ),
            const SizedBox(height: 8),

            // 盈亏金额
            _buildSectionTitle('盈亏金额'),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: TextStyle(
                color: _isProfit ? AppColors.win : AppColors.loss,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              decoration: InputDecoration(
                hintText: '输入金额',
                border: const OutlineInputBorder(),
                prefixText: _isProfit ? '+ ' : '- ',
                prefixStyle: TextStyle(
                  color: _isProfit ? AppColors.win : AppColors.loss,
                  fontWeight: FontWeight.w600,
                ),
                suffixText: _selectedCurrency == 'HKD' ? 'HKD' : 'CNY',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return '请输入金额';
                if (double.tryParse(v) == null) return '请输入有效数字';
                return null;
              },
            ),
            const SizedBox(height: 8),
            // 换算显示
            _buildConvertedAmount(provider.exchangeRate),
            const SizedBox(height: 16),

            // 盲注级别
            _buildSectionTitle('盲注级别（必填）'),
            DropdownButtonFormField<String>(
              value: _selectedBlind,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: PokerProvider.presetBlinds.map((b) {
                return DropdownMenuItem(value: b, child: Text(b));
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedBlind = v ?? '';
                  _blindController.text = v ?? '';
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _blindController,
              decoration: InputDecoration(
                hintText: '或手动输入自定义盲注，如 25/50',
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceTint,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // 备注
            _buildSectionTitle('备注（选填）'),
            TextFormField(
              controller: _remarkController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '记录额外信息...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 牌局详情（折叠面板）
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  '牌局详情（选填）',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                leading: Icon(Icons.sports_esports_outlined,
                    size: 20, color: Colors.grey.shade500),
                children: [
                  // 桌型
                  _buildSectionTitle('桌型'),
                  DropdownButtonFormField<String>(
                    value:
                        _selectedTableType.isEmpty ? null : _selectedTableType,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: PokerRecord.tableTypeOptions.map((t) {
                      return DropdownMenuItem(value: t, child: Text(t));
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => _selectedTableType = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  // 牌谱备注
                  _buildSectionTitle('本局关键手牌 / 牌谱'),
                  TextFormField(
                    controller: _handNotesController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: '记录本局关键手牌、操作思路...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(12),
                      hintStyle:
                          TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 保存按钮
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saveRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  widget.existingRecord == null ? '保存记录' : '更新记录',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

            // 删除按钮（编辑模式）
            if (widget.existingRecord != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('确认删除'),
                        content: const Text('删除后无法恢复，确定要删除这条记录吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('删除',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && widget.existingRecord?.id != null) {
                      if (!mounted) return;
                      await context
                          .read<PokerProvider>()
                          .deleteRecord(widget.existingRecord!.id!);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('删除记录'),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// 药丸形分段选择器（选中态语义色填充）
  Widget _buildPillSegment({
    required String leftLabel,
    required String rightLabel,
    required bool leftSelected,
    required bool rightSelected,
    required VoidCallback onLeft,
    required VoidCallback onRight,
    required Color fillColor,
    Color? rightFillColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPill(leftLabel, leftSelected, fillColor, onLeft),
          ),
          Expanded(
            child: _buildPill(rightLabel, rightSelected,
                rightFillColor ?? fillColor, onRight),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(
      String label, bool selected, Color fill, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? fill : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildConvertedAmount(double rate) {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final signedAmount = _isProfit ? amount : -amount;
    String convertedText;

    if (_selectedCurrency == 'HKD') {
      final cny = PokerRecord.convertAmount(signedAmount, 'HKD', 'CNY', rate);
      convertedText = '≈ ${cny.toStringAsFixed(2)} CNY';
    } else {
      final hkd = PokerRecord.convertAmount(signedAmount, 'CNY', 'HKD', rate);
      convertedText = '≈ ${hkd.toStringAsFixed(2)} HKD';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        convertedText,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
