import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/friend_profile.dart';
import 'services/firestore_sync_service.dart';

/// フレンド追加・一覧、自分のコード確認・表示名変更を行う画面。
class FriendsScreen extends StatefulWidget {
  final FriendProfile myProfile;

  /// 表示名が変更されたとき親に通知する。
  final void Function(String newName)? onDisplayNameChanged;

  const FriendsScreen({
    super.key,
    required this.myProfile,
    this.onDisplayNameChanged,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _codeController = TextEditingController();
  late String _displayName;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.myProfile.displayName;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _adding = true);
    try {
      final friend = await FirestoreSyncService.addFriendByCode(code);
      _codeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${friend.displayName} を追加しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('表示名を変更'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '表示名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    await FirestoreSyncService.setDisplayName(result);
    if (!mounted) return;
    setState(() => _displayName = result);
    widget.onDisplayNameChanged?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.myProfile.code ?? '------';
    return Scaffold(
      appBar: AppBar(title: const Text('フレンド')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 自分の情報 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _editDisplayName,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('変更'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'あなたのフレンドコード',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          code,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'コピー',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('コピーしました')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── フレンド追加 ──
          const Text(
            'フレンドを追加',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: '相手のコード（6文字）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _adding ? null : _addFriend,
                child: _adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('追加'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── フレンド一覧 ──
          const Text(
            'フレンド一覧',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<FriendProfile>>(
            stream: FirestoreSyncService.watchFriends(),
            builder: (context, snapshot) {
              final friends = snapshot.data ?? const <FriendProfile>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (friends.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'まだフレンドがいません。\n相手のコードを入力して追加しましょう。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final f in friends)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(f.displayName),
                      subtitle: f.code != null ? Text('コード: ${f.code}') : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () =>
                            FirestoreSyncService.removeFriend(f.uid),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
