import 'package:flutter/material.dart';

import 'color_extraction.dart';
import 'models/polygon.dart';
import 'services/area_ranking_service.dart';

/// 機能4：対戦モードの「面積ランキング」全画面。
class AreaRankingScreen extends StatelessWidget {
  /// 自分＋フレンドの確定多角形
  final List<WalkPolygon> polygons;
  final String? myUid;

  /// 空状態の文言出し分け用
  final int friendCount;

  const AreaRankingScreen({
    super.key,
    required this.polygons,
    required this.myUid,
    required this.friendCount,
  });

  static String _formatArea(double m2) {
    if (m2 >= 1000000) {
      return '${(m2 / 1000000).toStringAsFixed(2)} km²';
    }
    return '${m2.round()} m²';
  }

  @override
  Widget build(BuildContext context) {
    final ranking = AreaRankingService.rank(polygons, topN: 20);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('面積ランキング'),
        actions: [
          IconButton(
            tooltip: '閉じる',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: ranking.isEmpty
          ? _buildEmpty()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: ranking.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _buildRow(i + 1, ranking[i]),
            ),
    );
  }

  Widget _buildRow(int rank, RankingEntry e) {
    final c = e.colorId >= 0 && e.colorId < colorPalette24.length
        ? colorPalette24[e.colorId]
        : const ColorRGB(128, 128, 128);
    final colorName =
        e.colorId < colorNames24.length ? colorNames24[e.colorId] : '';
    final isMine = myUid != null && e.ownerUid == myUid;

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: rank <= 3 ? 22 : 16,
            fontWeight: FontWeight.bold,
            color: switch (rank) {
              1 => const Color(0xFFFFB300),
              2 => const Color(0xFF9E9E9E),
              3 => const Color(0xFF8D6E63),
              _ => Colors.black54,
            },
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMine ? '${e.ownerName}（あなた）' : e.ownerName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isMine ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Color.fromRGBO(c.r, c.g, c.b, 1.0),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 6),
          Text(colorName, style: const TextStyle(fontSize: 13)),
        ],
      ),
      trailing: Text(
        _formatArea(e.areaMeters),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEmpty() {
    final message = friendCount == 0
        ? 'まだフレンドがいません。\nフレンドを追加して、お互いの多角形で\n面積を競いましょう。'
        : 'まだ確定した多角形がありません。\n同じ色の写真を3枚撮ると多角形が完成します。';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              friendCount == 0
                  ? Icons.group_add_outlined
                  : Icons.layers_clear_outlined,
              size: 64,
              color: Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
