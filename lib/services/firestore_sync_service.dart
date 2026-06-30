import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_profile.dart';
import '../models/polygon.dart';
import 'firebase_auth_service.dart';

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
    return _users.doc(uid).collection('friends').snapshots().map(
          (snap) => snap.docs
              .map((d) => FriendProfile.fromMap(d.id, d.data()))
              .toList(),
        );
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
    return _polygons.orderBy('createdAt').snapshots().map(
          (snap) =>
              snap.docs.map((d) => WalkPolygon.fromMap(d.data())).toList(),
        );
  }

  /// 多角形を作成 / 更新する（確定済みのみ呼ぶ想定）。
  static Future<void> upsertPolygon(WalkPolygon polygon) async {
    await _polygons.doc(polygon.id).set(polygon.toMap());
  }

  static Future<void> deletePolygon(String polygonId) async {
    await _polygons.doc(polygonId).delete();
  }

  // ─────────────────────────────────────────
  // 写真メタ（photos）
  // ─────────────────────────────────────────

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
