import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../providers/poker_provider.dart';
import '../providers/exchange_provider.dart';
import '../utils/excel_exporter.dart';
import '../utils/excel_importer.dart';
import '../theme/app_colors.dart';
import 'exchange_list_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _rateController = TextEditingController();
  bool _exporting = false;
  bool _importing = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<PokerProvider>();
    _rateController.text = provider.exchangeRate.toStringAsFixed(4);
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _saveRate() async {
    final rate = double.tryParse(_rateController.text);
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的汇率')),
      );
      return;
    }
    await context.read<PokerProvider>().setExchangeRate(rate);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('汇率已更新')),
      );
    }
  }

  Future<void> _refreshRate() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    // 链式 fallback：前一个返回 null 就试下一个
    String? rateStr = await _fetchRate(
      'https://api.vatcomply.com/rates?base=HKD',
      (data) => (data['rates']['CNY'] as num).toString(),
    );
    rateStr ??= await _fetchRate(
      'https://open.er-api.com/v6/latest/HKD',
      (data) => (data['rates']['CNY'] as num).toString(),
    );
    rateStr ??= await _fetchRate(
      'https://api.exchangerate-api.com/v4/latest/HKD',
      (data) => (data['rates']['CNY'] as num).toString(),
    );
    rateStr ??= await _fetchRate(
      'https://latest.currency-api.pages.dev/v1/currencies/hkd.json',
      (data) => (data['hkd']['cny'] as num).toString(),
    );

    if (rateStr != null) {
      final rate = double.parse(rateStr);
      if (rate > 0) {
        final displayRate = double.parse(rate.toStringAsFixed(4));
        _rateController.text = displayRate.toStringAsFixed(4);
        // 自动获取 → 自动保存到本地，无需手动点保存
        await context.read<PokerProvider>().setExchangeRate(displayRate);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('实时汇率已更新：1 HKD = $displayRate CNY')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法获取实时汇率，请手动填写')),
        );
      }
    }

    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<String?> _fetchRate(
    String url,
    String Function(Map<String, dynamic>) extractRate,
  ) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return extractRate(data);
    } catch (e) {
      return null;
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      final provider = context.read<PokerProvider>();
      final exProvider = context.read<ExchangeProvider>();
      await ExcelExporter.exportRecords(
        provider.records,
        provider.exchangeRate,
        exchangeRecords: exProvider.records,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已调起分享面板')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    // 非 xlsx 弹窗提示
    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      _showSnackBar('仅支持 Excel 表格 (.xlsx) 导入');
      return;
    }

    final bytes = file.bytes;
    if (bytes == null) {
      _showSnackBar('无法读取文件');
      return;
    }

    setState(() => _importing = true);
    try {
      final provider = context.read<PokerProvider>();
      final exProvider = context.read<ExchangeProvider>();
      final importResult = await ExcelImporter.importFromBytes(
        bytes,
        provider.records,
        existingExchangeRecords: exProvider.records,
      );

      if (!mounted) return;

      if (importResult.errorMessage != null) {
        _showErrorDialog(importResult.errorMessage!);
        return;
      }

      // 批量写入
      if (importResult.newRecords.isNotEmpty) {
        await provider.addRecords(importResult.newRecords);
      }
      if (importResult.newExchangeRecords.isNotEmpty) {
        await exProvider.addRecords(importResult.newExchangeRecords);
      }

      // 显示结果
      _showImportResult(importResult);
    } catch (e) {
      if (mounted) _showErrorDialog('导入异常：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showImportResult(ImportResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultLine(Icons.check_circle, Colors.green, '成功',
                '${result.newRecords.length} 条'),
            if (result.duplicateCount > 0)
              _resultLine(Icons.skip_next, Colors.orange, '跳过重复',
                  '${result.duplicateCount} 条'),
            if (result.newExchangeRecords.isNotEmpty)
              _resultLine(Icons.check_circle, Colors.green, '兑换记录',
                  '${result.newExchangeRecords.length} 条'),
            if (result.exchangeDuplicateCount > 0)
              _resultLine(Icons.skip_next, Colors.orange, '兑换记录跳过重复',
                  '${result.exchangeDuplicateCount} 条'),
            if (result.failedCount > 0)
              _resultLine(Icons.error_outline, Colors.red, '解析失败',
                  '${result.failedCount} 条'),
            if (result.failedCount > 0) ...[
              const SizedBox(height: 12),
              const Text('失败详情：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: result.failedDetails
                      .map((d) => Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 2, horizontal: 8),
                            child: Text(d,
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.loss)),
                          ))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _resultLine(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入失败'),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 汇率设置
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '汇率设置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '1 港币 = ? 人民币',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rateController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '输入汇率',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        onPressed: _isRefreshing ? null : _refreshRate,
                        icon: _isRefreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_outlined),
                        tooltip: '获取实时汇率',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saveRate,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '修改汇率仅变更人民币换算展示结果，港币原始账目数据保持不变，所有历史账目会自动重新换算展示。',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        const SizedBox(height: 16),

        // 数据导出
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导出全部账目为 Excel'),
            subtitle: Text(
              '分享导出文件',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            trailing: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _exporting ? null : _exportExcel,
          ),
        ),
        const SizedBox(height: 16),

        // 数据导入
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导入 Excel 账目'),
            subtitle: Text(
              '仅支持 .xlsx 格式',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            trailing: _importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _importing ? null : _importExcel,
          ),
        ),
        const SizedBox(height: 16),

        // 港币存取兑换记录
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.swap_horiz, color: AppColors.seed),
            title: const Text('港币存取兑换记录'),
            subtitle: const Text(
              '记录取现结汇流水，单独核算汇兑成本',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ExchangeListPage(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // 关于
        const Center(
          child: Text(
            '积胜 · Elite · by VICQ',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}
