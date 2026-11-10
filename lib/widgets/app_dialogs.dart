import 'package:flutter/material.dart';

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

/// 轻提示（SnackBar）
void showAppToast(
  BuildContext context,
  String message, {
  bool error = false,
  bool warning = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error
          ? Colors.red.shade700
          : warning
              ? Colors.orange.shade800
              : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}
