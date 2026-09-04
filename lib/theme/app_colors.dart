import 'package:flutter/material.dart';

/// 积胜 · 语义色系统
///
/// 品牌主色：赌桌墨绿。文本三层：主 / 次 / 弱。
/// 盈亏双色全局统一，日后调色只改这一个文件。
class AppColors {
  AppColors._();

  /// 品牌种子色：赌桌呢绒墨绿（Material green-900）
  static const seed = Color(0xFF1B5E20);

  // ===== 赌桌氛围（2026-08 方向B：聚光）=====

  /// 墨绿渐变：顶 → 底（AppBar / Hero 卡 / 底部汇总栏共用）
  static const feltTop = Color(0xFF1B5E20);
  static const feltBottom = Color(0xFF13451F);
  static const feltGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [feltTop, feltBottom],
  );

  /// 顶部聚光光斑：模拟赌桌灯打在绿绒布上
  static const feltGlow = RadialGradient(
    center: Alignment(0, -1.7),
    radius: 1.7,
    colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
  );

  /// 浅灰 tint：筛选栏 / 弱化底色（莫兰迪灰调，绿降级为点缀）
  static const surfaceTint = Color(0xFFF5F5F4);

  /// 深底亮色：墨绿底上的盈亏（对比度达标）
  static const winOnDark = Color(0xFF4ADE80);
  static const lossOnDark = Color(0xFFF87171);

  /// 空状态图标色（暖灰，四页空状态统一）
  static const emptyIcon = Color(0xFFB5B0A9);

  /// 筹码图标暖灰外圈
  static const chipOuter = Color(0xFFECE8E2);

  // ===== 莫兰迪奶奶灰（2026-08 用户拍板：顶栏+Hero卡灰调）=====

  /// 顶栏底色（奶奶灰暖调）
  static const barTop = Color(0xFFEDEAE6);

  /// 顶栏文字色（暖深灰）
  static const barText = Color(0xFF3F3A36);

  /// 顶栏底线（极浅暖灰）
  static const barLine = Color(0xFFD8D2CB);

  /// Hero 卡奶奶灰渐变（累计净盈亏）
  static const heroLight = Color(0xFFEDEAE6);
  static const heroDark = Color(0xFFDFD9D1);
  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [heroLight, heroDark],
  );

  /// 盈利色（现代克制绿，不刺眼）
  static const win = Color(0xFF16A34A);

  /// 亏损色
  static const loss = Color(0xFFDC2626);

  /// 主文本：金额、标题、关键数字
  static const textPrimary = Colors.black87;

  /// 次级文本：日期、场地、字段标签
  static const textSecondary = Color(0xFF6B7280);

  /// 弱化文本：换算金额、提示、说明
  static const textMuted = Color(0xFF9CA3AF);

  /// 等宽数字：让一列金额逐位对齐
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}
