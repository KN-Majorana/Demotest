import 'package:flutter/material.dart';

import '../friends_screen.dart';
import '../models/friend_profile.dart';
import '../services/battle_service.dart';
import '../services/firestore_sync_service.dart';

/// 対戦モードの idle 状態：フレンドから対決相手を選ぶ画面。
class VersusLobbyScreen extends StatefulWidget {
  final FriendProfile myProfile;

  /// 表示名変更を親へ通知（フレンド画面から変更した場合）
  final void Function(String)? onDisplayNameChanged;

  const VersusLobbyScreen({
    super.key,
    required this.myProfile,
    this.onDisplayNameChanged,
  });

  @override
  State<VersusLobbyScreen> createState() => _VersusLobbyScreenState();
}

class _VersusLobbyScreenState extends State<VersusLobbyScreen> {
  // 時間制限の選択肢（秒）
  static const _timeLimits = <String, int>{
    '15分': 15 * 60,
    '30分': 30 * 60,
    '1時間': 60 * 60,
    '2時間': 120 * 60,
  };
  String _selectedLimit = '1時間';
  bool _sending = false;

  Future<void> _challenge(FriendProfile friend) async {
    setState(() => _sending = true);
    try {
      await BattleService.requestChallenge(
        challengerUid: widget.myProfile.uid,
        challengerName: widget.myProfile.displayName,
        opponentUid: friend.uid,
        opponentName: friend.displayName,
        timeLimitSec: _timeLimits[_selectedLimit]!,
      );
      // pending 作成後は親（versus_mode_view）が battle 状態を検知して
      // 待機画面へ自動遷移する。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.sports_kabaddi, color: Color(0xFFD32F2F)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '対戦相手を選ぶ',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'フレンド管理',
                  icon: const Icon(Icons.group_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FriendsScreen(
                          myProfile: widget.myProfile,
                          onDisplayNameChanged: widget.onDisplayNameChanged,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('制限時間：'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedLimit,
                  items: _timeLimits.keys
                      .map((k) =>
                          DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedLimit = v ?? _selectedLimit),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<FriendProfile>>(
              stream: FirestoreSyncService.watchFriends(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final friends = snapshot.data ?? const <FriendProfile>[];
                if (friends.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'まだフレンドがいません。\n右上のフレンド管理から追加してください。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: friends.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final f = friends[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(f.displayName),
                      subtitle: _OnlineText(uid: f.uid),
                      trailing: FilledButton(
                        onPressed: _sending ? null : () => _challenge(f),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                        ),
                        child: const Text('対戦相手にする'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// users/{uid}.lastSeen を読み、近似のオンライン状態を表示（best-effort）。
class _OnlineText extends StatelessWidget {
  final String uid;
  const _OnlineText({required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: BattleService.readLastSeen(uid),
      builder: (context, snap) {
        final ls = snap.data;
        final online = ls != null &&
            DateTime.now().millisecondsSinceEpoch - ls < 2 * 60 * 1000;
        return Row(
          children: [
            Icon(Icons.circle,
                size: 10,
                color: online ? Colors.green : Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(online ? 'オンライン' : 'オフライン',
                style: const TextStyle(fontSize: 12)),
          ],
        );
      },
    );
  }
}
