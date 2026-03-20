import 'package:flutter/material.dart';

class VoiceModeScreen extends StatelessWidget {
  const VoiceModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text('Neural Voice not supported on Web version.', 
          style: TextStyle(color: Colors.white24, fontSize: 12)),
      ),
    );
  }
}
