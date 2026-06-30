import 'package:flutter/material.dart';

import '../color_extraction.dart';
import '../models/polygon.dart';

/// ステップB-②：自分の既存（確定済み）多角形から1つ選ぶ BottomSheet。
/// versus モードでもフレンドの多角形は対象外（自分のもののみ）。
class ExistingPolygonPickSheet {
  static Future<WalkPolygon?> show(
    BuildContext context, {
    required List<WalkPolygon> polygons,
  }) {
    final confirmed = polygons.where((p) => p.confirmed && p.isActive).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));

    return showModalBottomSheet<WalkPolygon>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '追加する多角形を選ぶ',
                          style: TextStyle(
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
                  const SizedBox(height: 4),
                  const Text(
                    '選んだ多角形の色と写真の色が一致した場合のみ追加されます。',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: confirmed.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final poly = confirmed[i];
                        final c = poly.colorId < colorPalette24.length
                            ? colorPalette24[poly.colorId]
                            : const ColorRGB(128, 128, 128);
                        final name = poly.colorId < colorNames24.length
                            ? colorNames24[poly.colorId]
                            : '';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color.fromRGBO(c.r, c.g, c.b, 1.0),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                          title: Text('$name の多角形'),
                          subtitle: Text(
                            '作成: ${_formatTime(poly.createdAt)} ・ '
                            '頂点 ${poly.vertexCount}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(ctx, poly),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
