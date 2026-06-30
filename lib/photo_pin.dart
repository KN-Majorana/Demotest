import 'package:latlong2/latlong.dart';

import 'color_extraction.dart';

/// 撮影した写真とその位置情報・主要色を保持するモデル
class PhotoPin {
  final String id;
  final String imagePath;
  final LatLng position;
  final DateTime takenAt;

  /// colorPalette24 のインデックスリスト（実行時に使用）
  final List<int> colorIds;

  /// 所有者の Firebase UID（対戦モード連携用）。
  /// 旧データや normal 専用ユーザでは null。
  final String? ownerUid;

  /// 属する多角形（WalkPolygon）の ID。未割り当ては null。
  final String? polygonId;

  PhotoPin({
    String? id,
    required this.imagePath,
    required this.position,
    required this.takenAt,
    this.colorIds = const [],
    this.ownerUid,
    this.polygonId,
  }) : id = id ?? '${takenAt.microsecondsSinceEpoch}';

  PhotoPin copyWith({
    String? imagePath,
    LatLng? position,
    DateTime? takenAt,
    List<int>? colorIds,
    String? ownerUid,
    String? polygonId,
  }) {
    return PhotoPin(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      position: position ?? this.position,
      takenAt: takenAt ?? this.takenAt,
      colorIds: colorIds ?? this.colorIds,
      ownerUid: ownerUid ?? this.ownerUid,
      polygonId: polygonId ?? this.polygonId,
    );
  }

  /// JSON 保存: colorIds をインデックスではなく色名（文字列）で保存
  /// → パレットの並び順が変わっても壊れない
  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'latitude': position.latitude,
    'longitude': position.longitude,
    'takenAt': takenAt.toIso8601String(),
    'colorNames': colorIds
        .where((i) => i >= 0 && i < colorNames24.length)
        .map((i) => colorNames24[i])
        .toList(),
    // 新フィールド（null の場合はキー自体を省略して旧形式と完全互換）
    if (ownerUid != null) 'ownerUid': ownerUid,
    if (polygonId != null) 'polygonId': polygonId,
  };

  factory PhotoPin.fromJson(Map<String, dynamic> json) {
    // 新形式（colorNames）を優先、旧形式（colorIds）にも対応
    List<int> ids;
    if (json.containsKey('colorNames')) {
      final names = (json['colorNames'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
      ids = names
          .map((name) => colorNames24.indexOf(name))
          .where((i) => i >= 0)
          .toList();
    } else {
      // 旧インデックス形式: 範囲外は除去
      ids = (json['colorIds'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .where((i) => i >= 0 && i < colorPalette24.length)
          .toList();
    }

    return PhotoPin(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      imagePath: json['imagePath'] as String,
      position: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      takenAt: DateTime.parse(json['takenAt'] as String),
      colorIds: ids,
      // 旧データには存在しないキー → null で互換維持
      ownerUid: json['ownerUid'] as String?,
      polygonId: json['polygonId'] as String?,
    );
  }
}
