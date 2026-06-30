import 'package:flutter/material.dart';

import 'color_extraction.dart';

/// 機能3-[A]：新規多角形の色を選ばせる BottomSheet。
/// 選択された colorPalette24 のインデックスを返す。キャンセル時は null。
class ColorPickerSheet {
  static Future<int?> show(BuildContext context) {
    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '作る多角形の色を選択',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'この色と一致する写真だけがピンになります。',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (int i = 0; i < colorPalette24.length; i++)
                      _ColorChoice(
                        colorId: i,
                        onTap: () => Navigator.pop(ctx, i),
                      ),
                  ],
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
  final VoidCallback onTap;

  const _ColorChoice({required this.colorId, required this.onTap});

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
          SizedBox(
            width: 56,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
