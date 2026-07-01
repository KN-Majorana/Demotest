import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/polygon.dart';

/// リザルト画面の % バーで使う面積計算。
///
/// 仕様（11-3）:
///   - 全多角形の頂点から bounding box を算出し、20% パディングを加えた
///     矩形の面積を「盤面面積 F」とする。
///   - 各プレイヤーの塗り面積 S = 全所有多角形の実効面積合計。
///   - `self%  = S_self / F * 100`
///     `opp%   = S_opp  / F * 100`
///   - 浮動小数誤差で合計 100% 超なら 100 にクランプ。
///   - 多角形 0 個の場合は 0.0%。
class AreaShareCalculator {
  AreaShareCalculator._();

  static const double _mPerDegLat = 111320.0;

  /// [polygons] を対象に、[myUid] と [oppUid] の面積シェア（%）を返す。
  static AreaShareResult compute({
    required List<WalkPolygon> polygons,
    required String myUid,
    required String oppUid,
  }) {
    final live = polygons
        .where((p) => p.isActive && p.vertices.length >= 3)
        .toList();
    if (live.isEmpty) {
      return const AreaShareResult(
          myPercent: 0.0, opponentPercent: 0.0, boardAreaM2: 0.0);
    }

    // すべての頂点を集める
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final p in live) {
      for (final v in p.vertices) {
        if (v.latitude < minLat) minLat = v.latitude;
        if (v.latitude > maxLat) maxLat = v.latitude;
        if (v.longitude < minLng) minLng = v.longitude;
        if (v.longitude > maxLng) maxLng = v.longitude;
      }
    }

    // 20% パディング
    final latPad = (maxLat - minLat) * 0.2;
    final lngPad = (maxLng - minLng) * 0.2;
    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    final refLat = (minLat + maxLat) / 2.0;
    final mPerLng = _mPerDegLat * math.cos(refLat * math.pi / 180.0);
    final boardW = (maxLng - minLng) * mPerLng;
    final boardH = (maxLat - minLat) * _mPerDegLat;
    final board = boardW.abs() * boardH.abs();
    if (board <= 0) {
      return const AreaShareResult(
          myPercent: 0.0, opponentPercent: 0.0, boardAreaM2: 0.0);
    }

    double mySum = 0.0, oppSum = 0.0;
    for (final p in live) {
      final a = _areaWithHoles(p, refLat);
      if (p.ownerUid == myUid) {
        mySum += a;
      } else if (p.ownerUid == oppUid) {
        oppSum += a;
      }
    }

    double my = (mySum / board) * 100.0;
    double opp = (oppSum / board) * 100.0;
    if (my.isNaN) my = 0.0;
    if (opp.isNaN) opp = 0.0;
    if (my < 0) my = 0.0;
    if (opp < 0) opp = 0.0;
    // 浮動小数誤差で合計 100% 超はクランプ
    if (my + opp > 100.0) {
      final scale = 100.0 / (my + opp);
      my *= scale;
      opp *= scale;
    }

    return AreaShareResult(
      myPercent: my,
      opponentPercent: opp,
      boardAreaM2: board,
    );
  }

  /// 外周から穴の面積を引いた実効面積。
  static double _areaWithHoles(WalkPolygon p, double refLat) {
    final outer = _polyArea(p.vertices, refLat);
    double holeSum = 0.0;
    for (final h in p.holes) {
      holeSum += _polyArea(h, refLat);
    }
    final v = outer - holeSum;
    return v < 0 ? 0.0 : v;
  }

  static double _polyArea(List<LatLng> verts, double refLat) {
    if (verts.length < 3) return 0.0;
    final mPerLng = _mPerDegLat * math.cos(refLat * math.pi / 180.0);
    double sum = 0.0;
    for (int i = 0; i < verts.length; i++) {
      final a = verts[i];
      final b = verts[(i + 1) % verts.length];
      final ax = a.longitude * mPerLng;
      final ay = a.latitude * _mPerDegLat;
      final bx = b.longitude * mPerLng;
      final by = b.latitude * _mPerDegLat;
      sum += ax * by - bx * ay;
    }
    return sum.abs() / 2.0;
  }
}

class AreaShareResult {
  final double myPercent;
  final double opponentPercent;
  final double boardAreaM2;
  const AreaShareResult({
    required this.myPercent,
    required this.opponentPercent,
    required this.boardAreaM2,
  });
}
