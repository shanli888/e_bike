import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/frame_log.dart';
import '../services/ble_service.dart';

/// 蓝牙协议调试页：查看收发原始报文，并可手动下发十六进制命令。
///
/// 逆向文档里的帧格式是推测值，接上真实码表后可以在这里比对
/// 设备实际返回的报文，再回头修正 `_parseDataFrame` 的偏移。
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final _hexController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  // 高级发送参数
  String? _targetChar;   // null = 用默认写通道
  int _padLen = 0;       // 0 = 不补零
  bool _noRsp = false;   // 强制无应答写

  @override
  void initState() {
    super.initState();
    // 进调试页自动开启嗅探，确保命令回包能被记录到
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = context.read<BleService>();
      if (ble.isConnected && !ble.sniffMode) {
        ble.setSniffMode(true);
      }
    });
  }

  @override
  void dispose() {
    _hexController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send(BleService ble) async {
    if (_sending) return;
    setState(() => _sending = true);
    final error = await ble.sendHexAdvanced(
      hexText: _hexController.text,
      charShort: _targetChar,
      padLen: _padLen,
      noRsp: _noRsp,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _scrollToBottom();
    }
  }

  /// 把全部日志复制到剪贴板
  void _copyLogs(BleService ble) {
    final sb = StringBuffer();
    sb.writeln('智能码表 蓝牙调试日志  ${DateTime.now()}');
    sb.writeln('设备: ${ble.connectedDevice?.platformName ?? "未连接"}  '
        '写=${ble.writeCharLabel} 通知=${ble.notifyCharLabel}');
    sb.writeln('----------------------------------------');
    for (final log in ble.logs) {
      final dir = log.outgoing ? '>>' : '<<';
      final line = log.data.isEmpty
          ? '${log.timeText} $dir ${log.source}'
          : '${log.timeText} $dir ${log.source}: ${log.hex}';
      sb.writeln(line);
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    final lineCount = sb.toString().split("\n").length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 $lineCount 行日志到剪贴板'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('蓝牙调试'),
        actions: [
          Consumer<BleService>(
            builder: (context, ble, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 重新发现服务（仅连接时可用）
                if (ble.isConnected)
                  TextButton(
                    onPressed: () async {
                      await ble.rediscoverServices();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已重新发现服务，请查看日志'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: const Text('重发现', style: TextStyle(color: Colors.orange)),
                  ),
                // 复制全部日志到剪贴板，方便发给开发者分析
                TextButton(
                  onPressed: ble.logs.isEmpty ? null : () => _copyLogs(ble),
                  child: const Text('复制日志', style: TextStyle(color: Colors.orange)),
                ),
                TextButton(
                  onPressed: ble.logs.isEmpty ? null : ble.clearLogs,
                  child: const Text('清空', style: TextStyle(color: Colors.orange)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Consumer<BleService>(
        builder: (context, ble, _) {
          _scrollToBottom();
          return Column(
            children: [
              _buildStatusBar(ble),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text('此前原厂包错误，旧协议不适用；未知命令可能改变车辆状态。',
                    style: TextStyle(color: Colors.orange, fontSize: 11)),
              ),
              Expanded(child: _buildLogList(ble)),
              _buildAdvancedBar(ble),
              _buildInputBar(ble),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(BleService ble) {
    final connected = ble.isConnected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white.withValues(alpha: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                size: 16,
                color: connected ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connected
                      ? (ble.connectedDevice?.platformName ?? '已连接')
                      : '未连接设备，仅能查看历史报文',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: connected ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${ble.logs.length} 条',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '写 ${ble.writeCharLabel} · 通知 ${ble.notifyCharLabel}'
            '${ble.hasCtrlChannel ? ' · 含 FFE2 控制通道' : ''}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(BleService ble) {
    if (ble.logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert,
                  size: 56, color: Colors.white.withValues(alpha: 0.18)),
              const SizedBox(height: 16),
              Text(
                '还没有报文',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                '连接码表后，设备推送的数据帧会实时显示在这里；\n也可以在下方手动发送命令试探协议。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: ble.logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) => _buildLogTile(ble.logs[index]),
    );
  }

  Widget _buildLogTile(FrameLog log) {
    final color = log.outgoing ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                log.outgoing ? '发送 →' : '← 接收',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                log.source,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
              ),
              const Spacer(),
              Text(
                log.timeText,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            log.hex,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// 高级发送控制条：目标特征 / 补零长度 / 无应答写 / 读特征
  Widget _buildAdvancedBar(BleService ble) {
    final candidates = ble.writableCharCandidates;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      color: Colors.white.withValues(alpha: 0.03),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 嗅探模式：订阅所有可通知特征，录制设备主动上报的原始帧（逆向用）
          Row(
            children: [
              Icon(Icons.radar,
                  size: 15,
                  color: ble.sniffMode ? Colors.green : Colors.white38),
              const SizedBox(width: 6),
              Text('全特征嗅探',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              const Spacer(),
              Switch(
                value: ble.sniffMode,
                activeThumbColor: Colors.green,
                onChanged: ble.isConnected ? (v) => ble.setSniffMode(v) : null,
              ),
            ],
          ),
          if (ble.sniffMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('已订阅全部通知特征，操作电机后原始回包会记入日志',
                  style: TextStyle(
                      color: Colors.green.withValues(alpha: 0.7), fontSize: 10)),
            ),
          Row(
            children: [
              Text('目标',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
              const SizedBox(width: 6),
              DropdownButton<String?>(
                value: _targetChar,
                isDense: true,
                dropdownColor: const Color(0xFF252540),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('默认(FFE1→FFE2)')),
                  for (final c in candidates)
                    DropdownMenuItem<String?>(value: c, child: Text(c.toUpperCase())),
                ],
                onChanged: (v) => setState(() => _targetChar = v),
              ),
              const SizedBox(width: 10),
              Text('补零到',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
              const SizedBox(width: 4),
              DropdownButton<int>(
                value: _padLen,
                isDense: true,
                dropdownColor: const Color(0xFF252540),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('不补')),
                  DropdownMenuItem(value: 16, child: Text('16')),
                  DropdownMenuItem(value: 20, child: Text('20')),
                ],
                onChanged: (v) => setState(() => _padLen = v ?? 0),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Switch(
                    value: _noRsp,
                    activeThumbColor: Colors.orange,
                    onChanged: (v) => setState(() => _noRsp = v),
                  ),
                  Text('无应答',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                ],
              ),
            ],
          ),
          // 读取私有特征当前值（帮助分析设备数据组织）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('读特征:',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                const SizedBox(width: 6),
                for (final u in ['ffe1', 'ffe2', '2abe', '2a2b']) ...[
                  ActionChip(
                    label: Text(u.toUpperCase(), style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.blue.withValues(alpha: 0.15),
                    side: BorderSide(color: Colors.blue.withValues(alpha: 0.4)),
                    onPressed: ble.isConnected ? () => ble.readCharToLog(u) : null,
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.science_outlined, size: 16),
              label: const Text('原厂 C0 电压查询'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              onPressed: ble.isConnected && !_sending && !ble.lvbuProbeRunning
                  ? () => _queryLvbuVoltage(ble)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _queryLvbuVoltage(BleService ble) async {
    if (_sending) return;
    setState(() => _sending = true);
    final result = await ble.queryLvbuVoltage();
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildInputBar(BleService ble) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hexController,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F\s]')),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '手动发送未知命令可能改变设备状态',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _send(ble),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sending || !ble.isConnected ? null : () => _send(ble),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }
}
