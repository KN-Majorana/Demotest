import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'color_extraction.dart';
import 'models/polygon.dart';

/// 対戦モードの地図レイヤ。
///
/// 自分＋フレンドの確定・active 多角形を、それぞれのパレット色で塗る。
/// v3 以降、領域の上書きは [WalkPolygon] の幾何（rings/holes）そのものが
/// 表しているため、ここでは「視覚的な重ね合わせ」を一切行わない。
/// 各多角形の rings をそのまま塗り、holes は even-odd でくり抜く。
class VersusModeOverlay extends StatelessWidget {
  /// 描画対象（自分＋フレンドの確定・active 多角形のみ）
  final List<WalkPolygon> polygons;

  /// 自分の UID（自分の領域を強調するため）
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
    for (final poly in polygons) {
      if (!poly.confirmed || !poly.isActive) continue;
      if (poly.rings.isEmpty) continue;

      final pc = poly.colorId >= 0 && poly.colorId < colorPalette24.length
          ? colorPalette24[poly.colorId]
          : const ColorRGB(128, 128, 128);
      final isMine = myUid != null && poly.ownerUid == myUid;

      for (int i = 0; i < poly.rings.length; i++) {
        final ring = poly.rings[i];
        if (ring.length < 3) continue;

        // 外周 ＋ 穴（even-odd でくり抜く）
        final path = Path()..fillType = PathFillType.evenOdd;
        _addRing(path, ring);
        if (i < poly.holes.length) {
          for (final hole in poly.holes[i]) {
            if (hole.length >= 3) _addRing(path, hole);
          }
        }

        // 塗り（幾何が示すままに塗る。重ね合成トリックは使わない）
        canvas.drawPath(
          path,
          Paint()
            ..color = Color.fromRGBO(pc.r, pc.g, pc.b, isMine ? 0.42 : 0.30)
            ..style = PaintingStyle.fill,
        );

        // 外周の枠線
        final outline = Path();
        _addRing(outline, ring);
        canvas.drawPath(
          outline,
          Paint()
            ..color = Color.fromRGBO(pc.r, pc.g, pc.b, 1.0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isMine ? 3.0 : 1.5,
        );
      }
    }
  }

  void _addRing(Path path, List<LatLng> ring) {
    final pts =
        ring.map((v) => _toOffset(camera.latLngToScreenPoint(v))).toList();
    path.moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
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
