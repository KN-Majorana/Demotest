import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'area_ranking_screen.dart';
import 'color_collage_screen.dart';
import 'color_extraction.dart';
import 'color_picker_sheet.dart';
import 'fog_settings_service.dart';
import 'current_location_marker.dart';
import 'fog_overlay.dart';
import 'friends_screen.dart';
import 'ghost_track.dart';
import 'location_service.dart';
import 'map_mode.dart';
import 'mode_switcher.dart';
import 'photo_detail_sheet.dart';
import 'photo_list_screen.dart';
import 'photo_pin.dart';
import 'photo_pin_marker.dart';
import 'photo_service.dart';
import 'polygon_choice_sheet.dart';
import 'recording_controls.dart';
import 'track_picker_sheet.dart';
import 'track_storage_service.dart';
import 'versus_mode_overlay.dart';
import 'walk_track.dart';
import 'ghost_marker.dart';
import 'models/friend_profile.dart';
import 'models/location_point.dart';
import 'models/polygon.dart';
import 'services/exif_service.dart';
import 'services/export_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/firestore_sync_service.dart';
import 'services/photo_pin_storage_service.dart';
import 'services/polygon_overlap_service.dart';
import 'services/polygon_storage_service.dart';
import 'services/storage_upload_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = const LatLng(35.1815, 136.9066);
  bool _hasLocation = false;

  // モード状態
  MapMode _mode = MapMode.normal;

  // 再生モードの速度倍率
  static const double _ghostSpeed = 4.0;

  // 記録状態
  WalkTrack? _currentTrack;
  StreamSubscription<LatLng>? _positionSub;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  // 過去の散歩記録(起動時に永続ストレージから読み込む)
  final List<WalkTrack> _savedTracks = [];

  // 再生モード関連
  GhostTrack? _ghost;
  Timer? _ghostTimer;
  DateTime? _ghostStartedAt;
  LatLng? _ghostPosition;

  // 写真ピン(撮影した位置に表示)
  final List<PhotoPin> _photoPins = [];

  // 自分の多角形（準備中グループを含む。ローカル永続化）
  final List<WalkPolygon> _myPolygons = [];

  // 霧クリア設定: ピン間の最大距離（メートル）
  double _fogMaxDistance = FogSettingsService.defaultMaxDistance;

  // ─── 対戦モード（versus）関連 ───
  bool _versusJoined = false;
  FriendProfile? _myProfile;
  final List<FriendProfile> _friends = [];
  final List<WalkPolygon> _remotePolygons = [];
  StreamSubscription<List<WalkPolygon>>? _polygonSub;
  StreamSubscription<List<FriendProfile>>? _friendSub;

  bool get _isRecording => _currentTrack != null && _currentTrack!.isActive;

  /// 対戦モードで描画・集計する多角形（自分の確定分＋フレンドの確定分）。
  List<WalkPolygon> get _visiblePolygons {
    final friendUids = _friends.map((f) => f.uid).toSet();
    final mine = _myPolygons.where((p) => p.confirmed).toList();
    final fromFriends = _remotePolygons.where((p) =>
        p.confirmed &&
        friendUids.contains(p.ownerUid) &&
        p.ownerUid != _myProfile?.uid);
    return [...mine, ...fromFriends];
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadSavedTracks();
    _loadPhotoPins();
    _loadMyPolygons();
    _loadFogSettings();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _elapsedTimer?.cancel();
    _ghostTimer?.cancel();
    _polygonSub?.cancel();
    _friendSub?.cancel();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
      });
      _mapController.move(_currentPosition, 15.0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('位置情報取得失敗: $e')));
    }
  }

  Future<void> _loadSavedTracks() async {
    try {
      final tracks = await TrackStorageService.loadAll();
      if (!mounted) return;
      setState(() {
        _savedTracks
          ..clear()
          ..addAll(tracks);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('過去の記録の読み込みに失敗: $e')));
    }
  }

  Future<void> _loadPhotoPins() async {
    try {
      final pins = await PhotoPinStorageService.loadAll();
      if (!mounted) return;
      setState(() {
        _photoPins
          ..clear()
          ..addAll(pins);
      });
    } catch (_) {}
  }

  Future<void> _loadMyPolygons() async {
    try {
      final polys = await PolygonStorageService.loadAll();
      if (!mounted) return;
      setState(() {
        _myPolygons
          ..clear()
          ..addAll(polys);
      });
    } catch (_) {}
  }

  Future<void> _saveMyPolygons() async {
    try {
      await PolygonStorageService.saveAll(_myPolygons);
    } catch (_) {}
  }

  Future<void> _loadFogSettings() async {
    final dist = await FogSettingsService.loadMaxDistance();
    if (!mounted) return;
    setState(() => _fogMaxDistance = dist);
  }

  /// 霧設定ダイアログを表示する
  Future<void> _showFogSettings() async {
    double tempDistance = _fogMaxDistance;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final km = (tempDistance / 1000).toStringAsFixed(1);
          return AlertDialog(
            title: const Text('霧クリア設定'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '同じ主要色のピン同士がこの距離以内にある場合のみ、霧を晴らす対象として扱います。',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '$km km（${tempDistance.round()} m）',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Slider(
                  value: tempDistance,
                  min: 100,
                  max: 5000,
                  divisions: 49,
                  label: '${tempDistance.round()} m',
                  onChanged: (v) =>
                      setDialogState(() => tempDistance = v.roundToDouble()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('100 m', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    Text('5 km', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _fogMaxDistance = tempDistance);
                  FogSettingsService.saveMaxDistance(tempDistance);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _savePhotoPins() async {
    try {
      await PhotoPinStorageService.saveAll(_photoPins);
    } catch (_) {}
  }

  void _deletePhotoPin(PhotoPin pin) {
    setState(() {
      _photoPins.removeWhere((p) => p.id == pin.id);
      // 所属多角形の頂点を再計算（準備中に戻る場合もある）
      if (pin.polygonId != null) {
        _recomputeGroup(pin.polygonId!);
      }
    });
    _savePhotoPins();
    _saveMyPolygons();
  }

  /// 指定 ID の多角形を、現在のメンバーピンから再計算する。
  void _recomputeGroup(String polygonId) {
    final idx = _myPolygons.indexWhere((p) => p.id == polygonId);
    if (idx < 0) return;
    final members =
        _photoPins.where((p) => p.polygonId == polygonId).toList();
    final positions = members.map((p) => p.position).toList();
    var g = _myPolygons[idx].copyWith(
      photoIds: members.map((p) => p.id).toList(),
      vertices: PolygonOverlapService.convexHull(positions),
    );
    if (members.length < 3) {
      g = g.copyWith(confirmed: false);
    }
    _myPolygons[idx] = g;
    if (g.confirmed && _versusJoined) {
      _syncPolygonUp(g);
    }
  }

  // ─── 記録開始 ───
  void _startRecording() {
    final now = DateTime.now();
    setState(() {
      _currentTrack = WalkTrack(
        id: now.millisecondsSinceEpoch.toString(),
        startedAt: now,
        points: _hasLocation
            ? [TrackPoint(position: _currentPosition, timestamp: now)]
            : [],
      );
      _elapsed = Duration.zero;
    });

    // 位置情報の継続取得
    _positionSub = LocationService.watchPosition().listen((pos) {
      if (!mounted || !_isRecording) return;
      setState(() {
        _currentPosition = pos;
        _hasLocation = true;
        _currentTrack = _currentTrack!.copyWith(
          points: [
            ..._currentTrack!.points,
            TrackPoint(position: pos, timestamp: DateTime.now()),
          ],
        );
      });
    });

    // 経過時間タイマー(1秒ごと)
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) return;
      setState(() {
        _elapsed = DateTime.now().difference(_currentTrack!.startedAt);
      });
    });
  }

  // ─── 記録停止 ───
  Future<void> _stopRecording() async {
    _positionSub?.cancel();
    _positionSub = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    final count = _currentTrack?.points.length ?? 0;
    final finished = _currentTrack?.copyWith(endedAt: DateTime.now());
    setState(() {
      _currentTrack = finished;
      if (finished != null && finished.points.isNotEmpty) {
        _savedTracks.add(finished);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('記録を停止しました($count点)')));
    }

    // 永続化
    if (finished != null && finished.points.isNotEmpty) {
      try {
        await TrackStorageService.save(finished);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('記録の保存に失敗: $e')));
      }
    }
  }

  // ─── モード切替時のフック ───
  void _onModeChanged(MapMode mode) {
    setState(() => _mode = mode);
    if (mode == MapMode.animation) {
      _startGhostPlayback();
    } else {
      _stopGhostPlayback();
    }

    if (mode == MapMode.versus) {
      if (!_versusJoined) {
        _enterVersus();
      } else {
        _subscribeVersus();
      }
    } else {
      _unsubscribeVersus();
    }
  }

  // ─── 再生開始 ───
  // [target] を省略すると最新の保存済み軌跡を使う。
  void _startGhostPlayback({WalkTrack? target}) {
    _stopGhostPlayback();

    final selected =
        target ?? (_savedTracks.isNotEmpty ? _savedTracks.last : null);

    if (selected == null || selected.points.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('再生できる記録がありません')));
      }
      return;
    }

    final ghost = GhostTrack(selected, speed: _ghostSpeed);
    setState(() {
      _ghost = ghost;
      _ghostStartedAt = DateTime.now();
      _ghostPosition = selected.points.first.position;
    });

    // 軌跡の先頭にカメラを寄せる
    _mapController.move(selected.points.first.position, 16.0);

    _ghostTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _ghost == null || _ghostStartedAt == null) return;
      var elapsed = DateTime.now().difference(_ghostStartedAt!);

      // 終端まで行ったらループ再生する
      if (_ghost!.isFinished(elapsed)) {
        _ghostStartedAt = DateTime.now();
        elapsed = Duration.zero;
      }

      final pos = _ghost!.positionAt(elapsed);
      if (pos != null) {
        setState(() => _ghostPosition = pos);
      }
    });
  }

  // ─── 再生停止 ───
  void _stopGhostPlayback() {
    _ghostTimer?.cancel();
    _ghostTimer = null;
    setState(() {
      _ghost = null;
      _ghostStartedAt = null;
      _ghostPosition = null;
    });
  }

  // ─── 軌跡選択シートを開く ───
  Future<void> _openTrackPicker() async {
    final selected = await TrackPickerSheet.show(
      context,
      tracks: _savedTracks,
      selectedId: _ghost?.track.id,
    );
    if (selected != null && mounted) {
      _startGhostPlayback(target: selected);
    }
  }

  // ════════════════════════════════════════════
  // 対戦モード（versus）
  // ════════════════════════════════════════════

  /// 対戦に参加（匿名サインイン＋ユーザ作成＋購読開始）。
  Future<void> _enterVersus() async {
    try {
      final uid = await FirebaseAuthService.ensureSignedIn();
      final existing = await FirestoreSyncService.getMyProfile();
      final name = existing?.displayName ??
          'プレイヤー${uid.substring(uid.length - 4).toUpperCase()}';
      final profile = await FirestoreSyncService.ensureUserDoc(name);
      if (!mounted) return;

      setState(() {
        _myProfile = profile;
        _versusJoined = true;
        // ローカルで先に作った多角形に正式な所有者情報を付与
        for (int i = 0; i < _myPolygons.length; i++) {
          _myPolygons[i] = _myPolygons[i].copyWith(
            ownerUid: profile.uid,
            ownerName: profile.displayName,
          );
        }
      });
      _saveMyPolygons();
      _subscribeVersus();

      // 既存の確定多角形を Firestore に同期
      for (final g in _myPolygons.where((p) => p.confirmed)) {
        _syncPolygonUp(g);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('対戦モードに接続できませんでした（ローカル表示のみ）: $e');
    }
  }

  void _subscribeVersus() {
    _polygonSub?.cancel();
    _friendSub?.cancel();
    _polygonSub = FirestoreSyncService.watchAllPolygons().listen((all) {
      if (!mounted) return;
      setState(() {
        _remotePolygons
          ..clear()
          ..addAll(all);
      });
    });
    _friendSub = FirestoreSyncService.watchFriends().listen((friends) {
      if (!mounted) return;
      setState(() {
        _friends
          ..clear()
          ..addAll(friends);
      });
    });
  }

  void _unsubscribeVersus() {
    _polygonSub?.cancel();
    _polygonSub = null;
    _friendSub?.cancel();
    _friendSub = null;
  }

  /// 多角形（と構成写真）を Firestore / Storage に同期（ベストエフォート）。
  Future<void> _syncPolygonUp(WalkPolygon g) async {
    if (!_versusJoined) return;
    try {
      final members =
          _photoPins.where((p) => g.photoIds.contains(p.id)).toList();
      for (final pin in members) {
        try {
          final url = await StorageUploadService.uploadPhoto(
            ownerUid: g.ownerUid,
            photoId: pin.id,
            localPath: pin.imagePath,
          );
          await FirestoreSyncService.upsertPhoto(
            photoId: pin.id,
            ownerUid: g.ownerUid,
            polygonId: g.id,
            lat: pin.position.latitude,
            lng: pin.position.longitude,
            takenAt: pin.takenAt,
            colorId: g.colorId,
            imageUrl: url,
          );
        } catch (_) {
          // 個別写真の失敗は無視して続行
        }
      }
      await FirestoreSyncService.upsertPolygon(g);
    } catch (_) {
      // 同期失敗はローカル状態を優先（致命的でない）
    }
  }

  void _openRanking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AreaRankingScreen(
          polygons: _visiblePolygons,
          myUid: _myProfile?.uid,
          friendCount: _friends.length,
        ),
      ),
    );
  }

  void _openFriends() {
    final profile = _myProfile;
    if (profile == null) {
      _toast('対戦モードに接続中です…少し待って再度お試しください');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendsScreen(
          myProfile: profile,
          onDisplayNameChanged: (name) {
            setState(() {
              _myProfile = FriendProfile(
                uid: profile.uid,
                displayName: name,
                code: profile.code,
              );
            });
          },
        ),
      ),
    );
  }

  // ─── 写真撮影（機能3：新規作成 / 既存追加 を選択） ───
  Future<void> _takePhoto() async {
    try {
      // 撮影直前に最新の現在地を取りに行く
      LatLng photoPosition = _currentPosition;
      try {
        photoPosition = await LocationService.getCurrentPosition();
      } catch (_) {}

      final path = await PhotoService.takeAndSavePhoto();
      if (path == null) return; // キャンセル
      if (!mounted) return;

      // 写真の主要色を抽出（24色パレットのインデックス）
      final colorIds = await extractColorIdsFromPath(path);
      if (!mounted) return;

      // [A] 新規作成 / [B] 既存に追加 を選択
      final choice = await PolygonChoiceSheet.show(
        context,
        existingPolygons: _myPolygons.where((p) => p.confirmed).toList(),
      );
      if (choice == null) {
        await PhotoService.deletePhotoFile(path); // 破棄
        return;
      }
      if (!mounted) return;

      if (choice.kind == PolygonChoiceKind.createNew) {
        // [A] 色を選ばせる
        final colorId = await ColorPickerSheet.show(context);
        if (colorId == null) {
          await PhotoService.deletePhotoFile(path);
          return;
        }
        // 指定色と判定色が一致しない → ピンを立てない・写真破棄
        if (!colorIds.contains(colorId)) {
          await PhotoService.deletePhotoFile(path);
          _toast('指定した色と一致しません');
          return;
        }
        final group = _pendingGroupForColor(colorId) ?? _createNewGroup(colorId);
        _addPinAndAttach(path, photoPosition, colorIds, group);
        final name =
            colorId < colorNames24.length ? colorNames24[colorId] : '';
        _toast('「$name」の多角形にピンを追加しました');
      } else {
        // [B] 既存多角形に追加。色が一致する場合のみ。
        final target = choice.target!;
        if (!colorIds.contains(target.colorId)) {
          await PhotoService.deletePhotoFile(path);
          _toast('色が一致しません');
          return;
        }
        _addPinAndAttach(path, photoPosition, colorIds, target);
        _toast('既存の多角形にピンを追加しました');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撮影に失敗: $e')));
    }
  }

  /// 準備中（未確定）の同色グループを探す。
  WalkPolygon? _pendingGroupForColor(int colorId) {
    for (final g in _myPolygons) {
      if (!g.confirmed && g.colorId == colorId) return g;
    }
    return null;
  }

  /// 新しい準備中グループを生成（まだ _myPolygons には追加しない）。
  WalkPolygon _createNewGroup(int colorId) {
    final id = 'poly_${DateTime.now().microsecondsSinceEpoch}';
    return WalkPolygon(
      id: id,
      ownerUid: _myProfile?.uid ?? 'local',
      ownerName: _myProfile?.displayName ?? '',
      colorId: colorId,
      vertices: const [],
      createdAt: null,
      photoIds: const [],
      confirmed: false,
    );
  }

  /// ピンを立てて [group] に頂点を追加し、凸包を再計算する。
  /// 3 枚目で多角形を確定し、対戦参加中なら Firestore に同期する。
  void _addPinAndAttach(
    String path,
    LatLng pos,
    List<int> colorIds,
    WalkPolygon group,
  ) {
    final pin = PhotoPin(
      imagePath: path,
      position: pos,
      takenAt: DateTime.now(),
      colorIds: colorIds,
      ownerUid: _myProfile?.uid,
      polygonId: group.id,
    );

    // 既存メンバー位置 ＋ 新規ピン位置から凸包を再計算
    final positions = [
      ..._photoPins
          .where((p) => p.polygonId == group.id)
          .map((p) => p.position),
      pos,
    ];

    var g = group.copyWith(
      photoIds: [...group.photoIds, pin.id],
      vertices: PolygonOverlapService.convexHull(positions),
    );

    // 3 枚目で確定
    if (!g.confirmed && g.photoIds.length >= 3) {
      g = g.copyWith(
        confirmed: true,
        createdAt: DateTime.now(),
        ownerUid: _myProfile?.uid ?? group.ownerUid,
        ownerName: _myProfile?.displayName ?? group.ownerName,
      );
    }

    setState(() {
      _photoPins.add(pin);
      _upsertGroup(g);
    });

    _savePhotoPins();
    _saveMyPolygons();

    if (g.confirmed && _versusJoined) {
      _syncPolygonUp(g);
    }
  }

  void _upsertGroup(WalkPolygon g) {
    final i = _myPolygons.indexWhere((p) => p.id == g.id);
    if (i >= 0) {
      _myPolygons[i] = g;
    } else {
      _myPolygons.add(g);
    }
  }

  void _openPhotoList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoListScreen(
          photoPins: _photoPins,
          onDeletePins: (ids) {
            setState(() {
              _photoPins.removeWhere((p) => ids.contains(p.id));
              // 影響する多角形を再計算
              final affected = _myPolygons
                  .where((g) => g.photoIds.any(ids.contains))
                  .map((g) => g.id)
                  .toList();
              for (final pid in affected) {
                _recomputeGroup(pid);
              }
            });
            _savePhotoPins();
            _saveMyPolygons();
          },
        ),
      ),
    );
  }

  void _openColorCollage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ColorCollageScreen(photoPins: _photoPins),
      ),
    );
  }

  // ─── ギャラリーからEXIF位置情報を読み込んでピンを追加 ───
  Future<void> _importFromGallery() async {
    try {
      final points = await ExifService.getLocationsFromGallery();
      if (points.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報のある写真が見つかりませんでした')),
        );
        return;
      }
      if (!mounted) return;

      // 各写真の主要色を抽出してからピンを追加
      final List<PhotoPin> newPins = [];
      for (final p in points) {
        final path = p.imagePath ?? '';
        final colorIds = path.isNotEmpty
            ? await extractColorIdsFromPath(path)
            : <int>[];
        newPins.add(PhotoPin(
          imagePath: path,
          position: LatLng(p.latitude, p.longitude),
          takenAt: p.timestamp ?? DateTime.now(),
          colorIds: colorIds,
        ));
      }

      if (!mounted) return;
      setState(() {
        _photoPins.addAll(newPins);
      });
      _savePhotoPins();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${points.length}件の位置情報を読み込みました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('読み込み失敗: $e')),
      );
    }
  }

  // ─── 写真ピンをCSVエクスポート ───
  Future<void> _exportCsv() async {
    try {
      final points = _photoPins.map((pin) => LocationPoint(
        latitude: pin.position.latitude,
        longitude: pin.position.longitude,
        source: LocationSource.camera,
        timestamp: pin.takenAt,
        imagePath: pin.imagePath,
        label: pin.imagePath.split('/').last,
      )).toList();
      await ExportService.exportToCsv(points);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エクスポート失敗: $e')),
      );
    }
  }

  // ─── 再生モード時の「軌跡選択カード」 ───
  Widget _buildTrackPickerButton() {
    final current = _ghost?.track;
    final label = current == null
        ? '記録を選ぶ'
        : '${current.startedAt.month}/${current.startedAt.day} '
              '${current.startedAt.hour.toString().padLeft(2, '0')}:'
              '${current.startedAt.minute.toString().padLeft(2, '0')} の散歩';

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openTrackPicker,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: Color(0xFF2E7D32)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '再生中の記録',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_less_rounded, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  /// 対戦モード時の下部ステータスカード（接続状態・フレンド数）。
  Widget _buildVersusStatusCard() {
    final name = _myProfile?.displayName ?? '接続中…';
    final code = _myProfile?.code;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openFriends,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.sports_kabaddi, color: Color(0xFFD32F2F)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      code != null
                          ? 'コード $code ・ フレンド ${_friends.length}人'
                          : 'フレンド ${_friends.length}人',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.group_outlined, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackPoints =
        _currentTrack?.points.map((p) => p.position).toList() ?? [];

    // 再生モード時にゴーストが辿っている軌跡の全座標
    final ghostFullPath = _mode == MapMode.animation && _ghost != null
        ? _ghost!.track.points.map((p) => p.position).toList()
        : const <LatLng>[];

    return Scaffold(
      body: Stack(
        children: [
          // ── 地図本体 ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 13.0,
              minZoom: 3.0,
              maxZoom: 19.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.RunnerTests',
                maxZoom: 19,
              ),
              // 通常モード: 記録中の軌跡を青線で表示
              if (_mode == MapMode.normal && trackPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints,
                      strokeWidth: 5,
                      color: Colors.blue,
                    ),
                  ],
                ),
              // 再生モード: 再生対象の軌跡全体を緑で薄く表示
              if (_mode == MapMode.animation && ghostFullPath.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: ghostFullPath,
                      strokeWidth: 4,
                      color: Colors.green.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              // 霧オーバーレイ（同色ピン群の凸包ポリゴンで霧を晴らす）
              if (_mode == MapMode.fog)
                FogOverlay(
                  photoPins: _photoPins,
                  maxDistanceMeters: _fogMaxDistance,
                ),
              // 対戦オーバーレイ（自分＋フレンドの多角形）
              if (_mode == MapMode.versus)
                VersusModeOverlay(
                  polygons: _visiblePolygons,
                  myUid: _myProfile?.uid,
                ),
              // 写真ピン(全モードで表示)
              if (_photoPins.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final pin in _photoPins)
                      Marker(
                        point: pin.position,
                        width: 56,
                        height: 56,
                        child: GestureDetector(
                          onTap: () => PhotoDetailSheet.show(
                            context,
                            pin,
                            onDelete: () => _deletePhotoPin(pin),
                          ),
                          child: PhotoPinMarker(imagePath: pin.imagePath),
                        ),
                      ),
                  ],
                ),
              // 現在地マーカー(再生モード以外)
              if (_hasLocation && _mode != MapMode.animation)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 13,
                      height: 13,
                      child: const CurrentLocationMarker(),
                    ),
                  ],
                ),
              // ゴーストマーカー(再生モード時)
              if (_mode == MapMode.animation && _ghostPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _ghostPosition!,
                      width: 13,
                      height: 13,
                      child: const GhostMarker(),
                    ),
                  ],
                ),
            ],
          ),

          // ── 上部:モード切替 ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ModeSwitcher(
                    currentMode: _mode,
                    onModeChanged: _onModeChanged,
                  ),
                ),
              ),
            ),
          ),

          // ── 下部:記録コントロール(通常モード時のみ) ──
          if (_mode == MapMode.normal)
            Positioned(
              left: 16,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: RecordingControls(
                    isRecording: _isRecording,
                    pointCount: _currentTrack?.points.length ?? 0,
                    elapsed: _elapsed,
                    onStart: _startRecording,
                    onStop: _stopRecording,
                  ),
                ),
              ),
            ),

          // ── 下部:軌跡選択カード(再生モード時のみ) ──
          if (_mode == MapMode.animation)
            Positioned(
              left: 16,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildTrackPickerButton(),
                ),
              ),
            ),

          // ── 下部:対戦ステータスカード(対戦モード時のみ) ──
          if (_mode == MapMode.versus)
            Positioned(
              left: 16,
              right: 76,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildVersusStatusCard(),
                ),
              ),
            ),
        ],
      ),

      // 右下のFAB群(縦並び)
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 対戦モード: ランキング & フレンド
          if (_mode == MapMode.versus) ...[
            FloatingActionButton.small(
              onPressed: _openRanking,
              heroTag: 'area_ranking',
              tooltip: '面積ランキング',
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              child: const Icon(Icons.leaderboard),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              onPressed: _openFriends,
              heroTag: 'friends',
              tooltip: 'フレンド',
              child: const Icon(Icons.group_outlined),
            ),
            const SizedBox(height: 8),
          ],
          // CSVエクスポート
          if (_photoPins.isNotEmpty)
            FloatingActionButton.small(
              onPressed: _exportCsv,
              heroTag: 'csv_export',
              tooltip: 'CSVエクスポート',
              child: const Icon(Icons.share_outlined),
            ),
          if (_photoPins.isNotEmpty) const SizedBox(height: 8),
          // 霧モード設定（霧モード時のみ表示）
          if (_mode == MapMode.fog) ...[
            FloatingActionButton.small(
              onPressed: _showFogSettings,
              heroTag: 'fog_settings',
              tooltip: '霧クリア距離の設定',
              child: const Icon(Icons.tune),
            ),
            const SizedBox(height: 8),
          ],
          // カラーハンティングコラージュ
          FloatingActionButton.small(
            onPressed: _openColorCollage,
            heroTag: 'color_collage',
            tooltip: 'カラーハンティング',
            child: const Icon(Icons.palette_outlined),
          ),
          const SizedBox(height: 8),
          // ギャラリーからEXIF読み込み
          FloatingActionButton.small(
            onPressed: _importFromGallery,
            heroTag: 'exif_import',
            tooltip: 'ギャラリーから読み込み',
            child: const Icon(Icons.perm_media_outlined),
          ),
          const SizedBox(height: 8),
          // 写真一覧
          FloatingActionButton.small(
            onPressed: _openPhotoList,
            heroTag: 'photo_list',
            child: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(height: 8),
          // 写真撮影(再生モード中は隠す)
          if (_mode != MapMode.animation)
            FloatingActionButton.small(
              onPressed: _takePhoto,
              heroTag: 'photo_take',
              child: const Icon(Icons.camera_alt),
            ),
          if (_mode != MapMode.animation) const SizedBox(height: 8),
          // 現在地に戻る
          FloatingActionButton.small(
            onPressed: _hasLocation
                ? () => _mapController.move(_currentPosition, 16.0)
                : null,
            heroTag: 'recenter',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}
