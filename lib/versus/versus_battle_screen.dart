import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../color_extraction.dart';
import '../current_location_marker.dart';
import '../location_service.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import '../photo_pin.dart';
import '../photo_pin_marker.dart';
import '../photo_service.dart';
import '../polygon_create_flow.dart';
import '../services/battle_service.dart';
import '../services/polygon_overlap_service.dart';
import '../services/storage_upload_service.dart';
import '../versus_mode_overlay.dart';
import 'score_panel_screen.dart';

/// 対戦 active 状態のマップ画面。
/// カウントダウン・自分の色バッジ・強制終了・スコア・多角形作成を配置。
class VersusBattleScreen extends StatefulWidget {
  final Battle battle;
  final String myUid;

  /// 「強制終了」ボタン押下時（待機ダイアログ表示は親に委譲）
  final VoidCallback onRequestForceEnd;

  const VersusBattleScreen({
    super.key,
    required this.battle,
    required this.myUid,
    required this.onRequestForceEnd,
  });

  @override
  State<VersusBattleScreen> createState() => _VersusBattleScreenState();
}

class _VersusBattleScreenState extends State<VersusBattleScreen> {
  final MapController _mapController = MapController();
  LatLng _pos = const LatLng(35.1815, 136.9066);
  bool _hasLoc = false;

  StreamSubscription<List<WalkPolygon>>? _polySub;
  final List<WalkPolygon> _battlePolygons = [];

  // 準備中（未確定）グループと写真ピンはローカル（メモリ）保持
  final List<WalkPolygon> _pending = [];
  final List<PhotoPin> _pins = [];

  Timer? _countdown;
  Duration _remaining = Duration.zero;

  String get _battleId => widget.battle.id;
  int get _myColorId => widget.battle.myColorId(widget.myUid) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _polySub = BattleService.watchBattlePolygons(_battleId).listen((all) {
      if (!mounted) return;
      setState(() {
        _battlePolygons
          ..clear()
          ..addAll(all);
      });
    }, onError: (Object e) => debugPrint('battle polygons購読エラー: $e'));

    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = widget.battle.remaining());
      if (widget.battle.isPastEnd) {
        BattleService.endByTimeout(_battleId); // 冪等
      }
    });
  }

  @override
  void dispose() {
    _polySub?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final p = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _pos = p;
        _hasLoc = true;
      });
      _mapController.move(_pos, 15.0);
    } catch (_) {}
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<WalkPolygon> get _myConfirmed => _battlePolygons
      .where((p) => p.ownerUid == widget.myUid && p.confirmed && p.isActive)
      .toList();

  // ─── 多角形作成フロー（対戦：色は自分の割当色に固定） ───
  Future<void> _openCreateFlow() async {
    try {
      final result = await PolygonCreateFlow.run(
        context,
        myConfirmedPolygons: _myConfirmed,
        currentPosition: _pos,
        forcedColorId: _myColorId,
      );
      if (result == null || !mounted) return;
      if (result.usedLocationFallback) {
        _toast('位置情報が取得できなかったため、現在地・現在時刻で登録します');
      }

      final colorName =
          _myColorId < colorNames24.length ? colorNames24[_myColorId] : '';
      if (!result.colorIds.contains(_myColorId)) {
        await PhotoService.deletePhotoFile(result.photoPath);
        _toast('あなたの色（$colorName）と一致しないため追加できません');
        return;
      }

      if (result.kind == PolygonCreateKind.createNew) {
        final group = _pendingForColor() ?? _createPending();
        _addPinNew(result, group);
      } else {
        _addPinExisting(result);
      }
    } catch (e) {
      _toast('追加に失敗: $e');
    }
  }

  WalkPolygon? _pendingForColor() {
    for (final g in _pending) {
      if (!g.confirmed && g.colorId == _myColorId) return g;
    }
    return null;
  }

  WalkPolygon _createPending() {
    return WalkPolygon(
      id: 'bpoly_${DateTime.now().microsecondsSinceEpoch}',
      ownerUid: widget.myUid,
      ownerName: widget.battle.myNameFor(widget.myUid),
      colorId: _myColorId,
      vertices: const [],
      holes: const [],
      createdAt: null,
      photoIds: const [],
      confirmed: false,
    );
  }

  void _addPinNew(PolygonCreateResult result, WalkPolygon group) {
    final pin = PhotoPin(
      imagePath: result.photoPath,
      position: result.position,
      takenAt: result.takenAt,
      colorIds: result.colorIds,
      ownerUid: widget.myUid,
      polygonId: group.id,
    );
    final positions = [
      ..._pins
          .where((p) => p.polygonId == group.id)
          .map((p) => p.position),
      result.position,
    ];
    final hull = PolygonOverlapService.convexHull(positions);
    var g = group.copyWith(
      photoIds: [...group.photoIds, pin.id],
      vertices: hull,
    );
    final justConfirmed = !g.confirmed && g.photoIds.length >= 3;
    if (justConfirmed) {
      g = g.copyWith(confirmed: true, createdAt: DateTime.now());
    }

    setState(() {
      _pins.add(pin);
      final i = _pending.indexWhere((p) => p.id == g.id);
      if (i >= 0) {
        _pending[i] = g;
      } else {
        _pending.add(g);
      }
    });

    if (g.confirmed) {
      // 確定 → Firestore(battle) へアップロードし、pending から外す
      _uploadAndOverride(g, result);
      setState(() => _pending.removeWhere((p) => p.id == g.id));
    }
    _toast('多角形にピンを追加しました');
  }

  void _addPinExisting(PolygonCreateResult result) {
    final candidates = _myConfirmed
        .where((p) => p.colorId == _myColorId && p.vertices.isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      PhotoService.deletePhotoFile(result.photoPath);
      _toast('追加できる多角形がありません');
      return;
    }
    WalkPolygon? target;
    double best = double.infinity;
    for (final p in candidates) {
      for (final v in p.vertices) {
        final dx = v.longitude - result.position.longitude;
        final dy = v.latitude - result.position.latitude;
        final sq = dx * dx + dy * dy;
        if (sq < best) {
          best = sq;
          target = p;
        }
      }
    }
    if (target == null) {
      PhotoService.deletePhotoFile(result.photoPath);
      _toast('追加できる多角形がありません');
      return;
    }

    final pin = PhotoPin(
      imagePath: result.photoPath,
      position: result.position,
      takenAt: result.takenAt,
      colorIds: result.colorIds,
      ownerUid: widget.myUid,
      polygonId: target.id,
    );
    final hull = PolygonOverlapService.convexHull(
        [...target.vertices, result.position]);
    final updated = target.copyWith(
      vertices: hull,
      photoIds: [...target.photoIds, pin.id],
      lastModifiedAt: DateTime.now(),
    );
    setState(() => _pins.add(pin));
    BattleService.upsertBattlePolygon(_battleId, updated);
    _uploadPhoto(updated, pin, result);
    _toast('既存の多角形にピンを追加しました');
  }

  Future<void> _uploadAndOverride(
      WalkPolygon g, PolygonCreateResult result) async {
    await BattleService.upsertBattlePolygon(_battleId, g);
    // 写真アップロード（構成ピン）
    for (final pin in _pins.where((p) => g.photoIds.contains(p.id))) {
      await _uploadPhoto(g, pin, null);
    }
    // 相手の古い多角形へ減算適用
    final candidates = _battlePolygons
        .where((p) =>
            p.ownerUid != widget.myUid &&
            p.confirmed &&
            p.isActive &&
            p.createdAt != null &&
            g.createdAt != null &&
            g.createdAt!.isAfter(p.createdAt!))
        .toList();
    await BattleService.applyOverrideInBattle(
      battleId: _battleId,
      a: g,
      candidates: candidates,
    );
  }

  Future<void> _uploadPhoto(
      WalkPolygon poly, PhotoPin pin, PolygonCreateResult? result) async {
    try {
      final url = await StorageUploadService.uploadBattlePhoto(
        battleId: _battleId,
        ownerUid: widget.myUid,
        photoId: pin.id,
        localPath: pin.imagePath,
      );
      await BattleService.upsertBattlePhoto(
        battleId: _battleId,
        photoId: pin.id,
        ownerUid: widget.myUid,
        polygonId: poly.id,
        lat: pin.position.latitude,
        lng: pin.position.longitude,
        takenAt: pin.takenAt,
        colorId: poly.colorId,
        imageUrl: url,
      );
    } catch (_) {}
  }

  void _openScore() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScorePanelScreen(
          battle: widget.battle,
          polygons: _battlePolygons,
          myUid: widget.myUid,
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _myColorId < colorPalette24.length
        ? colorPalette24[_myColorId]
        : const ColorRGB(128, 128, 128);
    final colorName =
        _myColorId < colorNames24.length ? colorNames24[_myColorId] : '';

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _pos,
            initialZoom: 14.0,
            minZoom: 3.0,
            maxZoom: 19.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.RunnerTests',
              maxZoom: 19,
            ),
            VersusModeOverlay(
              polygons: _battlePolygons,
              myUid: widget.myUid,
            ),
            if (_pins.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final pin in _pins)
                    Marker(
                      point: pin.position,
                      width: 48,
                      height: 48,
                      child: PhotoPinMarker(imagePath: pin.imagePath),
                    ),
                ],
              ),
            if (_hasLoc)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pos,
                    width: 13,
                    height: 13,
                    child: const CurrentLocationMarker(),
                  ),
                ],
              ),
          ],
        ),

        // 上部左：自分の色バッジ
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Color.fromRGBO(c.r, c.g, c.b, 1.0),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('あなたの色: $colorName',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // 上部中央：カウントダウン
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(20),
                  color: _remaining.inSeconds <= 60
                      ? const Color(0xFFD32F2F)
                      : Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Text(
                      _fmt(_remaining),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 上部右：強制終了
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.onRequestForceEnd,
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag, size: 16, color: Color(0xFFD32F2F)),
                        SizedBox(width: 4),
                        Text('強制終了',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFFD32F2F))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 右下：スコア + 多角形作成
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'battle_score',
                  onPressed: _openScore,
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.leaderboard),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'battle_create',
                  onPressed: _openCreateFlow,
                  child: const Icon(Icons.brush),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'battle_recenter',
                  onPressed: _hasLoc
                      ? () => _mapController.move(_pos, 16.0)
                      : null,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
