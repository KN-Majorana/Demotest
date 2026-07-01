import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'color_extraction.dart';
import 'location_service.dart';
import 'models/polygon.dart';
import 'photo_service.dart';
import 'services/exif_service.dart';
import 'widgets/create_method_sheet.dart';
import 'widgets/color_pick_sheet.dart';
import 'widgets/photo_source_sheet.dart';

enum PolygonCreateKind { createNew, addExisting }

/// 多角形作成フロー（ステップ A→B→C→D）の結果。
///
/// v4: 新規作成・既存追加のどちらも「色（colorId）」を選ぶ形に統一。
/// 既存追加時に「どの多角形へ追加するか」は呼び出し側（map_screen）が
/// 写真位置から自動選択する。
class PolygonCreateResult {
  final PolygonCreateKind kind;

  /// 選んだ色（colorPalette24 のインデックス）
  final int colorId;

  final String photoPath;

  /// 写真から抽出した主要色（colorPalette24 のインデックス群）
  final List<int> colorIds;

  final LatLng position;
  final DateTime takenAt;

  /// ライブラリ選択時に EXIF が無く現在地/現在時刻へフォールバックしたか
  final bool usedLocationFallback;

  const PolygonCreateResult({
    required this.kind,
    required this.colorId,
    required this.photoPath,
    required this.colorIds,
    required this.position,
    required this.takenAt,
    required this.usedLocationFallback,
  });
}

/// ステップ A→B→C→D を順に進める状態機械。
class PolygonCreateFlow {
  PolygonCreateFlow._();

  /// [forcedColorId] を指定すると（対戦モード）、色選択ステップを丸ごと
  /// スキップし、色はその値に固定される。
  static Future<PolygonCreateResult?> run(
    BuildContext context, {
    required List<WalkPolygon> myConfirmedPolygons,
    required LatLng currentPosition,
    int? forcedColorId,
  }) async {
    // 自分が所有する色 → 個数
    final ownedCounts = <int, int>{};
    for (final p in myConfirmedPolygons) {
      if (!p.confirmed || !p.isActive) continue;
      ownedCounts[p.colorId] = (ownedCounts[p.colorId] ?? 0) + 1;
    }
    final hasExisting = ownedCounts.isNotEmpty;

    // ── ステップ A：作成方法 ──
    final method = await CreateMethodSheet.show(
      context,
      hasExisting: hasExisting,
    );
    if (method == null || !context.mounted) return null;

    int? colorId;

    if (forcedColorId != null) {
      // 対戦モード：色は自分の割当色に固定（色選択をスキップ）
      colorId = forcedColorId;
    } else if (method == PolygonCreateMethod.createNew) {
      // ── ステップ B-①：色選択（全24色）──
      colorId = await ColorPickSheet.show(
        context,
        title: '多角形の色を選ぶ',
        subtitle: 'この色と一致する写真だけがピンになります。',
      );
    } else {
      // ── ステップ B-②(v4)：所有色のみから選択 ──
      final owned = ownedCounts.keys.toList()..sort();
      colorId = await ColorPickSheet.show(
        context,
        title: '追加する色を選ぶ',
        subtitle: '選んだ色の多角形のうち、写真に最も近いものへ追加されます。',
        allowedColorIds: owned,
        colorCounts: ownedCounts,
      );
    }
    if (colorId == null || !context.mounted) return null;

    // ── ステップ C：写真取得元 ──
    final source = await PhotoSourceSheet.show(context);
    if (source == null) return null;

    // ── 写真取得 ──
    String? path;
    LatLng position = currentPosition;
    DateTime takenAt = DateTime.now();
    bool usedFallback = false;

    if (source == PhotoSource.camera) {
      try {
        position = await LocationService.getCurrentPosition();
      } catch (_) {}
      path = await PhotoService.takeAndSavePhoto();
      if (path == null) return null;
    } else {
      path = await PhotoService.pickFromGalleryAndSave();
      if (path == null) return null;

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
      photoPath: path,
      colorIds: colorIds,
      position: position,
      takenAt: takenAt,
      usedLocationFallback: usedFallback,
    );
  }
}
