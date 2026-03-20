import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// ═══════════════════════════════════════════════════════
///   Zen Chat Bubble — Minimalist & Uniform
///   Typography: DM Sans   Accent: Zen Orange (#FF4500)
/// ═══════════════════════════════════════════════════════

class ZenChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isTyping;
  final VoidCallback? onDelete;

  const ZenChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isTyping = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFFF4500);
    const surfaceColor = Color(0xFF1C1C1E);
    const textColor = Colors.white;

    return Padding(
      padding: EdgeInsets.fromLTRB(isUser ? 60 : 16, 8, isUser ? 16 : 60, 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor, boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 1)]),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                isUser ? 'ME' : 'ZEN AI',
                style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: isUser ? Colors.white38 : accentColor, letterSpacing: 1),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('HH:mm').format(timestamp),
                style: GoogleFonts.dmSans(fontSize: 9, color: Colors.white10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          GestureDetector(
            onLongPress: () {
              HapticFeedback.heavyImpact();
              showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1C1C1E),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (c) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.copy_rounded, color: Colors.white70),
                        title: Text('COPY TEXT', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: content));
                          Navigator.pop(c);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied', style: GoogleFonts.dmSans()), backgroundColor: surfaceColor, behavior: SnackBarBehavior.floating));
                        },
                      ),
                      if (onDelete != null)
                      ListTile(
                        leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        title: Text('DELETE MESSAGE', style: GoogleFonts.spaceGrotesk(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        onTap: () {
                          Navigator.pop(c);
                          onDelete!();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? accentColor.withValues(alpha: 0.08) : surfaceColor.withValues(alpha: 0.6),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(isUser ? 22 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 22),
                ),
                border: Border.all(color: isUser ? accentColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
              ),
              child: isTyping 
                ? _buildTypingIndicator(accentColor)
                : MarkdownBody(
                    data: content,
                    shrinkWrap: true,
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.dmSans(fontSize: 15, color: textColor, height: 1.5),
                      h1: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                      h2: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                      h3: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: accentColor),
                      code: GoogleFonts.firaCode(fontSize: 12, color: accentColor, backgroundColor: Colors.white.withValues(alpha: 0.05)),
                      codeblockDecoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                      blockquoteDecoration: const BoxDecoration(border: Border(left: BorderSide(color: accentColor, width: 4))),
                      listBullet: GoogleFonts.dmSans(fontSize: 15, color: accentColor),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(Color color) {
    return SizedBox(
      width: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (i) => _TypingDot(index: i, color: color)),
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int index; final Color color;
  const _TypingDot({required this.index, required this.color});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}
class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Opacity(opacity: 0.3 + (0.7 * Curves.easeInOut.transform((_ctrl.value + widget.index * 0.2) % 1.0)), child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color))),
    );
  }
}
