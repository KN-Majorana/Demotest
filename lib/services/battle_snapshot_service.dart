import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'storage_upload_service.dart';

/// リザルト画面用のマップスナップショット（PNG）を生成し、
/// Cloud Storage にアップロードして URL を返すサービス。
///
/// 実装方針(b)：challenger 側だけが生成・アップロードし、
/// opponent は resultSnapshotUrl を購読して同じ画像を表示する。
class BattleSnapshotService {
  BattleSnapshotService._();

  /// [boundaryKey] を付けた RepaintBoundary を PNG 化してアップロードする。
  static Future<String?> captureAndUpload({
    required GlobalKey boundaryKey,
    required String battleId,
  }) async {
    try {
      final obj = boundaryKey.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return null;
      final image = await obj.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final url = await StorageUploadService.uploadResultSnapshot(
        battleId: battleId,
        pngBytes: data.buffer.asUint8List(),
      );
      return url;
    } catch (_) {
      return null;
    }
  }
}
