import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// カメラ撮影・保存サービス
class PhotoService {
  PhotoService._();

  static final _picker = ImagePicker();

  /// カメラで撮影し、アプリの写真ディレクトリに保存する。
  /// キャンセルされた場合は null を返す。
  static Future<String?> takeAndSavePhoto() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (xFile == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(dir.path, 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }

    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = p.join(photosDir.path, fileName);
    await File(xFile.path).copy(destPath);
    return destPath;
  }

  /// 撮影したがピンを立てないと判断した写真ファイルを破棄する。
  /// （機能3：色が一致しなかった場合などに使用）
  static Future<void> deletePhotoFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 破棄失敗は無視（一時ファイルのため致命的でない）
    }
  }
}
