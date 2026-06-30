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
class AreaRankingService {
  AreaRankingService._();

  /// [visible]（自分＋フレンドの確定多角形）から
  /// 「所有者 × 色」ごとに実効面積を合算し、降順ランキングを返す。
  ///
  /// 機能2の上書き（より新しい多角形が古い多角形を奪う）を
  /// [PolygonOverlapService.effectiveAreaMeters] で反映する。
  static List<RankingEntry> rank(
    List<WalkPolygon> visible, {
    int topN = 20,
  }) {
    final confirmed = visible.where((p) => p.confirmed).toList();

    // (ownerUid|colorId) -> 集計
    final Map<String, _Agg> byKey = {};

    for (final poly in confirmed) {
      final eff = PolygonOverlapService.effectiveAreaMeters(poly, confirmed);
      if (eff <= 0) continue;
      final key = '${poly.ownerUid}|${poly.colorId}';
      final agg = byKey.putIfAbsent(
        key,
        () => _Agg(poly.ownerUid, poly.ownerName, poly.colorId),
      );
      agg.area += eff;
      // 表示名は最新のもので上書き（空なら維持）
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
