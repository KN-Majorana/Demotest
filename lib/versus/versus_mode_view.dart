import 'dart:async';

import 'package:flutter/material.dart';

import '../models/battle.dart';
import '../models/friend_profile.dart';
import '../services/battle_service.dart';
import 'dialogs/challenge_incoming_dialog.dart';
import 'dialogs/force_end_confirm_dialog.dart';
import 'dialogs/result_close_confirm_dialog.dart';
import 'versus_battle_screen.dart';
import 'versus_lobby_screen.dart';
import 'versus_result_screen.dart';

/// 対戦モードのルート。自分の battle 状態を購読し、
/// idle→lobby / pending→待機 / active→battle / ended→result を出し分ける。
/// 着信・強制終了確認・リザルト終了確認の各ダイアログもここで管理する。
class VersusModeView extends StatefulWidget {
  final FriendProfile myProfile;
  final void Function(String)? onDisplayNameChanged;

  const VersusModeView({
    super.key,
    required this.myProfile,
    this.onDisplayNameChanged,
  });

  @override
  State<VersusModeView> createState() => _VersusModeViewState();
}

class _VersusModeViewState extends State<VersusModeView> {
  StreamSubscription<Battle?>? _sub;
  Timer? _heartbeat;
  Battle? _battle;

  bool _incomingOpen = false;
  bool _forceEndOpen = false;
  bool _resultCloseOpen = false;

  String get _uid => widget.myProfile.uid;

  @override
  void initState() {
    super.initState();
    BattleService.touchLastSeen(_uid);
    _heartbeat = Timer.periodic(
        const Duration(seconds: 60), (_) => BattleService.touchLastSeen(_uid));

    _sub = BattleService.watchActiveBattleFor(_uid).listen((b) {
      if (!mounted) return;
      setState(() => _battle = b);
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleDialogs(b));
    }, onError: (Object e) => debugPrint('battle購読エラー: $e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _heartbeat?.cancel();
    super.dispose();
  }

  Future<void> _handleDialogs(Battle? b) async {
    if (!mounted || b == null) return;

    // 対決の着信（自分が opponent、pending）
    if (b.status == BattleStatus.pending &&
        b.opponentUid == _uid &&
        !b.isExpiredNow &&
        !_incomingOpen) {
      _incomingOpen = true;
      final ok = await ChallengeIncomingDialog.show(
        context,
        challengerName: b.challengerName,
      );
      _incomingOpen = false;
      if (ok == true) {
        await BattleService.acceptChallenge(b.id);
      } else {
        await BattleService.declineChallenge(b.id);
      }
      return;
    }

    // 強制終了の確認（相手が提案）
    if (b.status == BattleStatus.active &&
        b.forceEndRequestBy != null &&
        b.forceEndRequestBy != _uid &&
        !_forceEndOpen) {
      _forceEndOpen = true;
      final ok = await ForceEndConfirmDialog.show(context);
      _forceEndOpen = false;
      if (ok == true) {
        await BattleService.confirmForceEnd(b.id);
      } else {
        await BattleService.cancelForceEnd(b.id);
      }
      return;
    }

    // リザルト終了の確認（相手が提案）
    if ((b.status == BattleStatus.ended ||
            b.status == BattleStatus.resultShown) &&
        b.resultCloseRequestBy != null &&
        b.resultCloseRequestBy != _uid &&
        !_resultCloseOpen) {
      _resultCloseOpen = true;
      final ok = await ResultCloseConfirmDialog.show(context);
      _resultCloseOpen = false;
      if (ok == true) {
        await BattleService.confirmResultClose(b.id);
      } else {
        await BattleService.cancelResultClose(b.id);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _battle;

    if (b == null) {
      return VersusLobbyScreen(
        myProfile: widget.myProfile,
        onDisplayNameChanged: widget.onDisplayNameChanged,
      );
    }

    switch (b.status) {
      case BattleStatus.pending:
        if (b.isChallenger(_uid)) {
          return _waiting(
            '${b.opponentName} の応答を待っています…',
            actionLabel: '申込をキャンセル',
            onAction: () => BattleService.cancelChallenge(b.id),
          );
        }
        // opponent はダイアログ表示中。背景はロビー。
        return VersusLobbyScreen(
          myProfile: widget.myProfile,
          onDisplayNameChanged: widget.onDisplayNameChanged,
        );

      case BattleStatus.active:
        final battleScreen = VersusBattleScreen(
          battle: b,
          myUid: _uid,
          onRequestForceEnd: () => BattleService.requestForceEnd(b.id, _uid),
        );
        // 自分が強制終了を提案中 → 待機オーバーレイ
        if (b.forceEndRequestBy == _uid) {
          return Stack(children: [
            battleScreen,
            _overlay('相手に確認中…'),
          ]);
        }
        return battleScreen;

      case BattleStatus.ended:
      case BattleStatus.resultShown:
        final result = VersusResultScreen(
          battle: b,
          myUid: _uid,
          onRequestClose: () =>
              BattleService.requestResultClose(b.id, _uid),
        );
        if (b.resultCloseRequestBy == _uid) {
          return Stack(children: [
            result,
            _overlay('相手に確認中…'),
          ]);
        }
        return result;

      default:
        // cleared/declined/expired など → ロビーへ
        return VersusLobbyScreen(
          myProfile: widget.myProfile,
          onDisplayNameChanged: widget.onDisplayNameChanged,
        );
    }
  }

  Widget _waiting(String message,
      {required String actionLabel, required VoidCallback onAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }

  Widget _overlay(String message) {
    return Positioned.fill(
      child: Container(
        color: Colors.black45,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
