import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/zen_brain.dart';

class CanvasModuleScreen extends StatefulWidget {
  const CanvasModuleScreen({super.key});
  @override
  State<CanvasModuleScreen> createState() => _CanvasModuleScreenState();
}

enum CanvasMode { write, draw, hybrid }

class Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  Stroke({required this.points, required this.color, required this.width});
}

class CanvasNote {
  String id;
  String title;
  String content;
  DateTime date;
  CanvasNote(this.id, this.title, this.content, this.date);
}

class _CanvasModuleScreenState extends State<CanvasModuleScreen> {
  // Theme Variables mimicking the HTML Canvas v3 CSS (Dark Mode)
  static const Color _bg = Color(0xFF0D0D0B);
  static const Color _bg2 = Color(0xFF111110);
  static const Color _paper = Color(0xFF13130F);
  static const Color _border = Color(0x0FFFF8E6); // 6% white
  static const Color _border2 = Color(0x1CFFF8E6); // 11% white
  static const Color _text = Color(0xFFF0EAD8);
  static const Color _text2 = Color(0xFFC8BFA8);
  static const Color _muted = Color(0x61F0EAD8); // 38%
  static const Color _accent = Color(0xFFE8A87C);
  static const Color _accentBg = Color(0x14E8A87C); // 8%
  static const Color _blueBg = Color(0x147AAFD4);

  // States
  CanvasMode _mode = CanvasMode.write;
  bool _showAiPanel = false;
  bool _showSidebar = false;

  // Note Data
  final List<CanvasNote> _notes = [
    CanvasNote(
        '1',
        'Project Brainstorm',
        'Start writing... Use Zen AI to enhance your notes.\\n\\n1. Outline the core engine features\\n2. Build the UI components\\n3. Refactor the backend AI context\\n',
        DateTime.now().subtract(const Duration(hours: 2))),
    CanvasNote(
        '2',
        'Meeting Notes: Q3 Sync',
        'Discussing the upcoming architecture changes.',
        DateTime.now().subtract(const Duration(days: 1))),
    CanvasNote('3', 'Random Thoughts', '',
        DateTime.now().subtract(const Duration(days: 3))),
  ];
  int _activeNoteIndex = 0;

  // Editor Controllers
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  final _aiInputController = TextEditingController();
  final ScrollController _aiScrollController = ScrollController();

  // Zen AI
  final _brain = ZenBrain();
  final List<Map<String, String>> _aiMessages = [];
  bool _isAiTyping = false;

  // Draw State
  final List<Stroke> _strokes = [];
  Color _penColor = _text;
  bool _isEraser = false;
  double _strokeWidth = 3.0;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: _notes[_activeFileIndex].title);
    _contentController =
        TextEditingController(text: _notes[_activeFileIndex].content);
    _aiMessages.add({
      'role': 'assistant',
      'content':
          'I am Zen. I can summarise, check grammar, expand, or format your notes!'
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _aiInputController.dispose();
    _aiScrollController.dispose();
    super.dispose();
  }

  int get _activeFileIndex => _activeNoteIndex;

  void _switchNote(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _notes[_activeFileIndex].title = _titleController.text;
      _notes[_activeFileIndex].content = _contentController.text;
      _activeNoteIndex = index;
      _titleController.text = _notes[_activeFileIndex].title;
      _contentController.text = _notes[_activeFileIndex].content;
      _strokes.clear(); // clear drawing for new note (demo)
    });
  }

  void _newNote() {
    HapticFeedback.mediumImpact();
    setState(() {
      _notes[_activeFileIndex].title = _titleController.text;
      _notes[_activeFileIndex].content = _contentController.text;
      _notes.insert(
          0,
          CanvasNote(DateTime.now().millisecondsSinceEpoch.toString(), '', '',
              DateTime.now()));
      _activeNoteIndex = 0;
      _titleController.text = _notes[0].title;
      _contentController.text = _notes[0].content;
      _strokes.clear();
    });
  }

  Future<void> _sendToZen(String prompt) async {
    setState(() {
      _aiMessages.add({'role': 'user', 'content': prompt});
      _isAiTyping = true;
    });
    _scrollToBottom();

    // Save current active state before sending context
    _notes[_activeFileIndex].content = _contentController.text;
    final context = _contentController.text;
    final fullPrompt = context.isEmpty
        ? prompt
        : "Context from my current note:\\n```\\n$context\\n```\\n\\nPrompt: $prompt";

    try {
      final response = await _brain.chat(fullPrompt);
      setState(() {
        _aiMessages.add({'role': 'assistant', 'content': response});
        _isAiTyping = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _aiMessages.add({
          'role': 'assistant',
          'content': 'Could not connect to Zen. Is the server running?'
        });
        _isAiTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_aiScrollController.hasClients) {
        _aiScrollController.animateTo(
          _aiScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _deleteNote(int index) {
    if (_notes.length <= 1) return; // keep at least one
    HapticFeedback.mediumImpact();
    setState(() {
      _notes.removeAt(index);
      if (_activeNoteIndex >= _notes.length) {
        _activeNoteIndex = _notes.length - 1;
      }
      _titleController.text = _notes[_activeNoteIndex].title;
      _contentController.text = _notes[_activeNoteIndex].content;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Stack(
                children: [
                  Row(
                    children: [
                      if (_showSidebar) _buildSidebar(),
                      Expanded(
                        child: _buildMainArea(),
                      ),
                      if (_showAiPanel)
                        isNarrow
                            ? Flexible(flex: 3, child: _buildZenPanel())
                            : _buildZenPanel(),
                    ],
                  ),
                  if (_mode == CanvasMode.draw || _mode == CanvasMode.hybrid)
                    Positioned(
                      left: _showSidebar ? 280 : 20, // shift past sidebar
                      top: 16,
                      child: _buildDrawingTools(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: _bg, // rgba(245, 244, 240, .94)
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
          // LEFT
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_back_rounded,
                          size: 12, color: _muted),
                      const SizedBox(width: 4),
                      Text('Hub',
                          style: GoogleFonts.spaceMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: _muted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _tbBtn('Notes', Icons.menu_rounded,
                  isGhost: true, isActive: _showSidebar, onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _showSidebar = !_showSidebar;
                  if (_showSidebar && MediaQuery.of(context).size.width < 600) {
                    _showAiPanel = false;
                  }
                });
              }),
              const SizedBox(width: 8),
              if (MediaQuery.of(context).size.width > 600)
                Text(
                  'The Canvas',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 17,
                    fontStyle: FontStyle.italic,
                    color: _text,
                    letterSpacing: -0.01,
                  ),
                ),
            ],
          ),

          // CENTER
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF161614), // bg3
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeBtn('Write', CanvasMode.write),
                _modeBtn('Draw', CanvasMode.draw),
                _modeBtn('Split', CanvasMode.hybrid),
              ],
            ),
          ),

          // RIGHT
          Row(
            children: [
              if (MediaQuery.of(context).size.width > 600)
                _tbBtn('Send to Zen', Icons.auto_awesome, isGhost: true,
                    onTap: () {
                  if (!_showAiPanel) setState(() => _showAiPanel = true);
                  _sendToZen("Summarise and analyze this note.");
                }),
              if (MediaQuery.of(context).size.width > 600)
                const SizedBox(width: 8),
              _tbBtn('Zen', Icons.electric_bolt_rounded,
                  isActive: _showAiPanel, onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _showAiPanel = !_showAiPanel;
                  if (_showAiPanel && MediaQuery.of(context).size.width < 600) {
                    _showSidebar = false;
                  }
                });
              }),
            ],
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }

  Widget _modeBtn(String label, CanvasMode mode) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _paper : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceMono(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: active ? _text : _muted,
          ),
        ),
      ),
    );
  }

  Widget _tbBtn(String label, IconData icon,
      {bool isActive = false,
      bool isGhost = false,
      required VoidCallback onTap}) {
    Color bg = Colors.transparent;
    Color border = Colors.transparent;
    Color color = _text2;

    if (isActive) {
      bg = _accent;
      border = const Color(0xFFC47A45); // accent2
      color = Colors.white;
    } else if (!isGhost) {
      bg = _paper;
      border = _border;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: color,
                    letterSpacing: 0.02)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: _paper,
        border: Border(right: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
              color: Color(0x0A000000), offset: Offset(2, 0), blurRadius: 8)
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              children: [
                InkWell(
                  onTap: _newNote,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 8),
                        Text('NEW NOTE',
                            style: GoogleFonts.spaceMono(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: _bg2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      const Icon(Icons.search_rounded, size: 14, color: _muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          style:
                              GoogleFonts.spaceMono(fontSize: 11, color: _text),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search...',
                            hintStyle: GoogleFonts.spaceMono(color: _muted),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            alignment: Alignment.centerLeft,
            child: Text('NOTES',
                style: GoogleFonts.spaceMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: _muted)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                final isActive = index == _activeNoteIndex;
                return Dismissible(
                  key: Key(note.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.red.withValues(alpha: 0.15),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    child: const Icon(Icons.delete_rounded, color: Colors.red, size: 14),
                  ),
                  confirmDismiss: (_) async => _notes.length > 1,
                  onDismissed: (_) => _deleteNote(index),
                  child: InkWell(
                    onTap: () => _switchNote(index),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: isActive ? _accentBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isActive
                                ? _accent.withValues(alpha: 0.18)
                                : Colors.transparent),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📄', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.title.isEmpty ? 'Untitled' : note.title,
                                  style: GoogleFonts.lora(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _text,
                                      height: 1.4),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${note.date.month}/${note.date.day} • ${note.content.length} chars',
                                  style: GoogleFonts.spaceMono(
                                      fontSize: 9, color: _muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea() {
    if (_mode == CanvasMode.write) return _buildWriteArea();
    if (_mode == CanvasMode.draw) return _buildDrawArea();
    return Row(
      children: [
        Expanded(child: _buildWriteArea()),
        Container(width: 1, color: _border),
        Expanded(child: _buildDrawArea()),
      ],
    );
  }

  Widget _buildWriteArea() {
    return LayoutBuilder(builder: (context, constraints) {
      final double hPad = constraints.maxWidth < 400 ? 16.0 : 52.0;
      return Container(
        color: _paper,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, 40, hPad, 120),
              children: [
              TextField(
                controller: _titleController,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 38,
                  fontStyle: FontStyle.italic,
                  color: _text,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: 'Untitled',
                  hintStyle: GoogleFonts.playfairDisplay(
                      fontStyle: FontStyle.italic,
                      color: _text.withValues(alpha: 0.2)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() =>
                    _notes[_activeFileIndex].title = _titleController.text),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Text(
                      'Today, ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                      style:
                          GoogleFonts.spaceMono(fontSize: 10, color: _muted)),
                  // Word count
                  Text(
                    '${_contentController.text.trim().isEmpty ? 0 : _contentController.text.trim().split(RegExp(r'\s+')).length} words',
                    style: GoogleFonts.spaceMono(fontSize: 10, color: _muted),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: _accentBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _accent.withValues(alpha: 0.2))),
                    child: Text('# draft',
                        style:
                            GoogleFonts.spaceMono(fontSize: 9, color: _accent)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _border2,
                            style: BorderStyle
                                .none)),
                    child: Text('+ add tag',
                        style:
                            GoogleFonts.spaceMono(fontSize: 9, color: _muted)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 2, color: const Color(0xFF161614)), // bg3
              const SizedBox(height: 20),
              TextField(
                controller: _contentController,
                maxLines: null,
                style: GoogleFonts.lora(
                  fontSize: 16,
                  height: 1.85,
                  color: _text2,
                ),
                decoration: InputDecoration(
                  hintText: 'Start writing... Use Zen AI for magic.',
                  hintStyle: GoogleFonts.lora(
                      color: _text.withValues(alpha: 0.2),
                      fontStyle: FontStyle.italic),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() =>
                    _notes[_activeFileIndex].content = _contentController.text),
              ),
            ],
          ),
        ),
      ),
    );
    });
  }

  Widget _buildDrawArea() {
    return RepaintBoundary(
      child: CanvasDrawingLayer(
        strokes: _strokes,
        isEraser: _isEraser,
        penColor: _penColor,
        strokeWidth: _strokeWidth,
        onStrokesChanged: (newStrokes) {
          setState(() {
            _strokes.clear();
            _strokes.addAll(newStrokes);
          });
        },
      ),
    );
  }

  Widget _buildDrawingTools() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolBtn(Icons.edit_rounded, !_isEraser,
              () => setState(() => _isEraser = false)),
          const SizedBox(height: 8),
          _toolBtn(Icons.auto_fix_normal_rounded, _isEraser,
              () => setState(() => _isEraser = true)),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(height: 1, width: 24, color: _border)),
          _colorDot(_text),
          const SizedBox(height: 8),
          _colorDot(_accent),
          const SizedBox(height: 8),
          _colorDot(const Color(0xFF2563EB)),
          const SizedBox(height: 8),
          _colorDot(const Color(0xFF16A34A)),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(height: 1, width: 24, color: _border)),
          // Stroke width slider (vertical)
          RotatedBox(
            quarterTurns: 3,
            child: SizedBox(
              width: 80,
              child: Slider(
                value: _strokeWidth,
                min: 1.0,
                max: 12.0,
                divisions: 11,
                activeColor: _accent,
                inactiveColor: _border,
                onChanged: (v) => setState(() => _strokeWidth = v),
              ),
            ),
          ),
          Text(
            '${_strokeWidth.round()}px',
            style: GoogleFonts.spaceMono(fontSize: 7, color: _muted),
          ),
          const SizedBox(height: 8),
          IconButton(
            icon:
                const Icon(Icons.delete_sweep_rounded, size: 20, color: _muted),
            onPressed: () {
              HapticFeedback.mediumImpact();
              setState(() => _strokes.clear());
            },
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active ? _accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: active ? _accent : _muted),
      ),
    );
  }

  Widget _colorDot(Color color) {
    final active = _penColor == color && !_isEraser;
    return GestureDetector(
      onTap: () => setState(() {
        _penColor = color;
        _isEraser = false;
      }),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border:
              Border.all(color: active ? _paper : Colors.transparent, width: 2),
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)]
              : null,
        ),
      ),
    );
  }

  Widget _buildZenPanel() {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: Color(0xE00D0D0B), // hud-bg
        border: Border(left: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Text(
                  'ZEN.AI',
                  style: GoogleFonts.spaceMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.02,
                      color: _accent),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _paper,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('CANVAS',
                      style: GoogleFonts.spaceMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _text2)),
                ),
              ],
            ),
          ),

          // Quick actions
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _quickAct('Summarise'),
                _quickAct('Grammar'),
                _quickAct('Expand'),
                _quickAct('Quiz Me'),
              ],
            ),
          ),

          // Feed
          Expanded(
            child: ListView.builder(
              controller: _aiScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              itemCount: _aiMessages.length + (_isAiTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _aiMessages.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Zen is thinking...',
                        style: GoogleFonts.spaceMono(
                            fontSize: 10,
                            color: _muted,
                            fontStyle: FontStyle.italic)),
                  );
                }
                final msg = _aiMessages[index];
                final isUser = msg['role'] == 'user';
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(isUser ? 'YOU' : 'ZEN',
                          style: GoogleFonts.spaceMono(
                              fontSize: 7.5,
                              color: _muted,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: isUser ? _blueBg : _accentBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isUser
                                  ? const Color(0x2E2563EB)
                                  : const Color(0x26D4580A)),
                        ),
                        child: Text(
                          msg['content']!,
                          style: GoogleFonts.lora(
                              fontSize: 12, height: 1.55, color: _text),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: Colors.white10,
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _aiInputController,
                      style: GoogleFonts.spaceMono(fontSize: 11, color: _text),
                      decoration: InputDecoration(
                        hintText: 'Ask Zen anything.',
                        hintStyle: GoogleFonts.spaceMono(color: _muted),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (t) {
                        if (t.trim().isNotEmpty) {
                          _sendToZen(t);
                          _aiInputController.clear();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    final t = _aiInputController.text.trim();
                    if (t.isNotEmpty) {
                      _sendToZen(t);
                      _aiInputController.clear();
                    }
                  },
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _accentBg,
                      border: Border.all(color: const Color(0x40D4580A)),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_upward_rounded,
                        size: 14, color: _accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAct(String label) {
    return InkWell(
      onTap: () => _sendToZen(
          'Please $label this note:\\n${_contentController.text}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _border),
        ),
        child: Text(label,
            style: GoogleFonts.spaceMono(fontSize: 8.5, color: _muted)),
      ),
    );
  }
}

class CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;
  CanvasPainter(this.strokes, this.currentStroke);

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _paintStroke(canvas, currentStroke!);
    }
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DotPainter extends CustomPainter {
  const DotPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x2EFFF8E6); // .18 canvas-dots
    for (double i = 0; i < size.width; i += 20) {
      for (double j = 0; j < size.height; j += 20) {
        canvas.drawCircle(Offset(i, j), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CanvasDrawingLayer extends StatefulWidget {
  final List<Stroke> strokes;
  final bool isEraser;
  final Color penColor;
  final double strokeWidth;
  final Function(List<Stroke>) onStrokesChanged;

  const CanvasDrawingLayer({
    super.key,
    required this.strokes,
    required this.isEraser,
    required this.penColor,
    required this.strokeWidth,
    required this.onStrokesChanged,
  });

  @override
  State<CanvasDrawingLayer> createState() => _CanvasDrawingLayerState();
}

class _CanvasDrawingLayerState extends State<CanvasDrawingLayer> {
  Stroke? _currentStroke;

  void _erasePath(Offset point) {
    setState(() {
      widget.strokes.removeWhere((stroke) {
        for (final p in stroke.points) {
          if ((p - point).distance < 20.0) return true;
        }
        return false;
      });
      widget.onStrokesChanged(widget.strokes);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        if (widget.isEraser) {
          _erasePath(details.localPosition);
        } else {
          setState(() {
            _currentStroke = Stroke(
              points: [details.localPosition],
              color: widget.penColor,
              width: widget.strokeWidth,
            );
          });
        }
      },
      onPanUpdate: (details) {
        if (widget.isEraser) {
          _erasePath(details.localPosition);
        } else if (_currentStroke != null) {
          setState(() {
            _currentStroke!.points.add(details.localPosition);
          });
        }
      },
      onPanEnd: (details) {
        if (!widget.isEraser && _currentStroke != null) {
          setState(() {
            widget.strokes.add(_currentStroke!);
            _currentStroke = null;
            widget.onStrokesChanged(List.from(widget.strokes));
          });
        }
      },
      child: Stack(
        children: [
          Container(color: const Color(0xFF13130F)), // _paper
          const RepaintBoundary(
            child: CustomPaint(
              painter: DotPainter(),
              size: Size.infinite,
            ),
          ),
          CustomPaint(
            painter: CanvasPainter(widget.strokes, _currentStroke),
            size: Size.infinite,
          ),
        ],
      ),
    );
  }
}
