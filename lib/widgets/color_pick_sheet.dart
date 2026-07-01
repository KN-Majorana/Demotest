import 'package:flutter/material.dart';

import '../color_extraction.dart';

/// 色を選ぶ BottomSheet（グリッド表示）。
///
/// - 新規作成: [allowedColorIds] を null にして全 24 色を表示。
/// - 既存追加: [allowedColorIds] に「自分が所有する色」だけを渡し、
///   [colorCounts] でその色の多角形個数を表示する。
class ColorPickSheet {
  /// 選択された colorPalette24 のインデックスを返す。キャンセル時は null。
  static Future<int?> show(
    BuildContext context, {
    String title = '多角形の色を選ぶ',
    String? subtitle,
    List<int>? allowedColorIds,
    Map<int, int>? colorCounts,
  }) {
    final ids = allowedColorIds ??
        List<int>.generate(colorPalette24.length, (i) => i);

    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ids.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemBuilder: (ctx, i) {
                    final id = ids[i];
                    return _ColorChoice(
                      colorId: id,
                      count: colorCounts?[id],
                      onTap: () => Navigator.pop(ctx, id),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColorChoice extends StatelessWidget {
  final int colorId;
  final int? count;
  final VoidCallback onTap;

  const _ColorChoice({
    required this.colorId,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final c = colorPalette24[colorId];
    final name = colorId < colorNames24.length ? colorNames24[colorId] : '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color.fromRGBO(c.r, c.g, c.b, 1.0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count != null ? '$name（$count）' : name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
