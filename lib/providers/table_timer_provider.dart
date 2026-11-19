import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上桌计时器（支持中途暂停 / 继续）
///
/// 三个状态持久化到 SharedPreferences：
///  - 上桌时间戳（start）
///  - 暂停开始时间戳（pausedAt，null = 正在计时）
///  - 已累计暂停毫秒（pausedTotal）
/// APP 退后台、被系统杀掉、甚至重启后，计时/暂停状态都能恢复，不丢牌局时长。
///
/// 时长口径 = 净工时：澳门现金局 MISS 离桌不计盲（回桌补盲即可），
/// 所以离桌那段时间既没有手数也没有盲注成本，应从工时里扣掉。
class TableTimerProvider extends ChangeNotifier {
  static const _kStart = 'table_timer_start_ms';
  static const _kPausedAt = 'table_timer_paused_at_ms';
  static const _kPausedTotal = 'table_timer_paused_total_ms';

  /// 单段暂停短于此值视为误触，不计入休息
  static const _minPause = Duration(minutes: 1);

  DateTime? _startTime;
  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;

  /// 是否在上桌中（含暂停状态）
  bool get isRunning => _startTime != null;

  /// 是否处于暂停（休息）状态
  bool get isPaused => _pausedAt != null;

  /// 是否正在走秒（上桌且未暂停）——ticker 只在此时运行
  bool get isTicking => _startTime != null && _pausedAt == null;

  /// 上桌时间（未计时时为 null）
  DateTime? get startTime => _startTime;

  /// 已累计休息时长（含当前这段尚未结束的暂停）
  Duration get restTotal {
    final p = _pausedAt;
    return _pausedTotal +
        (p == null ? Duration.zero : DateTime.now().difference(p));
  }

  /// 净工时（扣除休息；暂停期间冻结不再增长）
  Duration get elapsed {
    final s = _startTime;
    if (s == null) return Duration.zero;
    final now = _pausedAt ?? DateTime.now();
    final net = now.difference(s) - _pausedTotal;
    return net.isNegative ? Duration.zero : net;
  }

  /// 启动 APP 时恢复计时/暂停状态
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kStart);
    if (ms == null || ms <= 0) return;
    _startTime = DateTime.fromMillisecondsSinceEpoch(ms);
    _pausedTotal = Duration(milliseconds: prefs.getInt(_kPausedTotal) ?? 0);
    final pausedMs = prefs.getInt(_kPausedAt);
    if (pausedMs != null && pausedMs > 0) {
      _pausedAt = DateTime.fromMillisecondsSinceEpoch(pausedMs);
    }
    notifyListeners();
  }

  /// 开始计时（上桌）
  Future<void> start() async {
    _startTime = DateTime.now();
    _pausedAt = null;
    _pausedTotal = Duration.zero;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStart, _startTime!.millisecondsSinceEpoch);
    await prefs.remove(_kPausedAt);
    await prefs.remove(_kPausedTotal);
    notifyListeners();
  }

  /// 暂停（离桌休息）
  Future<void> pause() async {
    if (_startTime == null || _pausedAt != null) return;
    _pausedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPausedAt, _pausedAt!.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// 继续（回桌）
  Future<void> resume() async {
    final p = _pausedAt;
    if (p == null) return;
    final seg = DateTime.now().difference(p);
    if (seg >= _minPause) _pausedTotal += seg; // 不足 1 分钟的误触不计
    _pausedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPausedAt);
    await prefs.setInt(_kPausedTotal, _pausedTotal.inMilliseconds);
    notifyListeners();
  }

  /// 结束计时（下桌），返回本次净工时，并清除计时状态
  Future<Duration> stop() async {
    final d = elapsed;
    _reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStart);
    await prefs.remove(_kPausedAt);
    await prefs.remove(_kPausedTotal);
    notifyListeners();
    return d;
  }

  /// 取消本次计时（误触兜底）
  Future<void> cancel() async {
    _reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStart);
    await prefs.remove(_kPausedAt);
    await prefs.remove(_kPausedTotal);
    notifyListeners();
  }

  void _reset() {
    _startTime = null;
    _pausedAt = null;
    _pausedTotal = Duration.zero;
  }
}
