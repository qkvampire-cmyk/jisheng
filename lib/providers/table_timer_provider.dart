import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上桌计时器
///
/// 开始时间持久化到 SharedPreferences：
/// APP 退后台、被系统杀掉、甚至重启后，计时状态都能恢复，不丢牌局时长。
class TableTimerProvider extends ChangeNotifier {
  static const _prefsKey = 'table_timer_start_ms';

  DateTime? _startTime;

  /// 是否正在计时
  bool get isRunning => _startTime != null;

  /// 上桌时间（未计时时为 null）
  DateTime? get startTime => _startTime;

  /// 已计时时长（未计时时为 zero）
  Duration get elapsed {
    final s = _startTime;
    if (s == null) return Duration.zero;
    return DateTime.now().difference(s);
  }

  /// 启动 APP 时恢复计时状态
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefsKey);
    if (ms != null && ms > 0) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(ms);
      notifyListeners();
    }
  }

  /// 开始计时（上桌）
  Future<void> start() async {
    _startTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, _startTime!.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// 结束计时（下桌），返回本次对局时长，并清除计时状态
  Future<Duration> stop() async {
    final d = elapsed;
    _startTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
    return d;
  }

  /// 取消本次计时（误触兜底）
  Future<void> cancel() async {
    _startTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}
