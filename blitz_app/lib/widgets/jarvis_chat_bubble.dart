import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme.dart';

/// Chat bubble for Zen AI conversations — overflow-safe
class JarvisChatBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isTyping;
  final bool isMinimalist;

  const JarvisChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isTyping = false,
    this.isMinimalist = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 56 : 12,
        right: isUser ? 12 : 56,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ── Role label ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isUser) ...[
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFE8EAFF), Color(0xFF6E8CFF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6E8CFF).withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  isUser ? 'YOU' : 'ZEN',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: isMinimalist 
                        ? Colors.white.withValues(alpha: 0.5)
                        : (isUser ? BlitzTheme.accent : const Color(0xFF6E8CFF)),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    color: isMinimalist 
                        ? Colors.white.withValues(alpha: 0.2)
                        : BlitzTheme.textMuted.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // ── Message bubble ──────────────────────────────
          // Use ConstrainedBox instead of width:double.infinity to prevent overflow
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied',
                        style: GoogleFonts.spaceMono(fontSize: 12)),
                    backgroundColor: BlitzTheme.surface,
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isUser ? 20 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 20),
                  ),
                  color: isMinimalist
                      ? (isUser ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.02))
                      : (isUser ? BlitzTheme.accent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04)),
                  border: Border.all(
                    color: isMinimalist
                        ? Colors.white.withValues(alpha: 0.12)
                        : (isUser ? BlitzTheme.accent.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08)),
                  ),
                  boxShadow: [
                    if (!isUser)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: isTyping
                    ? _buildTypingIndicator()
                    : isUser
                        ? Text(
                            content,
                            style: GoogleFonts.syne(
                              fontSize: 14,
                              color: BlitzTheme.textPrimary,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : MarkdownBody(
                            data: content,
                            shrinkWrap: true,
                            fitContent: true,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: GoogleFonts.syne(
                                fontSize: 13.5,
                                color: BlitzTheme.textPrimary.withValues(alpha: 0.95),
                                height: 1.6,
                              ),
                              h1: GoogleFonts.syne(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: BlitzTheme.textPrimary,
                                height: 1.4,
                              ),
                              h2: GoogleFonts.syne(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: BlitzTheme.textPrimary,
                                height: 1.4,
                              ),
                              h3: GoogleFonts.syne(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: BlitzTheme.accent,
                                height: 1.4,
                              ),
                              code: GoogleFonts.spaceMono(
                                fontSize: 11,
                                color: BlitzTheme.cyan,
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: const Color(0xFF0A0F1E), // Deep dark for code
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              codeblockPadding: const EdgeInsets.all(16),
                              blockquoteDecoration: BoxDecoration(
                                color: BlitzTheme.accent.withValues(alpha: 0.05),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                                border: const Border(
                                  left: BorderSide(color: BlitzTheme.accent, width: 3),
                                ),
                              ),
                              blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                              listBullet: GoogleFonts.syne(
                                fontSize: 14,
                                color: BlitzTheme.accent,
                                fontWeight: FontWeight.bold,
                              ),
                              strong: GoogleFonts.syne(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              em: GoogleFonts.syne(
                                fontStyle: FontStyle.italic,
                                color: BlitzTheme.textMuted,
                              ),
                              horizontalRuleDecoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                                ),
                              ),
                              pPadding: const EdgeInsets.only(bottom: 8),
                            ),
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 600 + i * 200),
          builder: (context, value, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BlitzTheme.accent.withValues(alpha: 0.3 + value * 0.4),
              ),
            );
          },
        );
      }),
    );
  }
}
