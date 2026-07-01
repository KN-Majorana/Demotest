import 'package:flutter/material.dart';

/// 相手からリザルト画面の終了を提案されたときの確認ポップアップ。
/// 「終了する」なら true、「終了しない」なら false を返す。
class ResultCloseConfirmDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('リザルト画面の終了'),
        content: const Text('リザルト画面を終了しますか？\n（対戦データは完全に削除されます）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('終了しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('終了する'),
          ),
        ],
      ),
    );
  }
}
