import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/polygon.dart';

/// 多角形の boolean 減算（B − A）を行う純関数サービス。
///
/// A（クリップ）は凸多角形（ピンの凸包）であることを前提とする。
/// B（被減算）は単純リング・分裂後の複数リング・穴付きのいずれもあり得る。
///
/// アルゴリズムは Weiler–Atherton ベース：
///   1. B の辺と A の辺の交点をすべて求める。
///   2. B / A それぞれの境界に交点を挿入し、相互リンクする。
///   3. 各交点に「A に入る/出る」フラグを付与。
///   4. 「A の外にある B の区間」を前進、「B の内にある A の区間」を逆走査で
///      つなぎ、閉路（= B − A のリング）を切り出す。複数得られれば分裂。
///
/// 数値安定のため、いったん局所平面（経度を cos(lat) 補正したメートル系）へ
/// 射影して計算し、結果を緯度経度へ戻す。退化や異常時は安全側に倒し、
/// 「変更なし（unchanged）」を返して B を破壊しない。
///
/// ── 使用例 ────────────────────────────────────────────────
///   final diff = PolygonClipService.differenceRingMinusConvex(bRing, aRing);
///   if (diff.consumed) { /* B は消滅 */ }
///   else if (diff.unchanged) { /* 重なりなし、B はそのまま */ }
///   else { final newRings = diff.outers; final newHoles = diff.holes; }
///
///   final updatedB = PolygonClipService.subtract(b, aRing, a.id);
/// ─────────────────────────────────────────────────────────
class PolygonClipService {
  PolygonClipService._();

  static const double _eps = 1e-7;
  static const double _mPerDegLat = 111320.0;

  // ─────────────────────────────────────────
  // 公開 API
  // ─────────────────────────────────────────

  /// WalkPolygon [b] から凸リング [aRing] を減算した新しい WalkPolygon を返す。
  /// 各外周リングごとに差し引き、既存の穴は新しい外周へ再分配する。
  static WalkPolygon subtract(WalkPolygon b, List<LatLng> aRing, String aId) {
    if (aRing.length < 3 || b.rings.isEmpty) return b;

    final newRings = <List<LatLng>>[];
    final newHoles = <List<List<LatLng>>>[];

    for (int i = 0; i < b.rings.length; i++) {
      final outer = b.rings[i];
      final existingHoles =
          (i < b.holes.length) ? b.holes[i] : const <List<LatLng>>[];

      final diff = differenceRingMinusConvex(outer, aRing);

      if (diff.consumed) {
        // この外周は完全に奪われた → 穴ごと消滅
        continue;
      }
      if (diff.unchanged) {
        newRings.add(outer);
        newHoles.add(List<List<LatLng>>.from(existingHoles));
        continue;
      }

      final candidateHoles = <List<LatLng>>[
        ...existingHoles,
        ...diff.holes,
      ];
      for (final o in diff.outers) {
        final assigned = <List<LatLng>>[];
        for (final h in candidateHoles) {
          if (h.length >= 3 && _centroidInside(h, o)) assigned.add(h);
        }
        newRings.add(o);
        newHoles.add(assigned);
      }
    }

    final consumed = newRings.isEmpty;
    return b.copyWith(
      rings: consumed ? const <List<LatLng>>[] : newRings,
      holes: consumed ? const <List<List<LatLng>>>[] : newHoles,
      status: consumed ? 'consumed' : 'active',
      lastModifiedAt: DateTime.now(),
      subtractedBy: aId,
    );
  }

  /// B の領域（外周リング群）と凸リング A が面積的に重なるかの簡易判定。
  static bool regionsOverlap(WalkPolygon b, List<LatLng> aRing) {
    for (final outer in b.rings) {
      if (_ringsOverlap(outer, aRing)) return true;
    }
    return false;
  }

  /// 単一リング [subject] から凸 [clip] を引いた結果。
  static PolyDiffResult differenceRingMinusConvex(
    List<LatLng> subject,
    List<LatLng> clip,
  ) {
    if (subject.length < 3 || clip.length < 3) {
      return const PolyDiffResult.unchanged();
    }

    // 局所平面へ射影
    final lat0 = subject.map((p) => p.latitude).reduce((a, b) => a + b) /
        subject.length;
    final lng0 = subject.map((p) => p.longitude).reduce((a, b) => a + b) /
        subject.length;
    final mPerLng = _mPerDegLat * math.cos(lat0 * math.pi / 180.0);

    _P proj(LatLng p) => _P(
          (p.longitude - lng0) * mPerLng,
          (p.latitude - lat0) * _mPerDegLat,
        );
    LatLng unproj(_P p) => LatLng(
          lat0 + p.y / _mPerDegLat,
          lng0 + p.x / mPerLng,
        );

    final s = subject.map(proj).toList();
    final c = clip.map(proj).toList();

    try {
      final result = _weilerAthertonDifference(s, c);
      if (result == null) {
        // 交差なし → 包含関係を判定
        final clipInSubject = c.every((p) => _pointInPoly(p, s));
        final subjectInClip = s.every((p) => _pointInPoly(p, c));
        if (subjectInClip) {
          return const PolyDiffResult.consumed();
        }
        if (clipInSubject) {
          // A が B の内部に完全包含 → A が穴になる
          return PolyDiffResult(
            outers: [subject],
            holes: [clip],
            consumed: false,
            unchanged: false,
          );
        }
        return const PolyDiffResult.unchanged();
      }

      if (result.isEmpty) return const PolyDiffResult.consumed();

      final outers = <List<LatLng>>[];
      for (final ring in result) {
        final cleaned = _cleanRing(ring);
        if (cleaned.length >= 3) {
          outers.add(_ensureCcw(cleaned).map(unproj).toList());
        }
      }
      if (outers.isEmpty) return const PolyDiffResult.consumed();
      return PolyDiffResult(
        outers: outers,
        holes: const [],
        consumed: false,
        unchanged: false,
      );
    } catch (_) {
      // 異常時は B を壊さない
      return const PolyDiffResult.unchanged();
    }
  }

  // ─────────────────────────────────────────
  // Weiler–Atherton 本体（平面座標）
  // ─────────────────────────────────────────

  /// 戻り値:
  ///   null      → 交差点なし（包含判定は呼び出し側）
  ///   []        → 交差はあるが結果が空（消滅）
  ///   [[...]]   → 結果リング群
  static List<List<_P>>? _weilerAthertonDifference(
    List<_P> subject,
    List<_P> clip,
  ) {
    final sn = subject.length;
    final cn = clip.length;

    // 交点レコード
    final records = <_XRec>[];
    for (int si = 0; si < sn; si++) {
      final a1 = subject[si];
      final a2 = subject[(si + 1) % sn];
      for (int ci = 0; ci < cn; ci++) {
        final b1 = clip[ci];
        final b2 = clip[(ci + 1) % cn];
        final x = _segIntersect(a1, a2, b1, b2);
        if (x != null) {
          records.add(_XRec(x.pt, si, x.t, ci, x.u, records.length));
        }
      }
    }
    if (records.isEmpty) return null;
    if (records.length.isOdd) return []; // 退化 → 安全側で消滅扱いを避け空

    // 拡張リスト（交点挿入）
    final sNodes = <_Nd>[];
    final sPosOfXid = <int, int>{};
    for (int si = 0; si < sn; si++) {
      sNodes.add(_Nd(subject[si], false, -1));
      final onEdge = records.where((r) => r.si == si).toList()
        ..sort((a, b) => a.t.compareTo(b.t));
      for (final r in onEdge) {
        sPosOfXid[r.id] = sNodes.length;
        sNodes.add(_Nd(r.pt, true, r.id));
      }
    }

    final cNodes = <_Nd>[];
    final cPosOfXid = <int, int>{};
    for (int ci = 0; ci < cn; ci++) {
      cNodes.add(_Nd(clip[ci], false, -1));
      final onEdge = records.where((r) => r.ci == ci).toList()
        ..sort((a, b) => a.u.compareTo(b.u));
      for (final r in onEdge) {
        cPosOfXid[r.id] = cNodes.length;
        cNodes.add(_Nd(r.pt, true, r.id));
      }
    }

    final sLen = sNodes.length;
    final cLen = cNodes.length;

    // entering: 交点を S 前進方向に越えると A(clip) の内側に入るか
    final entering = <int, bool>{};
    for (final r in records) {
      final idx = sPosOfXid[r.id]!;
      final cur = sNodes[idx].pt;
      final nxt = sNodes[(idx + 1) % sLen].pt;
      final mid = _P((cur.x + nxt.x) / 2, (cur.y + nxt.y) / 2);
      entering[r.id] = _pointInPoly(mid, clip);
    }

    final visited = <int>{};
    final results = <List<_P>>[];

    for (final r in records) {
      if (visited.contains(r.id)) continue;
      // 「A から出る」交点（entering==false）から開始 → S を外側へ進める
      if (entering[r.id] != false) continue;

      final contour = <_P>[];
      int curIdx = sPosOfXid[r.id]!;
      bool onSubject = true;
      final startXid = r.id;
      int guard = 0;
      final maxGuard = (sLen + cLen) * 4 + 10;

      while (guard++ < maxGuard) {
        if (onSubject) {
          final node = sNodes[curIdx];
          visited.add(node.xid);
          contour.add(node.pt);
          // S を前進し、次の交点まで頂点を集める
          int i = curIdx;
          while (true) {
            i = (i + 1) % sLen;
            if (sNodes[i].isX) break;
            contour.add(sNodes[i].pt);
          }
          final xid = sNodes[i].xid;
          if (xid == startXid) break; // 一周して戻った
          visited.add(xid);
          contour.add(sNodes[i].pt);
          onSubject = false;
          curIdx = cPosOfXid[xid]!;
        } else {
          // A(clip) を逆走査し、次の交点まで頂点を集める
          int i = curIdx;
          while (true) {
            i = (i - 1 + cLen) % cLen;
            if (cNodes[i].isX) break;
            contour.add(cNodes[i].pt);
          }
          final xid = cNodes[i].xid;
          contour.add(cNodes[i].pt);
          if (xid == startXid) break;
          onSubject = true;
          curIdx = sPosOfXid[xid]!;
        }
      }

      if (contour.length >= 3) results.add(contour);
    }

    return results;
  }

  // ─────────────────────────────────────────
  // 幾何ヘルパー（平面）
  // ─────────────────────────────────────────

  static _XHit? _segIntersect(_P a, _P b, _P c, _P d) {
    final rx = b.x - a.x, ry = b.y - a.y;
    final sx = d.x - c.x, sy = d.y - c.y;
    final denom = rx * sy - ry * sx;
    if (denom.abs() < 1e-12) return null; // 平行
    final t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / denom;
    final u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / denom;
    if (t > _eps && t < 1 - _eps && u > _eps && u < 1 - _eps) {
      return _XHit(_P(a.x + t * rx, a.y + t * ry), t, u);
    }
    return null;
  }

  static bool _pointInPoly(_P p, List<_P> poly) {
    bool inside = false;
    final n = poly.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final pi = poly[i], pj = poly[j];
      final intersect = ((pi.y > p.y) != (pj.y > p.y)) &&
          (p.x <
              (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 1e-18) + pi.x);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static bool _pointInPolyLL(LatLng p, List<LatLng> poly) {
    bool inside = false;
    final n = poly.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final pi = poly[i], pj = poly[j];
      final intersect = ((pi.latitude > p.latitude) !=
              (pj.latitude > p.latitude)) &&
          (p.longitude <
              (pj.longitude - pi.longitude) *
                      (p.latitude - pi.latitude) /
                      (pj.latitude - pi.latitude + 1e-18) +
                  pi.longitude);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static bool _centroidInside(List<LatLng> ring, List<LatLng> outer) {
    double sx = 0, sy = 0;
    for (final p in ring) {
      sx += p.longitude;
      sy += p.latitude;
    }
    final c = LatLng(sy / ring.length, sx / ring.length);
    return _pointInPolyLL(c, outer);
  }

  static bool _ringsOverlap(List<LatLng> a, List<LatLng> b) {
    // 頂点包含
    for (final p in a) {
      if (_pointInPolyLL(p, b)) return true;
    }
    for (final p in b) {
      if (_pointInPolyLL(p, a)) return true;
    }
    // 辺交差
    for (int i = 0; i < a.length; i++) {
      final a1 = a[i], a2 = a[(i + 1) % a.length];
      for (int j = 0; j < b.length; j++) {
        final b1 = b[j], b2 = b[(j + 1) % b.length];
        if (_segCrossLL(a1, a2, b1, b2)) return true;
      }
    }
    return false;
  }

  static bool _segCrossLL(LatLng a, LatLng b, LatLng c, LatLng d) {
    double cross(LatLng o, LatLng p, LatLng q) =>
        (p.longitude - o.longitude) * (q.latitude - o.latitude) -
        (p.latitude - o.latitude) * (q.longitude - o.longitude);
    final d1 = cross(c, d, a);
    final d2 = cross(c, d, b);
    final d3 = cross(a, b, c);
    final d4 = cross(a, b, d);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  static List<_P> _cleanRing(List<_P> ring) {
    final out = <_P>[];
    for (final p in ring) {
      if (out.isEmpty ||
          (out.last.x - p.x).abs() > 1e-6 ||
          (out.last.y - p.y).abs() > 1e-6) {
        out.add(p);
      }
    }
    // 末尾と先頭が重複していれば除去
    if (out.length >= 2 &&
        (out.first.x - out.last.x).abs() < 1e-6 &&
        (out.first.y - out.last.y).abs() < 1e-6) {
      out.removeLast();
    }
    return out;
  }

  static List<_P> _ensureCcw(List<_P> ring) {
    double sum = 0;
    for (int i = 0; i < ring.length; i++) {
      final a = ring[i], b = ring[(i + 1) % ring.length];
      sum += (b.x - a.x) * (b.y + a.y);
    }
    // sum > 0 は時計回り（y上向き平面）→ 反転して CCW に
    return sum > 0 ? ring.reversed.toList() : ring;
  }
}

/// 減算結果。
class PolyDiffResult {
  final List<List<LatLng>> outers;
  final List<List<LatLng>> holes;
  final bool consumed; // B が完全に消滅
  final bool unchanged; // 重なりなし・B 不変

  const PolyDiffResult({
    required this.outers,
    required this.holes,
    required this.consumed,
    required this.unchanged,
  });

  const PolyDiffResult.consumed()
      : outers = const [],
        holes = const [],
        consumed = true,
        unchanged = false;

  const PolyDiffResult.unchanged()
      : outers = const [],
        holes = const [],
        consumed = false,
        unchanged = true;
}

// ── 内部用の平面座標・ノード ───────────────────────────────
class _P {
  final double x, y;
  const _P(this.x, this.y);
}

class _XHit {
  final _P pt;
  final double t, u;
  const _XHit(this.pt, this.t, this.u);
}

class _XRec {
  final _P pt;
  final int si;
  final double t;
  final int ci;
  final double u;
  final int id;
  const _XRec(this.pt, this.si, this.t, this.ci, this.u, this.id);
}

class _Nd {
  final _P pt;
  final bool isX;
  final int xid;
  _Nd(this.pt, this.isX, this.xid);
}

// ═══════════════════════════════════════════════════════════
// 添付画像シナリオの検証メモ
// ───────────────────────────────────────────────────────────
// B = 赤い三角形（CCW: 頂点 b0(上), b1(左下), b2(右下) とする）。
// A = それを縦に貫く黄色の細長い凸四角形。A は B の上辺付近から
//     下辺付近まで縦断し、B の境界を 4 回横切る。
//
//   交点を S(=B) 前進順に並べると x0,x1,x2,x3 の 4 点。
//   midpoint テストにより:
//     x0: A から「出る」(entering=false)   ← 左側の外側区間の入口
//     x1: A に「入る」(entering=true)
//     x2: A から「出る」(entering=false)   ← 右側の外側区間の入口
//     x3: A に「入る」(entering=true)
//
//   走査1: entering==false の x0 から開始。
//     S を前進して B の左側の頂点群を集めつつ x1 まで進む
//       → contour に [x0, (Bの左側頂点…), x1]
//     x1 で A へ移り、A を逆走査して x0 まで戻る
//       → A の左側の縦辺（B 内部にある区間）を追加し閉路
//     得られるリング B1 = (B 左側の頂点) + (A 左側の交点 x0,x1)
//
//   走査2: 未訪問の entering==false の x2 から開始。
//     同様に B の右側頂点群 + x2,x3、A の右側縦辺で閉路
//     得られるリング B2 = (B 右側の頂点) + (A 右側の交点 x2,x3)
//
//   結果: B は B1（左）と B2（右）の 2 リングに分裂。
//   「左の交点は B1・右の交点は B2」という分配は、B 境界の走査順から
//   自動的に導かれており、左右判定の特別ロジックは不要である。
// ═══════════════════════════════════════════════════════════
