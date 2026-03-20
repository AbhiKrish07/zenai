import 'package:flutter/material.dart';
import '../core/theme_manager.dart';
import '../services/notification_service.dart';
import 'command_center_screen.dart';

class TabChangeNotification extends Notification {
  final int index;
  const TabChangeNotification(this.index);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNotificationService().startListening(askPermission: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Morphing Wallpaper Layer
          ListenableBuilder(
            listenable: ThemeManager(),
            builder: (context, child) {
              return AnimatedContainer(
                duration: const Duration(seconds: 2),
                decoration: BoxDecoration(gradient: ThemeManager().backgroundGradient),
              );
            },
          ),
          
          // Main Content
          const CommandCenterScreen(),
        ],
      ),
    );
  }
}
