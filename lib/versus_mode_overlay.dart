import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'color_extraction.dart';
import 'models/polygon.dart';

/// 対戦モードの地図レイヤ。
///
/// 自分＋フレンドの確定多角形を、それぞれのパレット色で塗って描画する。
/// 機能2（時刻ベースの上書き）は「古い→新しい順に重ね描き」することで
/// 視覚的に表現する（新しい多角形 A が古い多角形 B の上に乗る）。
class VersusModeOverlay extends StatelessWidget {
  /// 描画対象（自分＋フレンドの確定多角形のみ）
  final List<WalkPolygon> polygons;

  /// 自分の UID（自分の領域を強調表示するため）
  final String? myUid;

  const VersusModeOverlay({
    super.key,
    required this.polygons,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _VersusPainter(
          camera: camera,
          polygons: polygons,
          myUid: myUid,
        ),
      ),
    );
  }
}

class _VersusPainter extends CustomPainter {
  final MapCamera camera;
  final List<WalkPolygon> polygons;
  final String? myUid;

  const _VersusPainter({
    required this.camera,
    required this.polygons,
    required this.myUid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 確定済みのみ。createdAt 昇順（古い→新しい）に並べ、新しい方を上に重ねる。
    final drawList = polygons
        .where((p) => p.confirmed && p.vertices.length >= 3)
        .toList()
      ..sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return ta.compareTo(tb);
      });

    for (final poly in drawList) {
      final path = _toPath(poly.vertices);
      if (path == null) continue;

      final pc = poly.colorId >= 0 && poly.colorId < colorPalette24.length
          ? colorPalette24[poly.colorId]
          : const ColorRGB(128, 128, 128);
      final isMine = myUid != null && poly.ownerUid == myUid;

      // 塗り（新しい多角形が後に描かれるので自然に上書きされる）
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromRGBO(pc.r, pc.g, pc.b, isMine ? 0.42 : 0.30)
          ..style = PaintingStyle.fill,
      );

      // 枠線：自分は実線で濃く、フレンドはやや細く
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromRGBO(pc.r, pc.g, pc.b, 1.0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMine ? 3.0 : 1.5,
      );
    }
  }

  Path? _toPath(List<LatLng> verts) {
    if (verts.length < 3) return null;
    final pts = verts
        .map((v) => _toOffset(camera.latLngToScreenPoint(v)))
        .toList();
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    return path;
  }

  Offset _toOffset(Point<double> point) => Offset(point.x, point.y);

  @override
  bool shouldRepaint(covariant _VersusPainter old) =>
      old.camera.center != camera.center ||
      old.camera.zoom != camera.zoom ||
      old.camera.rotation != camera.rotation ||
      old.camera.nonRotatedSize != camera.nonRotatedSize ||
      old.myUid != myUid ||
      !listEquals(old.polygons, polygons);
}
