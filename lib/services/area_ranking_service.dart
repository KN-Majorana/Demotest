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

  /// 多角形の実効面積（外周 − 穴合計）を返す。
  static double regionArea(WalkPolygon p) {
    double area = PolygonOverlapService.areaMeters(p.vertices);
    for (final hole in p.holes) {
      area -= PolygonOverlapService.areaMeters(hole);
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

/// 1v1 スコア（プレイヤー1人分）
class BattleScore {
  final String uid;
  double areaMeters;
  int polygonCount;
  int stealCount; // 相手を削り取った回数（近似）
  BattleScore(this.uid)
      : areaMeters = 0,
        polygonCount = 0,
        stealCount = 0;
}

/// battle スコープの多角形から、各プレイヤーのスコアを集計する。
Map<String, BattleScore> computeBattleScores(List<WalkPolygon> polys) {
  final confirmed =
      polys.where((p) => p.confirmed && p.isActive).toList();

  // polygonId -> ownerUid（減算元の所有者を引くため）
  final idOwner = <String, String>{
    for (final p in confirmed) p.id: p.ownerUid,
  };

  final scores = <String, BattleScore>{};
  BattleScore scoreOf(String uid) =>
      scores.putIfAbsent(uid, () => BattleScore(uid));

  for (final p in confirmed) {
    final s = scoreOf(p.ownerUid);
    s.areaMeters += AreaRankingService.regionArea(p);
    s.polygonCount += 1;
    // 削り取り: この多角形を削った A の所有者に加算（近似）
    final by = p.subtractedBy;
    if (by != null) {
      final subtractorUid = idOwner[by];
      if (subtractorUid != null) scoreOf(subtractorUid).stealCount += 1;
    }
  }
  return scores;
}
