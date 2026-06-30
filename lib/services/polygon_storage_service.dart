import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/polygon.dart';

/// 自分の多角形（準備中グループを含む）をローカル JSON に永続化するサービス。
///
/// 対戦に参加していない（normal 専用）ユーザでも、撮影フローで作った
/// グループをローカルに保持できるようにするための保存先。
class PolygonStorageService {
  PolygonStorageService._();

  static const _fileName = 'walk_polygons.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> saveAll(List<WalkPolygon> polygons) async {
    final file = await _file();
    final json = jsonEncode(polygons.map((p) => p.toMap()).toList());
    await file.writeAsString(json);
  }

  static Future<List<WalkPolygon>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.isEmpty) return [];
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((j) => WalkPolygon.fromMap(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
