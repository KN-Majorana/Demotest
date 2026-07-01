import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/battle.dart';
import '../models/polygon.dart';
import '../services/battle_service.dart';
import '../services/battle_snapshot_service.dart';
import '../versus_mode_overlay.dart';
import 'score_panel_screen.dart';

/// リザルト画面（全画面）。
///
/// - 中央：対決終了時点のマップ画像（challenger が生成して Storage に上げ、
///   両者が resultSnapshotUrl を購読して同じ画像を表示）。
/// - スコア表。
/// - 「リザルト画面を終了する」ボタン → 親が終了確認フローを進める。
class VersusResultScreen extends StatefulWidget {
  final Battle battle;
  final String myUid;

  /// 「リザルト画面を終了する」押下時（相手への確認は親が処理）
  final VoidCallback onRequestClose;

  const VersusResultScreen({
    super.key,
    required this.battle,
    required this.myUid,
    required this.onRequestClose,
  });

  @override
  State<VersusResultScreen> createState() => _VersusResultScreenState();
}

class _VersusResultScreenState extends State<VersusResultScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final MapController _mapController = MapController();

  StreamSubscription<List<WalkPolygon>>? _polySub;
  final List<WalkPolygon> _polygons = [];
  bool _snapshotTried = false;

  bool get _isChallenger => widget.battle.isChallenger(widget.myUid);

  @override
  void initState() {
    super.initState();
    // ended → result_shown（冪等）
    BattleService.markResultShown(widget.battle.id);

    _polySub =
        BattleService.watchBattlePolygons(widget.battle.id).listen((all) {
      if (!mounted) return;
      setState(() {
        _polygons
          ..clear()
          ..addAll(all);
      });
      _fitMap();
      _maybeCaptureSnapshot();
    }, onError: (Object e) => debugPrint('result polygons購読エラー: $e'));
  }

  @override
  void dispose() {
    _polySub?.cancel();
    super.dispose();
  }

  void _fitMap() {
    final pts = <LatLng>[];
    for (final p in _polygons) {
      pts.addAll(p.vertices);
    }
    if (pts.isEmpty) return;
    final lat = pts.map((e) => e.latitude).reduce((a, b) => a + b) /
        pts.length;
    final lng = pts.map((e) => e.longitude).reduce((a, b) => a + b) /
        pts.length;
    try {
      _mapController.move(LatLng(lat, lng), 14.0);
    } catch (_) {}
  }

  Future<void> _maybeCaptureSnapshot() async {
    if (!_isChallenger) return;
    if (_snapshotTried) return;
    if (widget.battle.resultSnapshotUrl != null) return;
    if (_polygons.isEmpty) return;
    _snapshotTried = true;
    // タイルの描画を少し待ってからキャプチャ
    await Future.delayed(const Duration(milliseconds: 1500));
    final url = await BattleSnapshotService.captureAndUpload(
      boundaryKey: _boundaryKey,
      battleId: widget.battle.id,
    );
    if (url != null) {
      await BattleService.setResultSnapshotUrl(widget.battle.id, url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.battle.resultSnapshotUrl;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('リザルト'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '対決終了',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // 中央のマップ画像
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (url != null)
                  ? Image.network(url, fit: BoxFit.cover)
                  : RepaintBoundary(
                      key: _boundaryKey,
                      child: FlutterMap(
                        mapController: _mapController,
                        options: const MapOptions(
                          initialCenter: LatLng(35.1815, 136.9066),
                          initialZoom: 14.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.RunnerTests',
                            maxZoom: 19,
                          ),
                          VersusModeOverlay(
                            polygons: _polygons,
                            myUid: widget.myUid,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          BattleScoreView(
            battle: widget.battle,
            polygons: _polygons,
            myUid: widget.myUid,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.onRequestClose,
            icon: const Icon(Icons.close),
            label: const Text('リザルト画面を終了する'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
