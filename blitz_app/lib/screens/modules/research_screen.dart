import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import '../../theme.dart';
import '../../core/zen_brain.dart';

class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});
  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  final _ctrl = TextEditingController();
  final _brain = ZenBrain();
  bool _isLoading = false;
  String _statusMessage = '';
  String? _markdownReport;

  Future<void> _runResearch(String topic) async {
    if (topic.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    
    setState(() {
      _isLoading = true;
      _markdownReport = null;
      _statusMessage = 'Initializing Web Agents...\nDeploying Search Queries...';
    });

    try {
      // 1. Native Tavily Search
      const tavilyKey = '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';
      
      final searchResp = await http.post(
        Uri.parse('https://api.tavily.com/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "api_key": tavilyKey,
          "query": topic,
          "search_depth": "advanced",
          "max_results": 5,
          "include_answer": true
        }),
      ).timeout(const Duration(seconds: 15));

      if (searchResp.statusCode != 200) {
        throw Exception('Search failed');
      }

      setState(() {
        _statusMessage = 'Synthesizing knowledge vectors via Groq Engine...';
      });

      final data = jsonDecode(searchResp.body);
      final rawAnswer = data['answer'] ?? '';
      final results = data['results'] as List? ?? [];
      
      String contextData = rawAnswer + '\n\n';
      for (var r in results) {
        contextData += '- ${r['title']} (${r['url']})\n  ${r['content']}\n\n';
      }

      // 2. Pass to Groq for Markdown Synthesis
      final prompt = '''
You are an elite Autonomous Research Agent.
Write a comprehensive, highly-structured Markdown briefing Document based ONLY on the provided research context.
Use bolding, multiple headings, and bullet points. Give it a professional layout.

TOPIC: $topic

CONTEXT DATA:
$contextData
''';

      final report = await _brain.chat(prompt, sessionId: 'research_temp');

      setState(() {
        _markdownReport = report;
        _isLoading = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Research aborted due to anomaly: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: BlitzTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _ctrl,
                  style: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'What should we deep-dive into?',
                    hintStyle: GoogleFonts.syne(color: BlitzTheme.textMuted),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: BlitzTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: BlitzTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: BlitzTheme.cyan)),
                    suffixIcon: _isLoading
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: BlitzTheme.cyan)))
                      : IconButton(icon: const Icon(Icons.rocket_launch, color: BlitzTheme.cyan), onPressed: () => _runResearch(_ctrl.text)),
                  ),
                  onSubmitted: _runResearch,
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: BlitzTheme.cyan),
                            const SizedBox(height: 20),
                            Text(_statusMessage, textAlign: TextAlign.center, style: GoogleFonts.spaceMono(fontSize: 12, color: BlitzTheme.textMuted)),
                          ],
                        ),
                      )
                    : _markdownReport == null
                        ? Center(child: Text('Awaiting directive.', style: GoogleFonts.spaceMono(fontSize: 12, color: BlitzTheme.textMuted)))
                        : Markdown(
                            data: _markdownReport!,
                            styleSheet: MarkdownStyleSheet(
                              h1: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                              h2: GoogleFonts.syne(color: BlitzTheme.cyan, fontSize: 20, fontWeight: FontWeight.bold),
                              h3: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                              p: GoogleFonts.syne(color: BlitzTheme.textMuted, fontSize: 14),
                              listBullet: const TextStyle(color: BlitzTheme.accent),
                            ),
                          ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: BlitzTheme.surface,
        border: Border(bottom: BorderSide(color: BlitzTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: BlitzTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.hub_rounded, size: 24, color: BlitzTheme.cyan),
          const SizedBox(width: 8),
          Text(
            'DEEP RESEARCH',
            style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary, letterSpacing: 1.5),
          ),
        ],
      ),
    );
  }
}
