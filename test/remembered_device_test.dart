import 'package:bike_computer/models/assist_mode.dart';
import 'package:bike_computer/services/remembered_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('设备和已确认模式按设备保存，重启后可读取', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RememberedDeviceStore();
    final time = DateTime(2026, 11, 9, 10, 30);
    await store.saveDevice(RememberedDevice(id: 'device-a', name: 'LvBu motor', connectedAt: time));
    await store.saveMode('device-a', AssistMode.manual);
    final loaded = await RememberedDeviceStore().loadDevice();
    expect(loaded?.id, 'device-a');
    expect(loaded?.name, 'LvBu motor');
    expect(loaded?.connectedAt, time);
    expect(await store.loadMode('device-a'), AssistMode.manual);
    expect(await store.loadMode('device-b'), isNull);
  });

  test('损坏的设备记录不会导致启动失败', () async {
    SharedPreferences.setMockInitialValues({'last_ble_device_v1': 'broken'});
    expect(await RememberedDeviceStore().loadDevice(), isNull);
  });
}
