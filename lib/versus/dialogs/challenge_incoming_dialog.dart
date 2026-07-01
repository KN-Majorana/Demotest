import 'package:flutter/material.dart';

/// 対決の申込を受けたときのポップアップ。
/// 「対決する」なら true、「対決しない」なら false を返す。
class ChallengeIncomingDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String challengerName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('対決の申込'),
        content: Text('$challengerName から対決が申し込まれています。対決しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('対決しない'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('対決する'),
          ),
        ],
      ),
    );
  }
}
