import 'package:latlong2/latlong.dart';

/// 多角形（陣地）のドメインモデル。
///
/// 注: flutter_map も `Polygon` という型をエクスポートしているため、
/// 名前衝突を避ける目的でクラス名を [WalkPolygon] としている。
///
/// - [vertices] は構成ピン位置の凸包（時計回り/反時計回りは問わない）。
/// - [confirmed] が false の間は「準備中（ピン2枚以下）」を表し、
///   塗り表示・Firestore 共有の対象外。3枚目で true になり [createdAt] が確定する。
class WalkPolygon {
  final String id;
  final String ownerUid;
  final String ownerName;

  /// colorPalette24 のインデックス
  final int colorId;

  /// 凸包頂点（緯度経度）
  final List<LatLng> vertices;

  /// 多角形が「確定した」時刻。準備中は null。
  final DateTime? createdAt;

  /// 構成する写真ピンの ID リスト
  final List<String> photoIds;

  /// 3点以上集まり、領域として確定済みか
  final bool confirmed;

  const WalkPolygon({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.colorId,
    required this.vertices,
    required this.createdAt,
    required this.photoIds,
    required this.confirmed,
  });

  WalkPolygon copyWith({
    String? ownerUid,
    String? ownerName,
    int? colorId,
    List<LatLng>? vertices,
    DateTime? createdAt,
    List<String>? photoIds,
    bool? confirmed,
  }) {
    return WalkPolygon(
      id: id,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerName: ownerName ?? this.ownerName,
      colorId: colorId ?? this.colorId,
      vertices: vertices ?? this.vertices,
      createdAt: createdAt ?? this.createdAt,
      photoIds: photoIds ?? this.photoIds,
      confirmed: confirmed ?? this.confirmed,
    );
  }

  /// Firestore / ローカル共通のマップ表現。
  /// createdAt は比較が安定する epoch ミリ秒（int）で保持する。
  Map<String, dynamic> toMap() => {
    'id': id,
    'ownerUid': ownerUid,
    'ownerName': ownerName,
    'colorId': colorId,
    'vertices': vertices
        .map((v) => {'lat': v.latitude, 'lng': v.longitude})
        .toList(),
    'createdAt': createdAt?.millisecondsSinceEpoch,
    'photoIds': photoIds,
    'confirmed': confirmed,
  };

  factory WalkPolygon.fromMap(Map<String, dynamic> map) {
    final rawVerts = (map['vertices'] as List<dynamic>? ?? []);
    final verts = rawVerts.map((e) {
      final m = e as Map<String, dynamic>;
      return LatLng(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      );
    }).toList();

    final createdMs = map['createdAt'];
    return WalkPolygon(
      id: map['id'] as String,
      ownerUid: map['ownerUid'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '名無し',
      colorId: (map['colorId'] as num?)?.toInt() ?? 0,
      vertices: verts,
      createdAt: createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((createdMs as num).toInt()),
      photoIds: (map['photoIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      confirmed: map['confirmed'] as bool? ?? true,
    );
  }
}
