import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../color_extraction.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import 'polygon_clip_service.dart';
import 'storage_upload_service.dart';

/// 1v1 対戦（battle）セッションの状態機械と、battle スコープの
/// 多角形／写真データを扱うサービス。
///
/// 状態遷移はすべて Firestore トランザクションで冪等に行う（同時操作に強い）。
/// UI 層は Firestore を直接触らず、必ず本サービス経由で操作する。
class BattleService {
  BattleService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _battles =>
      _db.collection('battles');

  static CollectionReference<Map<String, dynamic>> _polys(String battleId) =>
      _battles.doc(battleId).collection('polygons');
  static CollectionReference<Map<String, dynamic>> _photos(String battleId) =>
      _battles.doc(battleId).collection('photos');

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ═══════════════════════════════════════════════
  // 購読
  // ═══════════════════════════════════════════════

  /// 自分が参加している「進行中」の battle を1つ購読する。
  /// cleared/declined/expired や、期限切れ pending は対象外。
  static Stream<Battle?> watchActiveBattleFor(String uid) {
    return _battles
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      Battle? best;
      for (final d in snap.docs) {
        Battle b;
        try {
          b = Battle.fromMap(d.id, d.data());
        } catch (_) {
          continue;
        }
        if (b.status == BattleStatus.cleared ||
            b.status == BattleStatus.declined ||
            b.status == BattleStatus.expired) {
          continue;
        }
        if (b.isExpiredNow) continue; // 期限切れ pending は無視
        best = _preferred(best, b);
      }
      return best;
    });
  }

  static int _priority(BattleStatus s) {
    switch (s) {
      case BattleStatus.active:
        return 4;
      case BattleStatus.resultShown:
        return 3;
      case BattleStatus.ended:
        return 2;
      case BattleStatus.pending:
        return 1;
      default:
        return 0;
    }
  }

  static Battle? _preferred(Battle? a, Battle b) {
    if (a == null) return b;
    return _priority(b.status) > _priority(a.status) ? b : a;
  }

  static Stream<Battle?> watchBattle(String battleId) {
    return _battles.doc(battleId).snapshots().map((d) =>
        d.exists ? Battle.fromMap(d.id, d.data()!) : null);
  }

  // ═══════════════════════════════════════════════
  // 申込 / 応答（idle → pending → active）
  // ═══════════════════════════════════════════════

  /// 対決を申し込む。相手が対戦中なら例外。battleId を返す。
  static Future<String> requestChallenge({
    required String challengerUid,
    required String challengerName,
    required String opponentUid,
    required String opponentName,
    int timeLimitSec = 3600,
  }) async {
    // 相手が既に active / 有効な pending に入っていないか確認
    final snap = await _battles
        .where('participants', arrayContains: opponentUid)
        .get();
    for (final d in snap.docs) {
      final b = Battle.fromMap(d.id, d.data());
      final busy = b.status == BattleStatus.active ||
          (b.status == BattleStatus.pending && !b.isExpiredNow) ||
          b.status == BattleStatus.ended ||
          b.status == BattleStatus.resultShown;
      if (busy) throw '相手は現在対戦中です';
    }

    final ref = _battles.doc();
    final now = _now();
    await ref.set({
      'status': 'pending',
      'challengerUid': challengerUid,
      'challengerName': challengerName,
      'opponentUid': opponentUid,
      'opponentName': opponentName,
      'participants': [challengerUid, opponentUid],
      'createdAt': now,
      'expiresAt': now + 5 * 60 * 1000, // 5 分
      'timeLimitSec': timeLimitSec,
    });
    return ref.id;
  }

  /// 相手が承諾 → active。色をランダム割当し endsAt を確定。
  static Future<void> acceptChallenge(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(battleId, snap.data()!);
      if (b.status != BattleStatus.pending) return; // 冪等
      final now = _now();
      final (cColor, oColor) = _randomDistinctColors();
      tx.update(ref, {
        'status': 'active',
        'startedAt': now,
        'endsAt': now + b.timeLimitSec * 1000,
        'colorAssignment': {
          'challengerColorId': cColor,
          'opponentColorId': oColor,
        },
      });
    });
  }

  static Future<void> declineChallenge(String battleId) async {
    await _battles.doc(battleId).update({'status': 'declined'});
    // 数秒後に自動削除
    Future.delayed(const Duration(seconds: 4), () async {
      try {
        await _battles.doc(battleId).delete();
      } catch (_) {}
    });
  }

  /// 挑戦者が申込をキャンセル（pending のうちに取り消し）。
  static Future<void> cancelChallenge(String battleId) async {
    try {
      await _battles.doc(battleId).delete();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════
  // 時間切れ（active → ended）
  // ═══════════════════════════════════════════════

  static Future<void> endByTimeout(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(battleId, snap.data()!);
      if (b.status != BattleStatus.active) return; // 冪等
      if (b.endsAt == null || DateTime.now().isBefore(b.endsAt!)) return;
      tx.update(ref, {
        'status': 'ended',
        'endedAt': _now(),
        'endedBy': 'timeout',
      });
    });
  }

  // ═══════════════════════════════════════════════
  // 強制終了（active → ended、両者合意）
  // ═══════════════════════════════════════════════

  static Future<void> requestForceEnd(String battleId, String uid) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(battleId, snap.data()!);
      if (b.status != BattleStatus.active) return;
      // 先着優先：既に誰かが提案済みなら無視
      if (b.forceEndRequestBy != null) return;
      tx.update(ref, {
        'forceEndRequestBy': uid,
        'forceEndRequestAt': _now(),
      });
    });
  }

  static Future<void> confirmForceEnd(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(battleId, snap.data()!);
      if (b.status != BattleStatus.active || b.forceEndRequestBy == null) {
        return;
      }
      tx.update(ref, {
        'status': 'ended',
        'endedAt': _now(),
        'endedBy': 'forceEnd',
        'forceEndRequestBy': null,
        'forceEndRequestAt': null,
      });
    });
  }

  static Future<void> cancelForceEnd(String battleId) async {
    await _battles.doc(battleId).update({
      'forceEndRequestBy': null,
      'forceEndRequestAt': null,
    });
  }

  // ═══════════════════════════════════════════════
  // リザルト（ended → result_shown → cleared）
  // ═══════════════════════════════════════════════

  static Future<void> markResultShown(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(battleId, snap.data()!);
      if (b.status != BattleStatus.ended) return; // 冪等
      tx.update(ref, {'status': 'result_shown'});
    });
  }

  static Future<void> setResultSnapshotUrl(
      String battleId, String url) async {
    try {
      await _battles.doc(battleId).update({'resultSnapshotUrl': url});
    } catch (_) {}
  }

  static Future<void> requestResultClose(String battleId, String uid) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = Battle.fromMap(battleId, snap.data()!);
      if (b.resultCloseRequestBy != null) return; // 先着優先
      tx.update(ref, {
        'resultCloseRequestBy': uid,
        'resultCloseRequestAt': _now(),
      });
    });
  }

  static Future<void> cancelResultClose(String battleId) async {
    await _battles.doc(battleId).update({
      'resultCloseRequestBy': null,
      'resultCloseRequestAt': null,
    });
  }

  /// 相手が終了に同意 → cleared にして battle データを完全消去。
  static Future<void> confirmResultClose(String battleId) async {
    await _db.runTransaction((tx) async {
      final ref = _battles.doc(battleId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      tx.update(ref, {'status': 'cleared'});
    });
    await purgeBattle(battleId);
  }

  /// battle 配下（polygons / photos / Storage）と本体を物理削除する。
  static Future<void> purgeBattle(String battleId) async {
    // 写真：Storage 実体も消すため、先に読み出す
    List<QueryDocumentSnapshot<Map<String, dynamic>>> photoDocs = [];
    try {
      photoDocs = (await _photos(battleId).get()).docs;
    } catch (_) {}

    // Firestore サブコレクション削除（batch は最大500件）
    try {
      final polyDocs = (await _polys(battleId).get()).docs;
      final batch = _db.batch();
      for (final d in polyDocs) {
        batch.delete(d.reference);
      }
      for (final d in photoDocs) {
        batch.delete(d.reference);
      }
      batch.delete(_battles.doc(battleId));
      await batch.commit();
    } catch (_) {}

    // Storage 実体（best-effort）
    for (final d in photoDocs) {
      final m = d.data();
      final owner = m['ownerUid'] as String? ?? '';
      await StorageUploadService.deleteBattlePhoto(
        battleId: battleId,
        ownerUid: owner,
        photoId: d.id,
      );
    }
    await StorageUploadService.deleteResultSnapshot(battleId);
  }

  // ═══════════════════════════════════════════════
  // battle スコープの多角形 / 写真
  // ═══════════════════════════════════════════════

  static Stream<List<WalkPolygon>> watchBattlePolygons(String battleId) {
    return _polys(battleId).snapshots().map((snap) {
      final out = <WalkPolygon>[];
      for (final d in snap.docs) {
        try {
          out.add(WalkPolygon.fromMap(d.data()));
        } catch (_) {}
      }
      return out;
    });
  }

  static Future<void> upsertBattlePolygon(
      String battleId, WalkPolygon p) async {
    await _polys(battleId).doc(p.id).set(p.toMap());
  }

  static Future<void> deleteBattlePolygon(
      String battleId, String polygonId) async {
    try {
      await _polys(battleId).doc(polygonId).delete();
    } catch (_) {}
  }

  static Future<void> upsertBattlePhoto({
    required String battleId,
    required String photoId,
    required String ownerUid,
    String? polygonId,
    required double lat,
    required double lng,
    required DateTime takenAt,
    required int colorId,
    required String imageUrl,
  }) async {
    await _photos(battleId).doc(photoId).set({
      'ownerUid': ownerUid,
      'polygonId': polygonId,
      'lat': lat,
      'lng': lng,
      'takenAt': takenAt.millisecondsSinceEpoch,
      'colorId': colorId,
      'imageUrl': imageUrl,
    });
  }

  static Future<void> deleteBattlePhoto(
      String battleId, String photoId) async {
    try {
      await _photos(battleId).doc(photoId).delete();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════
  // 減算 / 分裂再登録（battle スコープ内。v3/v4 を流用）
  // ═══════════════════════════════════════════════

  static Map<String, dynamic> _llm(LatLng v) =>
      {'lat': v.latitude, 'lng': v.longitude};

  /// A 確定時、同 battle 内の古い B 群へ減算を適用する。
  static Future<void> applyOverrideInBattle({
    required String battleId,
    required WalkPolygon a,
    required List<WalkPolygon> candidates,
  }) async {
    final aRing = a.vertices;
    if (aRing.length < 3 || a.createdAt == null) return;

    for (final b in candidates) {
      try {
        if (b.id == a.id) continue;
        if (!b.confirmed || !b.isActive || b.createdAt == null) continue;
        if (!a.createdAt!.isAfter(b.createdAt!)) continue;
        if (!PolygonClipService.regionsOverlap(b.vertices, aRing)) continue;

        final outcome = PolygonClipService.classify(b.vertices, aRing);
        final now = _now();
        switch (outcome.kind) {
          case SubtractKind.unchanged:
            break;
          case SubtractKind.updatedSingle:
            await _polys(battleId).doc(b.id).set({
              'vertices': outcome.single!.map(_llm).toList(),
              'lastModifiedAt': now,
              'subtractedBy': a.id,
            }, SetOptions(merge: true));
            break;
          case SubtractKind.holed:
            await _polys(battleId).doc(b.id).set({
              'holes': [
                {'points': outcome.hole!.map(_llm).toList()}
              ],
              'lastModifiedAt': now,
              'subtractedBy': a.id,
            }, SetOptions(merge: true));
            break;
          case SubtractKind.consumed:
            await _consumeB(battleId, b);
            break;
          case SubtractKind.split:
            await _splitB(battleId, b, outcome.pieces!, aRing, a.id);
            break;
        }
      } catch (_) {}
    }
  }

  static Future<void> _consumeB(String battleId, WalkPolygon b) async {
    final photos = await _readPhotos(battleId, b.id);
    final batch = _db.batch();
    batch.delete(_polys(battleId).doc(b.id));
    for (final p in photos) {
      batch.delete(_photos(battleId).doc(p.id));
    }
    await batch.commit();
    for (final p in photos) {
      await StorageUploadService.deleteBattlePhoto(
          battleId: battleId, ownerUid: p.ownerUid, photoId: p.id);
    }
  }

  static Future<void> _splitB(
    String battleId,
    WalkPolygon b,
    List<List<LatLng>> pieces,
    List<LatLng> aRing,
    String aId,
  ) async {
    final photos = await _readPhotos(battleId, b.id);
    final now = _now();
    final createdMs = b.createdAt?.millisecondsSinceEpoch;

    final refs = List.generate(pieces.length, (_) => _polys(battleId).doc());
    final assigned = List.generate(pieces.length, (_) => <String>[]);
    final vanished = <({String id, String ownerUid})>[];

    for (final ph in photos) {
      if (PolygonClipService.pointInRing(ph.pos, aRing)) {
        vanished.add((id: ph.id, ownerUid: ph.ownerUid));
        continue;
      }
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
    batch.delete(_polys(battleId).doc(b.id));
    for (int i = 0; i < pieces.length; i++) {
      batch.set(refs[i], {
        'id': refs[i].id,
        'ownerUid': b.ownerUid,
        'ownerName': b.ownerName,
        'colorId': b.colorId,
        'vertices': pieces[i].map(_llm).toList(),
        'holes': <dynamic>[],
        'createdAt': createdMs,
        'lastModifiedAt': now,
        'subtractedBy': aId,
        'photoIds': assigned[i],
        'confirmed': true,
        'status': 'active',
      });
      for (final pid in assigned[i]) {
        batch.set(_photos(battleId).doc(pid), {'polygonId': refs[i].id},
            SetOptions(merge: true));
      }
    }
    for (final v in vanished) {
      batch.delete(_photos(battleId).doc(v.id));
    }
    await batch.commit();

    for (final v in vanished) {
      await StorageUploadService.deleteBattlePhoto(
          battleId: battleId, ownerUid: v.ownerUid, photoId: v.id);
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

  static Future<List<({String id, LatLng pos, String ownerUid})>> _readPhotos(
      String battleId, String polygonId) async {
    final out = <({String id, LatLng pos, String ownerUid})>[];
    try {
      final q = await _photos(battleId)
          .where('polygonId', isEqualTo: polygonId)
          .get();
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

  // ── 色割当 ──────────────────────────────
  static (int, int) _randomDistinctColors() {
    final n = colorPalette24.length;
    final rnd = Random();
    final a = rnd.nextInt(n);
    int b;
    do {
      b = rnd.nextInt(n);
    } while (b == a);
    return (a, b);
  }

  // ── プレゼンス（近似）──────────────────────
  static Future<void> touchLastSeen(String uid) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .set({'lastSeen': _now()}, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<int?> readLastSeen(String uid) async {
    try {
      final d = await _db.collection('users').doc(uid).get();
      return (d.data()?['lastSeen'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }
}
