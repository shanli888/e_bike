import 'package:flutter/material.dart';

/// 全局 ScaffoldMessenger：服务层（闪控按键回调、助力调速调度器）没有
/// BuildContext，也能把结果弹成 toast。挂在 MaterialApp 上即可。
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 统一的提示弹窗：标题 + 说明 + 可选主操作
Future<void> showAppDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? primaryLabel,
  VoidCallback? onPrimary,
  String secondaryLabel = '知道了',
  IconData? icon,
  Color color = Colors.orange,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF252540),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: icon == null ? null : Icon(icon, color: color, size: 32),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17)),
      content: Text(
        message,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            secondaryLabel,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
        if (primaryLabel != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onPrimary?.call();
            },
            child: Text(primaryLabel, style: TextStyle(color: color)),
          ),
      ],
    ),
  );
}

SnackBar _buildSnackBar(
  String message, {
  required bool error,
  required bool warning,
  required Duration duration,
}) {
  return SnackBar(
    content: Text(message),
    backgroundColor: error
        ? Colors.red.shade700
        : warning
            ? Colors.orange.shade800
            : Colors.green.shade700,
    behavior: SnackBarBehavior.floating,
    duration: duration,
  );
}

/// 轻提示（SnackBar）：页面内调用，带 BuildContext。
/// 连续操作时直接替换当前 toast，避免提示排队堆积。
void showAppToast(
  BuildContext context,
  String message, {
  bool error = false,
  bool warning = false,
  Duration duration = const Duration(seconds: 2),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(_buildSnackBar(
    message,
    error: error,
    warning: warning,
    duration: duration,
  ));
}

/// 服务层用的轻提示：没有 context 时（例如 widget 测试）安全跳过。
void showGlobalToast(
  String message, {
  bool error = false,
  bool warning = false,
  Duration duration = const Duration(seconds: 2),
  bool replace = true,
}) {
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  if (replace) messenger.removeCurrentSnackBar();
  messenger.showSnackBar(_buildSnackBar(
    message,
    error: error,
    warning: warning,
    duration: duration,
  ));
}
