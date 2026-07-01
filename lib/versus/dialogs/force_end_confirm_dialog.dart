import 'package:flutter/material.dart';

/// 相手から強制終了を提案されたときの確認ポップアップ。
/// 「終了する」なら true、「終了しない」なら false を返す。
class ForceEndConfirmDialog {
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('強制終了の確認'),
        content: const Text('対決を強制終了しますか？'),
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
