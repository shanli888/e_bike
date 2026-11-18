/// 一条指令的下发结果
///
/// 设备采用「非静默命令」：下发后需要等设备回包确认。
/// 由于具体回包格式还在逆向中，这里把「收到匹配回包」视为确认成功，
/// 超时则视为「未确认」（设备可能已执行，只是没回包）。
enum CommandResult {
  /// 已下发且收到设备确认
  ok,

  /// 助力已在 0% / 99% 边界，本次没有发送
  atLimit,

  /// 已下发，但在超时时间内没有收到设备回包
  noResponse,

  /// 设备回了包，但内容表示执行失败
  deviceError,

  /// 写入蓝牙特征失败（无可用写特征 / 权限 / 特征不支持等）
  writeFailed,

  /// 其他蓝牙操作正在进行，本次没有发送。
  busy,

  /// 上次模式设置结果不确定，不允许再次发送。
  modeUncertain,

  /// 速度不为零、不可用或过期，禁止设置。
  notStationary,

  /// 尚未连接设备
  notConnected,

  /// 手机蓝牙没打开
  bluetoothOff,
}

extension CommandResultX on CommandResult {
  bool get isOk => this == CommandResult.ok;

  /// 指令确实发出去了（设备有回包，或者只是没回包）
  ///
  /// 没回包只表示写入已发出，不代表设备执行或状态已更新。
  bool get isSent => this == CommandResult.ok || this == CommandResult.noResponse;

  /// 是否需要弹窗强提示（其余情况用轻提示即可）
  bool get isError =>
      this == CommandResult.writeFailed ||
      this == CommandResult.busy ||
      this == CommandResult.modeUncertain ||
      this == CommandResult.notStationary ||
      this == CommandResult.notConnected ||
      this == CommandResult.bluetoothOff;

  String get title => switch (this) {
        CommandResult.ok => '指令已确认',
        CommandResult.atLimit => '已到边界',
        CommandResult.noResponse => '未收到设备确认',
        CommandResult.deviceError => '设备执行失败',
        CommandResult.writeFailed => '写入失败',
        CommandResult.busy => '蓝牙操作繁忙',
        CommandResult.modeUncertain => '助力状态未确认',
        CommandResult.notStationary => '未确认车辆静止',
        CommandResult.notConnected => '未连接设备',
        CommandResult.bluetoothOff => '蓝牙未开启',
      };

  String get message => switch (this) {
        CommandResult.ok => '设备已回包确认。',
        CommandResult.atLimit => '助力已在 0% 或 99% 边界，本次未发送。',
        CommandResult.noResponse => '未收到匹配确认，设备可能已经执行；请勿连续重试，先在原厂 App 或车辆上核实。',
        CommandResult.deviceError => '设备返回了失败状态，请检查参数或设备状态。',
        CommandResult.writeFailed => '蓝牙写入未成功或无法确认；请检查连接并通过原厂 App 或车辆核实。',
        CommandResult.busy => '蓝牙操作正在进行（只读查询或模式设置冷却），本次未发送；停止助力会自动等待链路空闲后重发。',
        CommandResult.modeUncertain => '手动模式尚未确认或上次设置结果不确定，本次未发送。请先在车辆或原厂 App 核实；如有必要重启本应用。',
        CommandResult.notStationary => '电机速度不为零、未读取或已过期，本次未发送。请停车并确认车轮安全后重试。',
        CommandResult.notConnected => '请先在「设备」页搜索并连接控制器。',
        CommandResult.bluetoothOff => '请打开手机蓝牙后再试。',
      };
}
