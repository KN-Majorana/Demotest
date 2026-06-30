import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'color_extraction.dart';
import 'location_service.dart';
import 'models/polygon.dart';
import 'photo_service.dart';
import 'services/exif_service.dart';
import 'widgets/create_method_sheet.dart';
import 'widgets/color_pick_sheet.dart';
import 'widgets/existing_polygon_pick_sheet.dart';
import 'widgets/photo_source_sheet.dart';

enum PolygonCreateKind { createNew, addExisting }

/// 多角形作成フロー（ステップ A→B→C→D）の結果。
///
/// 色判定（colorIds）まで済ませた状態で返す。最終的な「色一致チェックと
/// ピン確定」は呼び出し側（map_screen）の状態を使って行う。
class PolygonCreateResult {
  final PolygonCreateKind kind;

  /// createNew のとき選んだ色（colorPalette24 のインデックス）
  final int? colorId;

  /// addExisting のとき選んだ多角形
  final WalkPolygon? target;

  final String photoPath;

  /// 写真から抽出した主要色（colorPalette24 のインデックス群）
  final List<int> colorIds;

  final LatLng position;
  final DateTime takenAt;

  /// ライブラリ選択時に EXIF が無く、現在地/現在時刻にフォールバックしたか
  final bool usedLocationFallback;

  const PolygonCreateResult({
    required this.kind,
    required this.colorId,
    required this.target,
    required this.photoPath,
    required this.colorIds,
    required this.position,
    required this.takenAt,
    required this.usedLocationFallback,
  });
}

/// ステップ A→B→C→D を順に進める状態機械。
///
/// 途中でキャンセル/閉じられた場合は null を返す（取得済み写真は破棄する）。
class PolygonCreateFlow {
  PolygonCreateFlow._();

  static Future<PolygonCreateResult?> run(
    BuildContext context, {
    required List<WalkPolygon> myConfirmedPolygons,
    required LatLng currentPosition,
  }) async {
    // ── ステップ A：作成方法 ──
    final method = await CreateMethodSheet.show(
      context,
      hasExisting: myConfirmedPolygons.isNotEmpty,
    );
    if (method == null || !context.mounted) return null;

    int? colorId;
    WalkPolygon? target;

    if (method == PolygonCreateMethod.createNew) {
      // ── ステップ B-①：色選択 ──
      colorId = await ColorPickSheet.show(context);
      if (colorId == null || !context.mounted) return null;
    } else {
      // ── ステップ B-②：既存多角形の選択 ──
      target = await ExistingPolygonPickSheet.show(
        context,
        polygons: myConfirmedPolygons,
      );
      if (target == null || !context.mounted) return null;
    }

    // ── ステップ C：写真取得元 ──
    final source = await PhotoSourceSheet.show(context);
    if (source == null) return null;

    // ── 写真取得 ──
    String? path;
    LatLng position = currentPosition;
    DateTime takenAt = DateTime.now();
    bool usedFallback = false;

    if (source == PhotoSource.camera) {
      // 撮影：現在地・現在時刻
      try {
        position = await LocationService.getCurrentPosition();
      } catch (_) {
        // 取得できなければ渡された現在地を使う
      }
      path = await PhotoService.takeAndSavePhoto();
      if (path == null) return null; // キャンセル
    } else {
      // ライブラリ：EXIF から GPS / 撮影日時を取得、無ければフォールバック
      path = await PhotoService.pickFromGalleryAndSave();
      if (path == null) return null; // キャンセル

      final exif = await ExifService.readExifForFile(path);
      if (exif.lat != null && exif.lng != null) {
        position = LatLng(exif.lat!, exif.lng!);
      } else {
        usedFallback = true;
      }
      if (exif.timestamp != null) {
        takenAt = exif.timestamp!;
      } else {
        usedFallback = true;
      }
    }

    // ── ステップ D（前半）：色判定 ──
    final colorIds = await extractColorIdsFromPath(path);

    return PolygonCreateResult(
      kind: method == PolygonCreateMethod.createNew
          ? PolygonCreateKind.createNew
          : PolygonCreateKind.addExisting,
      colorId: colorId,
      target: target,
      photoPath: path,
      colorIds: colorIds,
      position: position,
      takenAt: takenAt,
      usedLocationFallback: usedFallback,
    );
  }
}
