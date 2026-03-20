import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../core/zen_brain.dart';
import '../core/theme_manager.dart';
import '../core/session.dart';
import 'login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/widget_item.dart';
import '../core/database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════
///   Zen OS — Configuration Screen 
///   Clean aesthetic, no underlines, fixed borders
/// ═══════════════════════════════════════════════════════

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _brain = ZenBrain();
  final _groqKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  final _elevenLabsKeyController = TextEditingController();
  final _zillizUserCtrl = TextEditingController();
  final _zillizPassCtrl = TextEditingController();
  final _zillizEndCtrl = TextEditingController();
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final groq = await _storage.read(key: 'groq_api_key');
    final gemini = await _storage.read(key: 'gemini_api_key');
    final eleven = await _storage.read(key: 'eleven_labs_api_key');
    final zUser = await _storage.read(key: 'zilliz_user');
    final zPass = await _storage.read(key: 'zilliz_password');
    final zEnd = await _storage.read(key: 'zilliz_endpoint');

    if (groq != null) setState(() => _groqKeyController.text = groq);
    if (gemini != null) setState(() => _geminiKeyController.text = gemini);
    if (eleven != null) setState(() => _elevenLabsKeyController.text = eleven);
    
    if (zUser != null) _zillizUserCtrl.text = zUser;
    if (zPass != null) _zillizPassCtrl.text = zPass;
    if (zEnd != null) _zillizEndCtrl.text = zEnd;
  }

  Future<void> _saveApiKey(String type) async {
    if (type == 'groq') {
      final key = _groqKeyController.text.trim();
      await _brain.setApiKey(key);
      _showSnack('Groq API Key Saved');
    } else if (type == 'gemini') {
      final key = _geminiKeyController.text.trim();
      await _brain.setGeminiApiKey(key);
      _showSnack('Gemini API Key Saved');
    } else if (type == 'eleven_labs') {
      final key = _elevenLabsKeyController.text.trim();
      await _brain.setElevenLabsKey(key);
      _showSnack('ElevenLabs API Key Saved');
    }
    setState(() {});
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.spaceMono(fontSize: 12)),
          backgroundColor: ZenTheme.accent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _pushWidgetToHome(String type) async {
    final db = ZenDatabase();
    final activeId = ZenSession().activeUserId;
    final widgets = await db.getHomeWidgets(userId: activeId);
    
    final id = const Uuid().v4();
    Size size;
    switch(type) {
      case 'ai_orb': size = const Size(180, 180); break;
      case 'photo': size = const Size(200, 240); break;
      case 'note': size = const Size(180, 130); break;
      case 'battery': size = const Size(140, 140); break;
      case 'weather': size = const Size(160, 160); break;
      case 'connectivity': size = const Size(140, 140); break;
      case 'stats_ring': size = const Size(220, 220); break; 
      case 'system_info': size = const Size(180, 160); break;
      case 'time_elapsed': size = const Size(160, 160); break;
      default: size = const Size(180, 180);
    }
    
    final widget = WidgetItem(
      id: id,
      userId: activeId,
      type: type,
      position: Offset(50.0 + (widgets.length * 15.0), 200.0 + (widgets.length * 15.0)),
      size: size,
      data: type == 'note' ? {'text': 'Double-tap to write...'} : {},
    );
    await db.saveHomeWidget(widget);
    
    if (mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Widget "$type" injected to Command Center.'),
        backgroundColor: Colors.cyan,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.tune_rounded, size: 24, color: ZenTheme.accent),
                const SizedBox(width: 14),
                Text('SETTINGS', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
              ]),
              const SizedBox(height: 32),

              const SizedBox(height: 24),

              _buildHeader('CORE SYSTEM'),
              _settingsCard(
                icon: Icons.settings_suggest_rounded,
                color: Colors.blueGrey,
                title: 'System Settings',
                subtitle: 'Direct hardware & permission access',
                onTap: () {
                  const MethodChannel('com.zen/focus').invokeMethod('openApp', {'package': 'com.android.settings'});
                },
              ),
              const SizedBox(height: 12),

              _buildHeader('AI BRAIN (USER KEYS REQUIRED)'),
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.security_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text('For privacy, Zen requires your own API keys. No keys are hardcoded in the binary.', style: GoogleFonts.dmSans(fontSize: 11, color: Colors.redAccent.withValues(alpha: 0.8)))),
                ]),
              ),
              _buildApiKeyInput('GROQ API', _groqKeyController, 'gsk_...', 'https://console.groq.com/keys', () => _saveApiKey('groq')),
              const SizedBox(height: 12),
              _buildApiKeyInput('GEMINI API', _geminiKeyController, 'AIza...', 'https://aistudio.google.com/app/apikey', () => _saveApiKey('gemini')),
              const SizedBox(height: 12),
              _buildApiKeyInput('ELEVENLABS API', _elevenLabsKeyController, 'sk_...', 'https://elevenlabs.io/app/api-keys', () => _saveApiKey('eleven_labs')),
              
              const SizedBox(height: 12),
              _settingsCard(
                icon: Icons.psychology_rounded,
                color: Colors.blueAccent,
                title: 'Intelligence Model',
                subtitle: _brain.currentModelName.toUpperCase(),
                onTap: _showModelPicker,
              ),

              const SizedBox(height: 12),
              _settingsCard(
                icon: Icons.storage_rounded,
                color: Colors.tealAccent,
                title: 'Vector Memory (Zilliz)',
                subtitle: _brain.zillizUser.isEmpty ? 'NOT CONFIGURED' : '${_brain.zillizUser.substring(0, 5)}...',
                onTap: _showZillizPicker,
              ),

              const SizedBox(height: 24),
              _buildHeader('SYSTEM WIDGETS'),
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 12, runSpacing: 12,
                  children: [
                    _buildWidgetBadge('Battery', 'battery'),
                    _buildWidgetBadge('Weather', 'weather'),
                    _buildWidgetBadge('Note', 'note'),
                    _buildWidgetBadge('Stats', 'stats_ring'),
                    _buildWidgetBadge('System', 'system_info'),
                    _buildWidgetBadge('Life', 'time_elapsed'),
                  ],
                ),
              ),

              const SizedBox(height: 24),
               _buildHeader('APPEARANCE'),
              _settingsCard(
                icon: Icons.color_lens_rounded,
                color: ZenTheme.accent,
                title: 'Accent Scheme',
                subtitle: 'Hex: #${ThemeManager().accent.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                onTap: _showThemePicker,
              ),
              _settingsCard(
                icon: Icons.wallpaper_rounded,
                color: Colors.purpleAccent,
                title: 'Home Wallpaper',
                subtitle: 'Pick high-fidelity imagery',
                onTap: _showWallpaperPicker,
              ),

              const SizedBox(height: 48),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await ZenSession().logout();
                    if (!context.mounted) return;
                    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
                  },
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                  label: Text('Logout Zen Session', style: GoogleFonts.dmSans(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(title, style: GoogleFonts.spaceMono(fontSize: 12, color: const Color(0xFF444444), letterSpacing: 2, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildApiKeyInput(String label, TextEditingController ctrl, String hint, String url, VoidCallback onSave) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.spaceMono(fontSize: 10, color: const Color(0xFF888888), fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(url)),
                child: Text('OBTAIN KEY', style: GoogleFonts.spaceMono(fontSize: 9, color: ZenTheme.accent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          TextField(
            controller: ctrl,
            obscureText: true,
            style: GoogleFonts.spaceMono(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.spaceMono(color: const Color(0xFF333333)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              suffixIcon: IconButton(icon: const Icon(Icons.save_rounded, color: ZenTheme.accent, size: 20), onPressed: onSave),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({required IconData icon, required Color color, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: color.withValues(alpha: 0.1)), child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(subtitle, style: GoogleFonts.spaceMono(fontSize: 10, color: const Color(0xFF888888))),
          ])),
          const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF444444)),
        ]),
      ),
    );
  }

  Widget _buildWidgetBadge(String label, String type) {
    return GestureDetector(
      onTap: () => _pushWidgetToHome(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Text(label, style: GoogleFonts.spaceMono(fontSize: 11, color: Colors.white70)),
      ),
    );
  }

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Text('SELECT INTELLIGENCE', style: GoogleFonts.spaceMono(color: const Color(0xFF444444), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
             const SizedBox(height: 20),
             ..._brain.availableModels.map((m) {
                final isSelected = _brain.currentModel == m['id'];
                return ListTile(
                  leading: Icon(Icons.psychology_rounded, color: isSelected ? ZenTheme.accent : const Color(0xFF444444)),
                  title: Text(m['name']!, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(m['id']!, style: GoogleFonts.spaceMono(fontSize: 9, color: const Color(0xFF888888))),
                  onTap: () async {
                    await _brain.setModel(m['id']!);
                    setState(() {});
                    if (c.mounted) Navigator.pop(c);
                  },
                );
             }),
             const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CHOOSE SCHEME', style: GoogleFonts.spaceMono(color: const Color(0xFF444444), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 20),
            ...ZenTheme.variants.map((v) => ListTile(
              leading: Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, color: v['color'] as Color)),
              title: Text(v['name'] as String, style: GoogleFonts.dmSans(color: Colors.white)),
              onTap: () async {
                await ThemeManager().setAccent(v['color'] as Color);
                if (!c.mounted) return;
                Navigator.pop(c);
                setState((){});
              },
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showWallpaperPicker() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zen_wallpaper', img.path);
      _showSnack('Wallpaper established in neuro-link.');
    }
  }

  void _showZillizPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom, left: 24, right: 24, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VECTOR MEMORY CONFIG', style: GoogleFonts.spaceMono(color: const Color(0xFF444444), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 20),
            _buildDialogInput('User / Public Key', _zillizUserCtrl),
            const SizedBox(height: 12),
            _buildDialogInput('Password / Secret Key', _zillizPassCtrl, obscure: true),
            const SizedBox(height: 12),
            _buildDialogInput('Cluster Endpoint', _zillizEndCtrl),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ZenTheme.accent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () async {
                  await _brain.setZillizConfig(_zillizUserCtrl.text.trim(), _zillizPassCtrl.text.trim(), _zillizEndCtrl.text.trim());
                  if (c.mounted) Navigator.pop(c);
                  _showSnack('Vector Storage sync complete.');
                  setState(() {});
                },
                child: Text('VERIFY & SYNC', style: GoogleFonts.dmSans(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogInput(String label, TextEditingController ctrl, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.spaceMono(fontSize: 10, color: const Color(0xFF888888))),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          style: GoogleFonts.spaceMono(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}
