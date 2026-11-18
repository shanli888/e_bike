# 电动助力控制器 App（bike_computer）

基于 Flutter 的自行车电助力电机控制 App（LVBU / WePower 白标控制器，逆向精简版）。
纯离线、无登录：通过蓝牙读取原厂协议支持的骑行数据，支持 GPS 测速及协议调试；「设备」页可单独扫描并连接 BR80 闪控，上/下键联动手动助力调速（1 秒防抖），主键可立即停止助力。助力设置、设备重启和陀螺仪校准需实机验证。

当前版本：`1.6.57+68`（2026-11-16）。版本说明见 [CHANGELOG.md](CHANGELOG.md)，应用内可在「设置 → 关于」查看。

### 本地电机标识配置

LVBU 蓝牙业务命令需要电机 IMEI。创建未纳入版本控制的 `local_config.json`，内容格式为 `{"LVBU_MOTOR_IMEI":"15位电机IMEI"}`，并执行 `flutter build apk --release --dart-define-from-file=local_config.json`。未配置有效 IMEI 时不能使用 LVBU 查询和设置。该标识仍会编译进 APK，个人 APK 和原厂抓包不要公开分享。

## 功能

| 页面 | 内容 |
| --- | --- |
| 码表 | 只读速度（蓝牙/GPS）、本次里程、平均/最高速度、蓝牙车体倾角、电压及估算电量、控制器温度；实验性 C4 模式设置 |
| 设备 | BLE 扫描（默认只显示名称匹配码表前缀的设备，可切换「显示全部蓝牙设备」）、连接/断开、信号强度 |
| 设置 | 速度来源（蓝牙 / GPS）、手机本地 CSC 轮径（不写电机）、陀螺仪角度及爬坡参数只读显示、设备详情、协议调试和关于；设备重启与校准需实机验证 |
| 蓝牙调试 | 收发原始报文（十六进制 + 时间戳）、手动下发任意十六进制命令、清空日志 |

页面切换用**底部导航**（码表 / 设备 / 设置），顶部只保留一条细标题栏，把纵向空间留给内容。

### 异常提示与指令确认

所有"下发命令"都改为**等待设备回包**（`BleService.sendCommandAwait`，默认 2 秒超时），
结果分五类（`CommandResult`）：

| 结果 | 判定 | 界面反馈 |
| --- | --- | --- |
| `ok` | 收到 `cmd` 或 `cmd\|0x80` 回包，且首字节为 0x00/0x01 或无数据 | 绿色提示「设备已确认」，状态更新 |
| `noResponse` | 2 秒内没有回包 | 橙色提示「已发送，未收到设备确认」，不更新设备状态 |
| `deviceError` | 回包内容表示失败 | 红色提示「设备返回失败」 |
| `writeFailed` | 写入特征抛异常 | 弹窗说明 |
| `notConnected` / `bluetoothOff` | 没连设备 / 蓝牙没开 | 弹窗 + 「去连接」/「去开启」 |

等待期间助力面板右上角显示「等待确认」转圈，期间不响应新的指令点击。**助力控制命令仍需在本应用完整实车验证；闪控主键的停止助力走原厂 A5 0% 通道，请让车轮离地测试，并保留车辆原有控制装置作为兜底。**

各类异常都会弹窗，而不是只打日志：

- **蓝牙未开启**：进设备页就弹「蓝牙未开启」，可直接「去开启」；部分机型（华为/荣耀）不允许 App 直接开蓝牙，
  会自动退回「去设置」——通过 `MainActivity` 的 MethodChannel 打开系统蓝牙设置页
- **连接失败**：弹窗说明可能原因（未开机/被占用/距离远）并提供「重试」
- **无法开始扫描**：权限被拒时弹窗，可跳系统设置
- **连接断开 / 蓝牙被关闭**：主界面监听状态变化，掉线时弹窗提醒，可一键跳到设备页
- **GPS 不可用**：定位关闭或权限被拒时，设置页显示原因并提供「重试定位」

### 速度来源

设置 → 显示 → 速度来源：

- **蓝牙**：用控制器上报的速度（默认）
- **GPS**：用手机定位算速度，同时计算 AVG / MAX / 本次里程；未定位、定位服务关闭或权限被拒时会提示原因并可「重试定位」
- 选择会保存在本地（`shared_preferences`），下次启动自动恢复；GPS 只在该模式下开启定位，切回蓝牙立即停止
- 码表页速度右下角的角标会显示当前来源（`蓝牙` / `GPS`）

### BR80 闪控

在「设备」页扫描并连接名称包含 `BlingRemote` 或 `BR80` 的闪控；它与电机分别连接。闪控连接成功后首页助力栏图标为绿色，否则为灰色，电量未读取时显示 `--`。

- **上/下键**：按设置页的「加减步进」增减助力（0–99%）。每次按键先本地移动首页助力滑杆，**1 秒防抖**后只把最后一次按键的最终值下发一次，连续调速不会每按一次就写一条 BLE 指令。写入沿用 A5 确认与冷却保护，需先连接控制器并保持手动模式。
- **主键（home）**：不参与防抖，按下立即下发原厂协议的停止助力命令 `A5F<电机IMEI>00`（即手动助力设为 0%），同时取消尚未下发的调速指令。旧 AA55 / `0x22` 帧来自误用的 APK 推测，已停用。
- 手动拖滑杆或点首页 `+ / -` 时，会取消仍在倒计时的闪控调速，避免随后覆盖用户刚设的值。
- 设备页可断开闪控。实车使用前请先让车轮离地验证按键调速与停止动作。

### 助力控制

- **模式**：通勤 / 运动 / 爬坡 / 休闲 / 手动（对应逆向文档的 commute / exercise / climbing / leisure / manual）
- **等级**：1~5 档，点数字直接选档，`+` / `−` 逐档调节
- **手动模式**：切换到手动态后，档位条变成 **0~100% 滑块**（5% 一档），可拖动或点按设定；
  `+` / `−` 每次 5%，右上角实时显示百分比
- **停止**：一键停止助力（等级与百分比都归 0）
- 所有操作都会即时反馈：成功绿色提示、失败红色提示；日志可在「蓝牙调试」里核对实际下发的字节

## 目录结构

```
lib/
  main.dart                     入口 + 三个 Tab（DefaultTabController）
  models/bike_data.dart         骑行数据模型
  models/device_settings.dart   设备设置模型
  models/frame_log.dart         调试日志条目
  models/assist_mode.dart       助力模式枚举（名称/模式码/图标）
  models/command_result.dart    指令结果（已确认/未回包/失败…）与提示文案
  services/ble_constants.dart   GATT UUID / 设备名前缀
  services/ble_commands.dart    命令帧构造（帧头/长度/命令字/校验）
  services/gps_service.dart     GPS 测速（速度/极速/均速/里程，可持久化开关）
  services/system_settings.dart 调系统蓝牙设置页（MethodChannel）
  services/ble_service.dart     核心蓝牙服务（扫描、连接、CSC 解析、助力控制、回包确认、调试日志）
  widgets/app_dialogs.dart      统一弹窗与轻提示
  screens/dashboard_screen.dart 码表 + 助力控制
  screens/device_screen.dart    设备扫描连接
  screens/settings_screen.dart  设置页面
  screens/debug_screen.dart     协议调试（报文查看 + 手动发送）
android/                        Android 工程（minSdk 24，targetSdk 36）
ios/                            iOS 工程（已配置蓝牙用途描述）
test/                           模型 + 命令帧单元测试
tools/make_icon.py              生成各密度启动图标
```

## 蓝牙协议

**注意：此前误用其他 App 的 APK；以下 AA 55、WePower JSON/二进制候选协议不能用于此设备。实际原厂包是 `bt_20240407115023.apk`（`wang.lvbu.mobile`）。只读功能已部分实机验证；C4 模式设置与 A5 手动百分比（含停止助力用的 0%）仍需实车验证，请保留车辆原有控制装置。**

依据《蓝牙协议逆向文档》（项目根目录 `蓝牙协议逆向文档.md`）：

- 当前实现优先从 `FFE1` 写入，并订阅 `FFE1` 及其他可通知的私有特征。
- 原厂 App 对不同布局使用不同通道，`FFE2` 也可能是控制通知通道；具体以实机抓包确认。
- 命令帧：`AA 55 <len> <cmd> <data...> <checksum>`
  - `len` = 1（命令字）+ 数据长度
  - `checksum` = 前面所有字节求和的低 8 位取反

| 功能 | 命令字 | 帧示例 | 状态 |
| --- | --- | --- | --- |
| 重启设备 | `0x01` | `AA 55 01 01 FE` | 推测 |
| 轮胎尺寸 27.5" | `0x02` | `AA 55 04 02 1C 02 BB 21` | 推测 |
| 查询陀螺仪 | `0x10` | `AA 55 01 10 EF` | 推测 |
| 校准陀螺仪 | `0x11` | `AA 55 01 11 EE` | 推测 |
| 助力等级 0~5 | `0x20` | `AA 55 02 20 03 DB`（3 档） | 推测 |
| 助力模式 | `0x21` | `AA 55 02 21 03 DA`（爬坡） | 推测（通勤 1/运动 2/爬坡 3/休闲 4/手动 5） |
| 停止助力 | `0x22` | `AA 55 02 22 00 DC` | 推测 |
| 手动助力百分比 | `0x23` | `AA 55 02 23 23 B8`（35%） | 推测，手动模式专用 |
| 限速 25km/h | `0x30` | `AA 55 02 30 19 B5` | 已实现构造，未接 UI |
| 头灯开 | `0x31` | `AA 55 02 31 01 CC` | 已实现构造，未接 UI |

> ⚠️ 这张表是**误用 APK 时期的历史推测记录，全部未接实车且已停用**（`BleService.sendCommandAwait` 不会下发）。
> 原厂 LVBU 3.4.0 实际写 FFE1 的是 `命令码 + F + 15位电机IMEI + 数据`，例如手动助力 `A5F<IMEI>51`、
> 停止助力 `A5F<IMEI>00`。请以 `lib/services/lvbu_mode.dart` 与 `docs/LVBU_3.4.0_协议分析.md` 为准。

私有帧的字段偏移同样是推测值（见 `ble_service.dart` 的 `_parseDataFrame`），其中：

- 电量：`payload[15]`，百分比
- 电压：`payload[25..26]`，uint16 小端、单位 0.1V（`0x01E2` → 48.2V），未上报时界面显示「电压 --」

同时兼容标准 CSC（`0x1816 / 0x2A5B`）：用轮圈累计值与事件时间算瞬时速度和里程，
CSC 轮径取设置页的手机本地设置，周长按直径乘 π 估算；当前 LVBU BF 速度来自电机，不使用此轮径。本车没有踏频传感器，曲柄部分不解析、界面也不显示。

## 本机构建环境

| 组件 | 版本 / 位置 |
| --- | --- |
| Flutter | 3.47.9 stable（Dart 3.13.7）· `E:\install\flutter` |
| JDK | Microsoft OpenJDK 17.0.13 · `E:\install\jdk17\jdk-17.0.13+11` |
| Android SDK | Platform 36 / Build-Tools 36.0.0 · `E:\install\androidsdk` |
| Gradle | 9.3.1（wrapper 自动下载） |

`JAVA_HOME` / `ANDROID_HOME` / `Path` 已写入用户环境变量。`E:\flutter` 下另有一份 SDK，
当前 `Path` 指向 `E:\install\flutter`，两者选其一即可。

## 构建 / 安装

```powershell
cd E:\dswork\bike_computer
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=local_config.json
# 产物：build\app\outputs\flutter-apk\app-release.apk
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

调试（热重载）：`flutter run -d <设备序列号>`。

## 签名

release 签名配置保存在未提交的 `android/key.properties`，keystore 文件同样不提交。请自行安全备份；换机重装必须沿用同一 keystore，否则无法覆盖安装。未配置签名时会回退到 debug 签名。

## 构建中踩到的坑（已修复）

1. **Kotlin 增量编译缓存跨盘报错**：pub 缓存在 C:、工程在 E: 时报
   `this and base files have different roots`。已在 `android/gradle.properties` 关闭 `kotlin.incremental`。
2. **插件 compileSdk 过低**：`flutter_blue_plus` 声明 compileSdk 33，但依赖的 androidx 库要求 34+，
   `checkReleaseAarMetadata` 失败。已在根 `android/build.gradle.kts` 统一把子工程 compileSdk 提到 36。
3. **缺失字体资源**：原 `pubspec.yaml` 引用不存在的 `assets/fonts/DigitalDisplay.ttf`，已移除。
4. **`DefaultTabController.of(context)` 空指针**：原 `MainScreen` 用自建 `TabController`，首页「连接设备」取不到。
   已改为 `DefaultTabController` 包住 Scaffold。
5. **胎宽类型错误**：`[16, 20, ..., 27.5, 29]` 是 `List<num>`，传给 `setTireSize(int)` 编译不过。
   已把 `tireSize` 改为 `double`。
6. **权限判断过严**：Android 12+ 不需要定位权限（`neverForLocation`），原逻辑要求全部授权会卡住扫描。
7. **扫描监听器重复叠加**：每次 `startScan` 都 `listen` 且不取消，已改为只订阅一次。
8. **未连接时首页布局挤压**：已改为未连接整屏显示连接引导。
9. **只支持「无响应写」的特征写不出去**：Android 报
   `The WRITE property is not supported by this BLE characteristic`。
   现在按特征属性自动选择 `withoutResponse`。

## 待办

- [ ] 用真实控制器校准命令字与校验算法（当前全部为推测值）。
- [ ] 限速 / 头灯 / EBS 电子刹车的 UI（命令构造已就绪，缺确认后的命令字）。
- [x] 连接后保持屏幕常亮（1.6.44 起接入 `wakelock_plus`，控制器或闪控任一连上即常亮）。
- [ ] iOS 端未在 macOS 上验证（`Info.plist` 已加蓝牙用途描述）。
