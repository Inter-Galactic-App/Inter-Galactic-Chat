import 'package:flutter/material.dart';
import 'package:intergalactic/ui/mobile_preview/mobile_ui_preview_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MobileUiPreviewApp());
}

class MobileUiPreviewApp extends StatelessWidget {
  const MobileUiPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MobileUiPreviewPage(),
    );
  }
}
