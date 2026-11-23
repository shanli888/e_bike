import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/models/command_result.dart';
import 'package:bike_computer/services/ble_service.dart';
import 'package:bike_computer/services/lvbu_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('缺少构建期 IMEI 时助力命令返回失败而不是抛异常', () async {
    // 普通 flutter test 不注入 --dart-define，motorImei 为空。
    if (LvbuProtocol.validImei(LvbuProtocol.motorImei)) {
      // 若测试环境显式注入了 IMEI，这条防呆用例不适用。
      return;
    }

    final ble = BleService();
    expect(await ble.setAssistMode(AssistMode.manual),
        CommandResult.writeFailed);
    expect(await ble.setAssistPercent(50), CommandResult.writeFailed);
    expect(await ble.stopAssist(), CommandResult.writeFailed);

    // 告警只记录一次，避免连续操作刷屏。
    final warnings = ble.logs
        .where((log) => log.source.contains('未配置有效的电机 IMEI'))
        .toList();
    expect(warnings, hasLength(1));
    expect(warnings.first.source, contains('local_config.json'));
  });
}
