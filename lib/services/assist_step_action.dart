import '../models/command_result.dart';
import 'assist_step_settings.dart';
import 'ble_service.dart';

/// 手动模式「+ / -」按钮与 BR80 闪控「上 / 下」键共用的助力步进动作。
///
/// 两条入口都走这里，保证使用同一份步进设置、同样的 0~99 夹取和同一条
/// `stepAssistPercent` 命令。[direction] 为 +1（加 / 上键）或 -1（减 / 下键）。
///
/// 返回 [CommandResult.atLimit] 表示已经到边界，本次没有向设备下发。
Future<CommandResult> applyAssistStep(
  BleService ble,
  int direction,
  int step,
) async {
  final magnitude = AssistStepSettings.clampStep(step);
  final target = assistStepTarget(ble.assistPercent, direction, magnitude);
  if (target == ble.assistPercent) return CommandResult.atLimit;
  return ble.stepAssistPercent(direction < 0 ? -magnitude : magnitude);
}
