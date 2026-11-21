import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ride_record.dart';

/// 骑行记录的本地文件仓库（纯离线）。
///
/// 每条记录一个 `<id>.json` 文件，放在应用文档目录的 rides/ 子目录下。
/// 列表读取时按开始时间倒序；写入采用「先写临时文件再 rename」避免中途断电
/// 产生半截文件。目录可通过构造参数注入，便于单元测试用临时目录。
class RideRepository {
  RideRepository({Directory? dir}) : _dirOverride = dir;

  final Directory? _dirOverride;
  Directory? _resolved;

  Future<Directory> _rideDir() async {
    final existing = _resolved;
    if (existing != null) return existing;
    final base = _dirOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}rides');
    if (!await dir.exists()) await dir.create(recursive: true);
    _resolved = dir;
    return dir;
  }

  /// 保存一次骑行，返回写入的文件。
  Future<File> save(RideSession session) async {
    final dir = await _rideDir();
    // 用 id 做文件名，替换掉文件系统非法字符
    final safeId = session.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final target = File('${dir.path}${Platform.pathSeparator}$safeId.json');
    final tmp = File('${dir.path}${Platform.pathSeparator}$safeId.json.tmp');
    await tmp.writeAsString(session.toJsonString());
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
    return target;
  }

  /// 列出全部记录，按开始时间倒序（最新在前）。
  /// 单条解析失败时跳过，不让一条坏数据毁掉整个列表。
  Future<List<RideSession>> listAll() async {
    final dir = await _rideDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    final items = <RideSession>[];
    for (final f in files) {
      try {
        items.add(RideSession.fromJsonString(await f.readAsString()));
      } catch (_) {
        // 跳过损坏记录
      }
    }
    items.sort((a, b) => b.startTime.compareTo(a.startTime));
    return items;
  }

  /// 删除指定 id 的记录
  Future<void> delete(String id) async {
    final dir = await _rideDir();
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final target = File('${dir.path}${Platform.pathSeparator}$safeId.json');
    if (await target.exists()) await target.delete();
  }

  /// 累计统计：总次数 / 总里程 km / 总爬升 m
  Future<({int count, double distanceKm, double ascentM})> totals() async {
    final all = await listAll();
    var dist = 0.0;
    var asc = 0.0;
    for (final r in all) {
      dist += r.distanceKm;
      asc += r.ascentM;
    }
    return (count: all.length, distanceKm: dist, ascentM: asc);
  }
}
