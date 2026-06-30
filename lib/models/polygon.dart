import 'package:latlong2/latlong.dart';

/// 多角形（陣地）のドメインモデル。
///
/// 注: flutter_map も `Polygon` をエクスポートしているため、名前衝突を
/// 避けてクラス名は [WalkPolygon] とする。
///
/// v3 で「真の幾何学的減算」に対応するため、単一リングではなく
/// MultiPolygon（複数外周リング）＋穴を保持できる構造にした。
///   - [rings]   各外周リング（CCW）。A による減算で分裂すると複数になる。
///   - [holes]   各外周リングに対応する穴のリスト（rings と同じ長さ）。
///               A が B 内部に完全包含されたときに穴が生じる。
///   - [status]  'active'（表示・集計対象）/ 'consumed'（奪われて消滅）。
///   - [confirmed] が false の間は準備中（ピン2枚以下）で共有対象外。
class WalkPolygon {
  final String id;
  final String ownerUid;
  final String ownerName;

  /// colorPalette24 のインデックス
  final int colorId;

  /// 外周リング群（CCW）。分裂時は複数。
  final List<List<LatLng>> rings;

  /// 各外周リングごとの穴リスト（rings と同じ長さ。穴なしは空リスト）。
  final List<List<List<LatLng>>> holes;

  /// 多角形が「確定した」時刻。準備中は null。
  final DateTime? createdAt;

  /// 最後に減算（領域を奪われた）された時刻。
  final DateTime? lastModifiedAt;

  /// 直近の減算を行った A の polygonId（履歴用）。
  final String? subtractedBy;

  /// 構成する写真ピンの ID リスト
  final List<String> photoIds;

  /// 3点以上集まり領域として確定済みか
  final bool confirmed;

  /// 'active' | 'consumed'
  final String status;

  const WalkPolygon({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.colorId,
    required this.rings,
    required this.holes,
    required this.createdAt,
    required this.photoIds,
    required this.confirmed,
    this.lastModifiedAt,
    this.subtractedBy,
    this.status = 'active',
  });

  /// 後方互換用：最初の外周リングを返す（旧コードの `vertices` 相当）。
  List<LatLng> get vertices => rings.isNotEmpty ? rings.first : const [];

  /// 全リングの頂点総数
  int get vertexCount => rings.fold(0, (sum, r) => sum + r.length);

  bool get isActive => status == 'active';

  WalkPolygon copyWith({
    String? ownerUid,
    String? ownerName,
    int? colorId,
    List<List<LatLng>>? rings,
    List<List<List<LatLng>>>? holes,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    String? subtractedBy,
    List<String>? photoIds,
    bool? confirmed,
    String? status,
  }) {
    return WalkPolygon(
      id: id,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerName: ownerName ?? this.ownerName,
      colorId: colorId ?? this.colorId,
      rings: rings ?? this.rings,
      holes: holes ?? this.holes,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      subtractedBy: subtractedBy ?? this.subtractedBy,
      photoIds: photoIds ?? this.photoIds,
      confirmed: confirmed ?? this.confirmed,
      status: status ?? this.status,
    );
  }

  /// 単一リング（穴なし）の WalkPolygon を作る簡易コンストラクタ。
  factory WalkPolygon.singleRing({
    required String id,
    required String ownerUid,
    required String ownerName,
    required int colorId,
    required List<LatLng> ring,
    required DateTime? createdAt,
    required List<String> photoIds,
    required bool confirmed,
  }) {
    return WalkPolygon(
      id: id,
      ownerUid: ownerUid,
      ownerName: ownerName,
      colorId: colorId,
      rings: ring.isEmpty ? const [] : [ring],
      holes: ring.isEmpty ? const [] : [const []],
      createdAt: createdAt,
      photoIds: photoIds,
      confirmed: confirmed,
    );
  }

  // ── シリアライズ ──────────────────────────────

  static Map<String, dynamic> _ll(LatLng v) =>
      {'lat': v.latitude, 'lng': v.longitude};

  static LatLng _toLL(dynamic e) {
    final m = e as Map<String, dynamic>;
    return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
  }

  /// 1 リングをパース。新形式 {'points':[...]} と旧形式 [...] の両対応。
  static List<LatLng> _parseRing(dynamic r) {
    if (r is Map) {
      return (r['points'] as List<dynamic>? ?? []).map(_toLL).toList();
    }
    return (r as List<dynamic>).map(_toLL).toList();
  }

  // Firestore は「配列の直下に配列」を許可しないため、各リングを
  // map（{'points': [...]}）で包む。holes も同様に map で包む。
  static Map<String, dynamic> _ringMap(List<LatLng> ring) =>
      {'points': ring.map(_ll).toList()};

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerUid': ownerUid,
        'ownerName': ownerName,
        'colorId': colorId,
        'rings': rings.map(_ringMap).toList(),
        'holes': holes
            .map((hl) => {'rings': hl.map(_ringMap).toList()})
            .toList(),
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'lastModifiedAt': lastModifiedAt?.millisecondsSinceEpoch,
        'subtractedBy': subtractedBy,
        'photoIds': photoIds,
        'confirmed': confirmed,
        'status': status,
      };

  factory WalkPolygon.fromMap(Map<String, dynamic> map) {
    // rings/holes をパース。旧形式（vertices）にも対応。
    List<List<LatLng>> rings;
    List<List<List<LatLng>>> holes;

    if (map['rings'] != null) {
      rings = (map['rings'] as List<dynamic>).map(_parseRing).toList();
    } else if (map['vertices'] != null) {
      // 旧形式: 単一リング
      final verts = (map['vertices'] as List<dynamic>).map(_toLL).toList();
      rings = verts.isEmpty ? <List<LatLng>>[] : [verts];
    } else {
      rings = <List<LatLng>>[];
    }

    if (map['holes'] != null) {
      holes = (map['holes'] as List<dynamic>).map((hl) {
        // 新形式: {'rings': [ {'points':[...]}, ... ]}
        if (hl is Map) {
          final inner = (hl['rings'] as List<dynamic>? ?? []);
          return inner.map(_parseRing).toList();
        }
        // 旧形式（入れ子リスト）
        return (hl as List<dynamic>).map(_parseRing).toList();
      }).toList();
    } else {
      // rings と同じ長さの空穴リストで初期化
      holes = List.generate(rings.length, (_) => <List<LatLng>>[]);
    }
    // 長さ不一致を補正
    while (holes.length < rings.length) {
      holes.add(<List<LatLng>>[]);
    }

    final createdMs = map['createdAt'];
    final modMs = map['lastModifiedAt'];
    return WalkPolygon(
      id: map['id'] as String,
      ownerUid: map['ownerUid'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '名無し',
      colorId: (map['colorId'] as num?)?.toInt() ?? 0,
      rings: rings,
      holes: holes,
      createdAt: createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((createdMs as num).toInt()),
      lastModifiedAt: modMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((modMs as num).toInt()),
      subtractedBy: map['subtractedBy'] as String?,
      photoIds: (map['photoIds'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
      confirmed: map['confirmed'] as bool? ?? true,
      status: map['status'] as String? ?? 'active',
    );
  }
}
