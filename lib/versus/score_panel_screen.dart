import 'package:flutter/material.dart';

import '../color_extraction.dart';
import '../models/battle.dart';
import '../models/polygon.dart';
import '../services/area_ranking_service.dart';

String formatArea(double m2) {
  if (m2 >= 1000000) return '${(m2 / 1000000).toStringAsFixed(2)} km²';
  return '${m2.round()} m²';
}

/// 1v1 のスコアパネル（旧 area_ranking_screen の置き換え）。
class ScorePanelScreen extends StatelessWidget {
  final Battle battle;
  final List<WalkPolygon> polygons;
  final String myUid;

  const ScorePanelScreen({
    super.key,
    required this.battle,
    required this.polygons,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('スコア'),
        actions: [
          IconButton(
            tooltip: '閉じる',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: BattleScoreView(
          battle: battle,
          polygons: polygons,
          myUid: myUid,
        ),
      ),
    );
  }
}

/// スコア表示の共通ウィジェット（リザルト画面でも再利用）。
class BattleScoreView extends StatelessWidget {
  final Battle battle;
  final List<WalkPolygon> polygons;
  final String myUid;

  const BattleScoreView({
    super.key,
    required this.battle,
    required this.polygons,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final scores = computeBattleScores(polygons);
    final me = battle.myNameFor(myUid);
    final opp = battle.opponentNameFor(myUid);
    final myColor = battle.myColorId(myUid);
    final oppColor = battle.opponentColorIdFor(myUid);
    final oppUid = battle.opponentUidFor(myUid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          title: '$me（あなた）',
          colorId: myColor,
          score: scores[myUid],
          highlight: true,
        ),
        const SizedBox(height: 12),
        _card(
          title: opp,
          colorId: oppColor,
          score: scores[oppUid],
          highlight: false,
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    required int? colorId,
    required BattleScore? score,
    required bool highlight,
  }) {
    final c = (colorId != null && colorId < colorPalette24.length)
        ? colorPalette24[colorId]
        : const ColorRGB(128, 128, 128);
    final name = (colorId != null && colorId < colorNames24.length)
        ? colorNames24[colorId]
        : '-';
    final area = score?.areaMeters ?? 0;
    final count = score?.polygonCount ?? 0;
    final steals = score?.stealCount ?? 0;

    return Card(
      elevation: highlight ? 4 : 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(c.r, c.g, c.b, 1.0),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(name, style: const TextStyle(color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 12),
            _row('確保面積', formatArea(area)),
            _row('多角形の数', '$count'),
            _row('削り取った回数', '$steals'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
