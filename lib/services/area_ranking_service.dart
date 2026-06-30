import '../models/polygon.dart';
import 'polygon_overlap_service.dart';

/// ランキング1行分の集計結果
class RankingEntry {
  final String ownerUid;
  final String ownerName;
  final int colorId;

  /// 実効面積（平方メートル）
  final double areaMeters;

  const RankingEntry({
    required this.ownerUid,
    required this.ownerName,
    required this.colorId,
    required this.areaMeters,
  });
}

/// 対戦モードの「面積ランキング」を集計するサービス。
///
/// v3 以降、領域の上書きは多角形の幾何（rings/holes）そのものに反映されて
/// いるため、実効面積は「現在の幾何の面積」を素直に計算するだけでよい：
///   effectiveArea = Σ area(rings) − Σ area(holes)
class AreaRankingService {
  AreaRankingService._();

  /// 多角形の実効面積（外周リング合計 − 穴合計）を返す。
  static double regionArea(WalkPolygon p) {
    double area = 0;
    for (final ring in p.rings) {
      area += PolygonOverlapService.areaMeters(ring);
    }
    for (final hl in p.holes) {
      for (final hole in hl) {
        area -= PolygonOverlapService.areaMeters(hole);
      }
    }
    return area < 0 ? 0 : area;
  }

  /// [visible]（自分＋フレンドの確定・active 多角形）から
  /// 「所有者 × 色」ごとに実効面積を合算し、降順ランキングを返す。
  static List<RankingEntry> rank(
    List<WalkPolygon> visible, {
    int topN = 20,
  }) {
    final target =
        visible.where((p) => p.confirmed && p.isActive).toList();

    final Map<String, _Agg> byKey = {};

    for (final poly in target) {
      final eff = regionArea(poly);
      if (eff <= 0) continue;
      final key = '${poly.ownerUid}|${poly.colorId}';
      final agg = byKey.putIfAbsent(
        key,
        () => _Agg(poly.ownerUid, poly.ownerName, poly.colorId),
      );
      agg.area += eff;
      if (poly.ownerName.isNotEmpty) agg.ownerName = poly.ownerName;
    }

    final entries = byKey.values
        .map((a) => RankingEntry(
              ownerUid: a.ownerUid,
              ownerName: a.ownerName,
              colorId: a.colorId,
              areaMeters: a.area,
            ))
        .toList()
      ..sort((a, b) => b.areaMeters.compareTo(a.areaMeters));

    if (entries.length > topN) return entries.sublist(0, topN);
    return entries;
  }
}

class _Agg {
  final String ownerUid;
  String ownerName;
  final int colorId;
  double area = 0.0;
  _Agg(this.ownerUid, this.ownerName, this.colorId);
}
