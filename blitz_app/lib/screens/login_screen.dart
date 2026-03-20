import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../core/database.dart';
import '../core/session.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'welcome_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _db = ZenDatabase();
  late AnimationController _animController;
  
  bool _isLogin = true;
  bool _loading = false;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final username = _usernameController.text.trim();
    final passphrase = _passphraseController.text.trim();

    if (username.isEmpty || passphrase.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        // Authenticate
        final user = await _db.authenticateUser(username, passphrase);
        if (user != null) {
          debugPrint('User logged in: ${user['username']}');
          await ZenSession().login(user['id'], name: user['username']);
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          }
        } else {
          setState(() => _error = 'Invalid username or passphrase');
        }
      } else {
        // Sign Up
        final existing = await _db.getUserByUsername(username);
        if (existing != null) {
          setState(() => _error = 'Username already exists');
        } else {
          final id = const Uuid().v4();
          await _db.insertUser({
            'id': id,
            'username': username,
            'passphrase_hash': passphrase,
            'created_at': DateTime.now().toIso8601String(),
          });
          debugPrint('New user signed up: $username');
          await ZenSession().login(id, name: username);
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          }
        }
      }
    } catch (e) {
      setState(() => _error = 'System error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _buildBackdrop(),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 60),
                    _buildFields(),
                    if (_error != null) _buildError(),
                    const SizedBox(height: 48),
                    _buildActionButton(),
                    const SizedBox(height: 32),
                    _buildToggleLink(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdrop() {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: WelcomeBackgroundPainter(_animController.value),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BlitzTheme.accentGradient,
            boxShadow: accentGlow(color: BlitzTheme.accent, blur: 30),
          ),
          child: const Icon(Icons.shield_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 24),
        Text(
          _isLogin ? 'AUTHENTICATE' : 'INITIALIZE',
          style: GoogleFonts.syne(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isLogin ? 'IDENTITY VERIFICATION REQUIRED' : 'ESTABLISH NEW SECURE PROFILE',
          style: GoogleFonts.spaceMono(
            fontSize: 9, color: BlitzTheme.textMuted,
            letterSpacing: 2.5, fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFields() {
    return Column(
      children: [
        _buildTextField(
          controller: _usernameController,
          label: 'USER_ID',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 24),
        _buildTextField(
          controller: _passphraseController,
          label: 'PASSWORD',
          icon: Icons.lock_outline_rounded,
          isObscure: true,
        ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        _error!,
        style: GoogleFonts.spaceMono(color: BlitzTheme.red, fontSize: 11),
      ),
    );
  }

  Widget _buildActionButton() {
    return GestureDetector(
      onTap: _loading ? null : _handleSubmit,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          color: _loading ? BlitzTheme.surface : BlitzTheme.textPrimary,
          boxShadow: _loading ? [] : [
            BoxShadow(color: Colors.white.withValues(alpha: 0.15), blurRadius: 40),
          ],
        ),
        child: Center(
          child: _loading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
            : Text(
                _isLogin ? 'ENTER ZEN' : 'GENERATE ACCESS',
                style: GoogleFonts.spaceMono(
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  letterSpacing: 3,
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildToggleLink() {
    return TextButton(
      onPressed: () => setState(() {
        _isLogin = !_isLogin;
        _error = null;
      }),
      child: Text(
        _isLogin ? 'REQUEST NEW CREDENTIALS' : 'RECALL EXISTING IDENTITY',
        style: GoogleFonts.spaceMono(
          fontSize: 9,
          color: BlitzTheme.accent,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: BlitzTheme.textMuted,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: TextField(
            controller: controller,
            obscureText: isObscure,
            style: GoogleFonts.spaceMono(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: BlitzTheme.accent.withValues(alpha: 0.4), size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            ),
          ),
        ),
      ],
    );
  }
}
