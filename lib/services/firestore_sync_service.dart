import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/friend_profile.dart';
import '../models/polygon.dart';
import 'firebase_auth_service.dart';
import 'polygon_clip_service.dart';
import 'storage_upload_service.dart';

/// Firestore とのデータ同期を担うサービス。
///
/// スキーマ:
///   users/{uid}                         : displayName, code, createdAt
///   users/{uid}/friends/{friendUid}     : addedAt, displayName, code
///   polygons/{polygonId}                : ownerUid, ownerName, colorId,
///                                         vertices[], createdAt(ms), photoIds[],
///                                         confirmed
///   photos/{photoId}                    : ownerUid, polygonId, lat, lng,
///                                         takenAt, colorId, imageUrl
class FirestoreSyncService {
  FirestoreSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  static CollectionReference<Map<String, dynamic>> get _polygons =>
      _db.collection('polygons');
  static CollectionReference<Map<String, dynamic>> get _photos =>
      _db.collection('photos');

  // ─────────────────────────────────────────
  // ユーザ / プロフィール
  // ─────────────────────────────────────────

  /// users/{uid} を作成（無ければ）。code が無ければ採番する。
  /// 自分の FriendProfile を返す。
  static Future<FriendProfile> ensureUserDoc(String displayName) async {
    final uid = await FirebaseAuthService.ensureSignedIn();
    final ref = _users.doc(uid);
    final snap = await ref.get();

    String code;
    if (!snap.exists || snap.data()?['code'] == null) {
      code = await _generateUniqueCode();
      await ref.set({
        'displayName': displayName,
        'code': code,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      code = snap.data()!['code'] as String;
      if (displayName.isNotEmpty && snap.data()?['displayName'] != displayName) {
        await ref.set({'displayName': displayName}, SetOptions(merge: true));
      }
    }

    await FirebaseAuthService.updateDisplayName(displayName);
    return FriendProfile(uid: uid, displayName: displayName, code: code);
  }

  /// 表示名を更新する。
  static Future<void> setDisplayName(String displayName) async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return;
    await _users.doc(uid).set(
      {'displayName': displayName},
      SetOptions(merge: true),
    );
    await FirebaseAuthService.updateDisplayName(displayName);
    // 既存の自分の多角形にも表示名を反映（任意・ベストエフォート）
    final mine = await _polygons.where('ownerUid', isEqualTo: uid).get();
    for (final d in mine.docs) {
      await d.reference.set({'ownerName': displayName}, SetOptions(merge: true));
    }
  }

  static Future<FriendProfile?> getMyProfile() async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return null;
    final snap = await _users.doc(uid).get();
    if (!snap.exists) return null;
    return FriendProfile.fromMap(uid, snap.data()!);
  }

  // ─────────────────────────────────────────
  // フレンド
  // ─────────────────────────────────────────

  /// 自分のフレンド一覧を購読する。
  static Stream<List<FriendProfile>> watchFriends() {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return Stream.value(const []);
    return _users.doc(uid).collection('friends').snapshots().map((snap) {
      final out = <FriendProfile>[];
      for (final d in snap.docs) {
        try {
          out.add(FriendProfile.fromMap(d.id, d.data()));
        } catch (_) {
          // 壊れた1件で全体を落とさない
        }
      }
      return out;
    });
  }

  /// フレンドコードからフレンドを追加する。追加した相手の FriendProfile を返す。
  /// 見つからない / 自分自身 の場合は例外を投げる。
  static Future<FriendProfile> addFriendByCode(String code) async {
    final uid = await FirebaseAuthService.ensureSignedIn();
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw 'コードを入力してください';
    }

    final q =
        await _users.where('code', isEqualTo: normalized).limit(1).get();
    if (q.docs.isEmpty) {
      throw 'そのコードのユーザが見つかりません';
    }
    final doc = q.docs.first;
    if (doc.id == uid) {
      throw '自分自身は追加できません';
    }

    final data = doc.data();
    await _users.doc(uid).collection('friends').doc(doc.id).set({
      'addedAt': FieldValue.serverTimestamp(),
      'displayName': data['displayName'] ?? '名無し',
      'code': data['code'],
    });

    return FriendProfile.fromMap(doc.id, data);
  }

  /// フレンドを削除する。
  static Future<void> removeFriend(String friendUid) async {
    final uid = FirebaseAuthService.uid;
    if (uid == null) return;
    await _users.doc(uid).collection('friends').doc(friendUid).delete();
  }

  // ─────────────────────────────────────────
  // 多角形（polygons）
  // ─────────────────────────────────────────

  /// 全多角形を createdAt 昇順で購読する。
  /// フレンド限定の絞り込みはクライアント側で行う（セキュリティルール参照）。
  static Stream<List<WalkPolygon>> watchAllPolygons() {
    return _polygons.orderBy('createdAt').snapshots().map((snap) {
      final out = <WalkPolygon>[];
      for (final d in snap.docs) {
        try {
          out.add(WalkPolygon.fromMap(d.data()));
        } catch (_) {
          // 壊れた/旧形式で読めない1件はスキップ（全体は落とさない）
        }
      }
      return out;
    });
  }

  /// 多角形を作成 / 更新する（確定済みのみ呼ぶ想定）。
  static Future<void> upsertPolygon(WalkPolygon polygon) async {
    await _polygons.doc(polygon.id).set(polygon.toMap());
  }

  static Future<void> deletePolygon(String polygonId) async {
    await _polygons.doc(polygonId).delete();
  }

  // ═════════════════════════════════════════════════════════
  // 機能2(v4)：新規多角形 A による、より古い B 群への減算適用
  //   - 単一リングに削れる / 穴があく → B ドキュメントをその場更新
  //   - B が完全に奪われる           → B を物理削除（写真も削除）
  //   - B が 2 つ以上に分裂           → 元 B を削除し B1..Bn を新規作成
  //                                     （createdAt は元 B を継承）
  // 分裂・消滅は WriteBatch で原子的に commit する（失敗時は何も反映されない）。
  // Cloud Storage の画像削除は batch に含められないため commit 成功後に行い、
  // 失敗はログのみとする（データ主体は Firestore を優先）。
  // ═════════════════════════════════════════════════════════

  static Map<String, dynamic> _llm(LatLng v) =>
      {'lat': v.latitude, 'lng': v.longitude};

  /// A（確定した新規多角形）で [candidates]（A より古い確定 active 多角形）を
  /// 減算適用する。versus モードでのみ呼ぶこと。
  static Future<void> applyOverride({
    required WalkPolygon a,
    required List<WalkPolygon> candidates,
  }) async {
    final aRing = a.vertices;
    if (aRing.length < 3 || a.createdAt == null) return;

    for (final b in candidates) {
      try {
        if (b.id == a.id) continue;
        if (!b.confirmed || !b.isActive || b.createdAt == null) continue;
        if (!a.createdAt!.isAfter(b.createdAt!)) continue; // A が新しい時のみ
        if (!PolygonClipService.regionsOverlap(b.vertices, aRing)) continue;

        final outcome = PolygonClipService.classify(b.vertices, aRing);
        final now = DateTime.now().millisecondsSinceEpoch;

        switch (outcome.kind) {
          case SubtractKind.unchanged:
            break;

          case SubtractKind.updatedSingle:
            // 角が削れて単一リングのまま → その場更新
            await _polygons.doc(b.id).set({
              'vertices': outcome.single!.map(_llm).toList(),
              'lastModifiedAt': now,
              'subtractedBy': a.id,
            }, SetOptions(merge: true));
            break;

          case SubtractKind.holed:
            // A が B 内部に完全包含 → 穴を追加（外周は不変）
            await _polygons.doc(b.id).set({
              'holes': [
                {'points': outcome.hole!.map(_llm).toList()}
              ],
              'lastModifiedAt': now,
              'subtractedBy': a.id,
            }, SetOptions(merge: true));
            break;

          case SubtractKind.consumed:
            await _consumeB(b);
            break;

          case SubtractKind.split:
            await _splitB(b, outcome.pieces!, aRing, a.id);
            break;
        }
      } catch (_) {
        // この B の処理に失敗しても他の B は続行（batch内は原子的）
      }
    }
  }

  /// B が A に完全に奪われた場合：B と B の全写真を削除する。
  static Future<void> _consumeB(WalkPolygon b) async {
    final photos = await _readPhotos(b.id);
    final batch = _db.batch();
    batch.delete(_polygons.doc(b.id));
    for (final p in photos) {
      batch.delete(_photos.doc(p.id));
    }
    await batch.commit(); // 失敗時は何も反映されない（原子的）

    for (final p in photos) {
      await StorageUploadService.deletePhoto(
          ownerUid: p.ownerUid, photoId: p.id);
    }
  }

  /// B が分裂した場合：元 B を削除し、各リングを独立ドキュメントとして作成。
  /// 写真は「どのリングに属するか / A に奪われて消失したか」で引き継ぎ or 削除。
  static Future<void> _splitB(
    WalkPolygon b,
    List<List<LatLng>> pieces,
    List<LatLng> aRing,
    String aId,
  ) async {
    final photos = await _readPhotos(b.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final createdMs = b.createdAt?.millisecondsSinceEpoch;

    // piece ごとの新 ID
    final refs = List.generate(pieces.length, (_) => _polygons.doc());
    final assigned = List.generate(pieces.length, (_) => <String>[]);
    final vanished = <({String id, String ownerUid})>[];

    for (final ph in photos) {
      // A の内側に入った点 → 消失（奪われた）
      if (PolygonClipService.pointInRing(ph.pos, aRing)) {
        vanished.add((id: ph.id, ownerUid: ph.ownerUid));
        continue;
      }
      // それ以外は、内部に含む piece（無ければ最近傍 piece）へ引き継ぎ
      int target = -1;
      for (int i = 0; i < pieces.length; i++) {
        if (PolygonClipService.pointInRing(ph.pos, pieces[i])) {
          target = i;
          break;
        }
      }
      if (target < 0) target = _nearestPiece(ph.pos, pieces);
      if (target >= 0) {
        assigned[target].add(ph.id);
      } else {
        vanished.add((id: ph.id, ownerUid: ph.ownerUid));
      }
    }

    final batch = _db.batch();
    batch.delete(_polygons.doc(b.id));
    for (int i = 0; i < pieces.length; i++) {
      batch.set(refs[i], {
        'id': refs[i].id,
        'ownerUid': b.ownerUid,
        'ownerName': b.ownerName,
        'colorId': b.colorId,
        'vertices': pieces[i].map(_llm).toList(),
        'holes': <dynamic>[],
        'createdAt': createdMs, // 元 B の createdAt を継承（減算判定のため）
        'lastModifiedAt': now,
        'subtractedBy': aId,
        'photoIds': assigned[i],
        'confirmed': true,
        'status': 'active',
      });
      // 引き継ぐ写真の polygonId を更新
      for (final pid in assigned[i]) {
        batch.set(_photos.doc(pid), {'polygonId': refs[i].id},
            SetOptions(merge: true));
      }
    }
    // 消失した写真は Firestore からも削除
    for (final v in vanished) {
      batch.delete(_photos.doc(v.id));
    }

    await batch.commit(); // 原子的：失敗時は元 B も残り、B1..Bn も作られない

    // commit 成功後に Storage 実体を削除（失敗はログのみ）
    for (final v in vanished) {
      await StorageUploadService.deletePhoto(
          ownerUid: v.ownerUid, photoId: v.id);
    }
  }

  static int _nearestPiece(LatLng p, List<List<LatLng>> pieces) {
    int best = -1;
    double bestD = double.infinity;
    for (int i = 0; i < pieces.length; i++) {
      for (final v in pieces[i]) {
        final dx = p.longitude - v.longitude;
        final dy = p.latitude - v.latitude;
        final d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }

  /// 指定 polygonId に属する写真の (id, 位置, ownerUid) を読み出す。
  static Future<List<({String id, LatLng pos, String ownerUid})>> _readPhotos(
      String polygonId) async {
    final out = <({String id, LatLng pos, String ownerUid})>[];
    try {
      final q =
          await _photos.where('polygonId', isEqualTo: polygonId).get();
      for (final d in q.docs) {
        final m = d.data();
        final lat = (m['lat'] as num?)?.toDouble();
        final lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        out.add((
          id: d.id,
          pos: LatLng(lat, lng),
          ownerUid: m['ownerUid'] as String? ?? '',
        ));
      }
    } catch (_) {}
    return out;
  }

  // ─────────────────────────────────────────
  // 写真メタ（photos）
  // ─────────────────────────────────────────

  /// 写真メタ（photos/{photoId}）を削除する。
  static Future<void> deletePhoto(String photoId) async {
    try {
      await _photos.doc(photoId).delete();
    } catch (_) {}
  }

  static Future<void> upsertPhoto({
    required String photoId,
    required String ownerUid,
    String? polygonId,
    required double lat,
    required double lng,
    required DateTime takenAt,
    required int colorId,
    required String imageUrl,
  }) async {
    await _photos.doc(photoId).set({
      'ownerUid': ownerUid,
      'polygonId': polygonId,
      'lat': lat,
      'lng': lng,
      'takenAt': takenAt.millisecondsSinceEpoch,
      'colorId': colorId,
      'imageUrl': imageUrl,
    });
  }

  // ─────────────────────────────────────────
  // 内部
  // ─────────────────────────────────────────

  /// 紛らわしい文字を除いた 6 文字の一意なフレンドコードを採番する。
  static Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    for (int attempt = 0; attempt < 8; attempt++) {
      final code = List.generate(
        6,
        (_) => chars[rnd.nextInt(chars.length)],
      ).join();
      final exists =
          await _users.where('code', isEqualTo: code).limit(1).get();
      if (exists.docs.isEmpty) return code;
    }
    // 衝突が続く場合はタイムスタンプ末尾でフォールバック
    return 'X${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase().padLeft(5, '0').substring(0, 5)}';
  }
}
