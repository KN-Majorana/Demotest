import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 捕捉されない非同期エラーでアプリ全体が落ちるのを防ぐ安全網。
  // （対戦モードの Firestore リスナー等で想定外のエラーが出ても、
  //   ログに出してアプリは継続させる。）
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('未捕捉エラー: $error\n$stack');
    return true; // handled
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase 設定が未配置でも通常モード等は動作するよう、起動失敗は握りつぶす。
    debugPrint('Firebase 初期化に失敗しました（対戦モードは利用できません）: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
