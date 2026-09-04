import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// 全 App 统一的莫兰迪奶奶灰顶栏（暖深灰字 + 底部极浅灰线）
///
/// 2026-08 用户拍板：灰调顶栏，绿降级为点缀色（FAB/按钮/盈亏数字）。
/// 主页面标题左对齐，子页面默认居中。
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool centerTitle;
  final Widget? leading;

  const AppAppBar({
    super.key,
    required this.title,
    this.centerTitle = true,
    this.leading,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      centerTitle: centerTitle,
      elevation: 0,
      backgroundColor: AppColors.barTop,
      foregroundColor: AppColors.barText,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.barText,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.barLine),
      ),
    );
  }
}
