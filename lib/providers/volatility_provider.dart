import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 波动分析参数设置（手数/小时 + 真实赢率 μ 自动/手动）
class VolatilityProvider extends ChangeNotifier {
  double _handsPerHour = 25; // 现场每小时手数
  bool _manualMu = false; // false=自动估计，true=手动填值
  double _manualMuValue = 30; // 手动 μ（bb/100）

  double get handsPerHour => _handsPerHour;
  bool get manualMu => _manualMu;
  double get manualMuValue => _manualMuValue;

  /// 生效的 μ：手动模式返回手动值，否则 null（由计算模块自动估计）
  double? get effectiveManualMu => _manualMu ? _manualMuValue : null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _handsPerHour = prefs.getDouble('vol_hands_per_hour') ?? 25;
    _manualMu = prefs.getBool('vol_mu_manual') ?? false;
    _manualMuValue = prefs.getDouble('vol_mu_value') ?? 30;
    notifyListeners();
  }

  Future<void> setHandsPerHour(double v) async {
    _handsPerHour = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('vol_hands_per_hour', v);
    notifyListeners();
  }

  Future<void> setManualMu(bool v) async {
    _manualMu = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vol_mu_manual', v);
    notifyListeners();
  }

  Future<void> setManualMuValue(double v) async {
    _manualMuValue = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('vol_mu_value', v);
    notifyListeners();
  }
}
