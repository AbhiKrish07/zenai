import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../core/database.dart';
import '../widgets/zen_chat_bubble.dart';
import 'standby_screen.dart';
import '../core/zen_brain.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../voice/voice_engine.dart';
import '../voice/voice_state.dart';

/// ═══════════════════════════════════════════════════════
///   Zen AI Chat — Neural Interface (Black & Orange)
///   Part of CommandCenter — Synchronized with Dashboard
/// ═══════════════════════════════════════════════════════

class ChatScreen extends StatefulWidget {
  final VoidCallback? onStateChanged; // ── Neural sync with Dashboard ──
  const ChatScreen({super.key, this.onStateChanged});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin {
  final _brain = ZenBrain();
  final _db = ZenDatabase();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _uuid = const Uuid();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ChatMessage> _messages = [];
  List<ChatSession> _sessions = [];
  List<ChatSession> _trashSessions = [];
  List<Map<String, dynamic>> _folders = [];
  ChatSession? _currentSession;
  
  bool _isTyping = false;
  bool _loading = true;
  bool _isListening = false;
  final _voice = VoiceEngine();
  StreamSubscription? _voiceSub;
  final Color _accentColor = const Color(0xFFFF4500);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _initVoiceSystem();
  }

  void _initVoiceSystem() {
    _voiceSub = _voice.transcriptStream.listen((t) {
      if (mounted && _isListening) {
        setState(() => _controller.text = t);
      }
    });
    _voice.stateStream.listen((s) {
      if (!mounted) return;
      if (s == VoiceState.idle && _isListening) {
        _isListening = false;
        _sendMessage(_controller.text);
      }
    });
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadFolders();
    final sessions = await _db.getChatSessions();
    final trash = await _db.getTrashSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _trashSessions = trash;
        if (_sessions.isEmpty) {
          _currentSession = null;
          _messages = [];
        } else {
          // If current session is gone or we need initial pick
          if (_currentSession == null || !_sessions.any((s) => s.id == _currentSession!.id)) {
            _currentSession = _sessions.firstWhere((s) => !s.isArchived, orElse: () => _sessions.first);
          }
        }
      });
      await _loadMessages();
    }
  }

  Future<void> _loadFolders() async {
    final folders = await _db.getFolders();
    if (mounted) setState(() => _folders = List.from(folders));
  }

  Future<void> _loadMessages() async {
    final messages = await _db.getRecentMessages(limit: 50, sessionId: _currentSession?.id);
    if (mounted) {
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _createNewChat() async {
    final newSession = ChatSession(
      id: _uuid.v4(), 
      title: 'Neural Link ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}', 
      updatedAt: DateTime.now()
    );
    await _db.insertChatSession(newSession);
    if (!mounted) return;
    
    setState(() {
       _currentSession = newSession;
       _loading = true;
    });
    
    await _loadInitialData();
    if (!mounted) return;
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) { Navigator.pop(context); }
    _focusNode.requestFocus();
  }

  Future<void> _trashSession(ChatSession session) async {
    await _db.trashChatSession(session.id);
    _loadInitialData();
  }

  Future<void> _restoreSession(ChatSession session) async {
    await _db.restoreChatSession(session.id);
    _loadInitialData();
  }

  Future<void> _deleteSessionPermanently(ChatSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text('DELETE ARCHIVE?', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 2)),
        content: Text('This will permanently erase this neural link and all contained data.', style: GoogleFonts.dmSans(color: Colors.white60, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('CANCEL', style: GoogleFonts.spaceMono(color: Colors.white24, fontSize: 10))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('DELETE', style: GoogleFonts.spaceMono(color: Colors.redAccent, fontSize: 10))),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deleteChatSession(session.id);
      _loadInitialData();
    }
  }

  void _switchSession(ChatSession session) {
    setState(() { _currentSession = session; _loading = true; });
    _loadMessages();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) { Navigator.pop(context); }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final content = text.trim();
    _controller.clear();
    HapticFeedback.lightImpact();

    if (_currentSession == null) { await _createNewChat(); }

    final userMsg = ChatMessage(id: _uuid.v4(), role: 'user', content: content, timestamp: DateTime.now(), sessionId: _currentSession?.id);
    setState(() { _messages.add(userMsg); _isTyping = true; });
    _scrollToBottom();
    await _db.insertMessage(userMsg);

    try {
      String accumulated = "";
      final assistantId = _uuid.v4();
      final stream = _brain.chatStream(content, sessionId: _currentSession?.id);
      final placeholder = ChatMessage(id: assistantId, role: 'assistant', content: '', timestamp: DateTime.now(), sessionId: _currentSession?.id);
      setState(() { _messages.add(placeholder); });

      await for (final token in stream) {
        accumulated += token;
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == assistantId);
            if (idx != -1) { _messages[idx] = ChatMessage(id: assistantId, role: 'assistant', content: accumulated, timestamp: DateTime.now(), sessionId: _currentSession?.id); }
          });
          _scrollToBottom();
        }
      }
      if (!mounted) return;
      
      String rawContent = accumulated;
      
      // ── ROBUST MULTI-COMMAND PARSING ──
      final cmdRegex = RegExp(r'<CMD>(.*?)</CMD>', dotAll: true);
      final matches = cmdRegex.allMatches(accumulated);
      
      if (matches.isNotEmpty) {
        for (final match in matches) {
          final commandBlock = match.group(1);
          if (commandBlock != null) {
            await _processCommand(commandBlock.trim());
            rawContent = rawContent.replaceAll('<CMD>$commandBlock</CMD>', '').trim();
          }
        }
        // ── SYNC DASHBOARD STATE ──
        if (widget.onStateChanged != null) widget.onStateChanged!();
      }

      final finalAssistantMsg = ChatMessage(id: assistantId, role: 'assistant', content: rawContent, timestamp: DateTime.now(), sessionId: _currentSession?.id);
      await _db.insertMessage(finalAssistantMsg);
      setState(() { _isTyping = false; });
      if (_isListening || _voice.speakEnabled) {
         _voice.speak(rawContent);
      }
    } catch (e) {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _deleteMessage(String id) async {
    await _db.deleteMessage(id);
    setState(() { _messages.removeWhere((m) => m.id == id); });
  }

  Future<void> _processCommand(String cmd) async {
    if (cmd.startsWith('create_task:')) {
      final payload = cmd.substring('create_task:'.length).trim();
      final components = payload.split('|');
      if (components.isNotEmpty) {
        String pRaw = components.length > 1 ? components[1].toLowerCase().trim() : 'medium';
        String p = 'medium';
        if (pRaw == '3' || pRaw.contains('high')) { p = 'high'; }
        else if (pRaw == '1' || pRaw.contains('low')) { p = 'low'; }

        await _db.insertTask(Task(title: components[0], priority: p, description: components.length > 2 ? components[2] : ''));
        _showCommandSnack('New Task: ${components[0]}');
      }
    } else if (cmd.startsWith('create_event:')) {
      final components = cmd.substring('create_event:'.length).trim().split('|');
      if (components.isNotEmpty) {
        await _db.insertEvent(CalendarEvent(id: _uuid.v4(), title: components[0], startTime: DateTime.tryParse(components[1]) ?? DateTime.now(), endTime: DateTime.tryParse(components[2]) ?? DateTime.now().add(const Duration(hours: 1)), description: components.length > 3 ? components[3] : '', createdAt: DateTime.now()));
        _showCommandSnack('Event Scheduled: ${components[0]}');
      }
    }
  }

  void _showCommandSnack(String msg) {
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.dmSans()), backgroundColor: _accentColor, behavior: SnackBarBehavior.floating)); }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      drawer: _buildHistoryDrawer(),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading 
              ? const Center(child: CircularProgressIndicator(color: Colors.white12)) 
              : (_messages.isEmpty ? _buildQuickPrompts() : _buildMessageList()),
          ),
          if (_isTyping) _buildTypingIndicator(),
          _buildInputBar(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer() {
    final activeSessions = _sessions.where((s) => !s.isArchived).toList();

    return Drawer(
      backgroundColor: const Color(0xFF1C1C1E),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
              child: Row(
                children: [
                  Text('NEURAL ARCHIVE', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 13)),
                  const Spacer(),
                  IconButton(onPressed: _createNewChat, icon: Icon(Icons.add_circle_outline_rounded, color: _accentColor, size: 20)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Folders
                  ..._folders.map((f) => _buildFolderSection(f, activeSessions)),
                  const SizedBox(height: 12),
                  
                  // Uncategorized
                  _buildHistoryHeader('UNCATEGORIZED'),
                  ...activeSessions.where((s) => s.folderId == null).map((s) => _buildDraggableSessionTile(s)),

                  // Archived
                  if (_sessions.any((s) => s.isArchived)) ...[
                    const SizedBox(height: 24),
                    _buildHistoryHeader('ARCHIVED'),
                    ..._sessions.where((s) => s.isArchived).map((s) => _buildDraggableSessionTile(s)),
                  ],

                  // Trash Folder
                  if (_trashSessions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildTrashFolder(_trashSessions),
                  ],
                ],
              ),
            ),
            _buildDrawerFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryHeader(String title) {
    return Padding(padding: const EdgeInsets.fromLTRB(8, 16, 8, 8), child: Text(title, style: GoogleFonts.spaceMono(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1.5)));
  }

  Widget _buildTrashFolder(List<ChatSession> sessions) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        final sessionId = details.data;
        final session = _sessions.firstWhere((s) => s.id == sessionId, orElse: () => _trashSessions.firstWhere((s) => s.id == sessionId));
        await _trashSession(session);
      },
      builder: (context, candidateData, rejectedData) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: candidateData.isNotEmpty ? Colors.redAccent.withValues(alpha: 0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: Icon(Icons.delete_sweep_rounded, size: 16, color: candidateData.isNotEmpty ? Colors.redAccent : Colors.white24),
          title: Text('NEURAL TRASH', style: GoogleFonts.dmSans(fontSize: 11, color: candidateData.isNotEmpty ? Colors.redAccent : Colors.white38, fontWeight: FontWeight.bold, letterSpacing: 1)),
          trailing: Text(sessions.length.toString(), style: GoogleFonts.spaceMono(fontSize: 10, color: Colors.white10)),
          childrenPadding: const EdgeInsets.only(left: 12),
          shape: const Border(),
          children: sessions.map((s) => _buildTrashTile(s)).toList(),
        ),
      ),
    );
  }

  Widget _buildFolderSection(Map<String, dynamic> folder, List<ChatSession> sessions) {
    final folderId = folder['id'];
    final folderName = folder['name'];
    final items = sessions.where((s) => s.folderId == folderId).toList();

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        final sessionId = details.data;
        await _db.moveSessionToFolder(sessionId, folderId);
        _loadInitialData();
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty ? _accentColor.withValues(alpha: 0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Icon(Icons.folder_open_rounded, size: 16, color: candidateData.isNotEmpty ? _accentColor : Colors.white24),
            title: Text(folderName.toUpperCase(), style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1)),
            trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white12),
            childrenPadding: const EdgeInsets.only(left: 12),
            shape: const Border(),
            children: items.map((s) => _buildDraggableSessionTile(s)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildDraggableSessionTile(ChatSession s) {
    final isSelected = s.id == _currentSession?.id;
    return LongPressDraggable<String>(
      data: s.id,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(12), border: Border.all(color: _accentColor.withValues(alpha: 0.3))),
          child: Text(s.title.toUpperCase(), style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildSessionTile(s, isSelected)),
      child: _buildSessionTile(s, isSelected),
    );
  }

  Widget _buildSessionTile(ChatSession s, bool isSelected) {
    return Dismissible(
      key: Key('chat_session_${s.id}'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
             _showRenameDialog(s);
             return false; // Don't dismiss, just show dialog
        } else {
             await _trashSession(s);
             return true;
        }
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.blueAccent.withValues(alpha: 0.1),
        child: const Icon(Icons.edit_rounded, color: Colors.blueAccent, size: 18),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent.withValues(alpha: 0.1),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        dense: true,
        title: Text(s.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(fontSize: 12, color: isSelected ? _accentColor : Colors.white60, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        trailing: isSelected ? null : PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white10, size: 14),
          color: const Color(0xFF2C2C2E),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'rename', child: Row(children: [const Icon(Icons.edit_rounded, size: 14, color: Colors.white60), const SizedBox(width: 8), Text('Rename', style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white))])),
            PopupMenuItem(value: s.isArchived ? 'unarchive' : 'archive', child: Row(children: [Icon(s.isArchived ? Icons.unarchive_rounded : Icons.archive_outlined, size: 14, color: Colors.white60), const SizedBox(width: 8), Text(s.isArchived ? 'Unarchive' : 'Archive', style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white))])),
            PopupMenuItem(value: 'trash', child: Row(children: [const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent), const SizedBox(width: 8), Text('Move to Trash', style: GoogleFonts.dmSans(fontSize: 12, color: Colors.redAccent))])),
          ],
          onSelected: (val) {
            if (val == 'rename') { _showRenameDialog(s); }
            else if (val == 'archive') { _toggleArchive(s, true); }
            else if (val == 'unarchive') { _toggleArchive(s, false); }
            else if (val == 'trash') { _trashSession(s); }
          },
        ),
        onTap: () {
          Navigator.pop(context);
          _switchSession(s);
        },
      ),
    );
  }

  Widget _buildTrashTile(ChatSession s) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      dense: true,
      leading: const Icon(Icons.auto_delete_rounded, size: 14, color: Colors.white12),
      title: Text(s.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white24)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.restore_rounded, size: 14, color: Colors.white24), onPressed: () => _restoreSession(s)),
          IconButton(icon: Icon(Icons.close_rounded, size: 14, color: Colors.redAccent.withValues(alpha: 0.3)), onPressed: () => _deleteSessionPermanently(s)),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.create_new_folder_outlined, size: 18, color: _accentColor.withValues(alpha: 0.7)),
            title: Text('NEW FOLDER', style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1)),
            onTap: _showNewFolderDialog,
          ),
          DragTarget<String>(
            onWillAcceptWithDetails: (details) => true,
            onAcceptWithDetails: (details) async {
              final sessionId = details.data;
              await _db.moveSessionToFolder(sessionId, null);
              _loadInitialData();
            },
            builder: (context, candidateData, rejectedData) {
              return ListTile(
                dense: true,
                leading: Icon(Icons.remove_circle_outline_rounded, size: 18, color: candidateData.isNotEmpty ? Colors.redAccent : Colors.white24),
                title: Text('MOVE OUT', style: GoogleFonts.dmSans(fontSize: 11, color: candidateData.isNotEmpty ? Colors.redAccent : Colors.white38, fontWeight: FontWeight.bold, letterSpacing: 1)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text('NEW FOLDER', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Folder Name', hintStyle: TextStyle(color: Colors.white24))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () async {
            if (ctrl.text.trim().isNotEmpty) {
              await _db.createFolder(ctrl.text.trim());
              if (!c.mounted) return;
              Navigator.pop(c);
              _loadFolders();
            }
          }, style: ElevatedButton.styleFrom(backgroundColor: _accentColor), child: const Text('CREATE')),
        ],
      ),
    );
  }

  void _showRenameDialog(ChatSession s) {
    final ctrl = TextEditingController(text: s.title);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text('RENAME SESSION', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'New Title', hintStyle: TextStyle(color: Colors.white24))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () async {
            if (ctrl.text.trim().isNotEmpty) {
              await _db.renameSession(s.id, ctrl.text.trim());
              if (!c.mounted) return;
              Navigator.pop(c);
              _loadInitialData();
            }
          }, style: ElevatedButton.styleFrom(backgroundColor: _accentColor), child: const Text('RENAME')),
        ],
      ),
    );
  }

  void _toggleArchive(ChatSession s, bool archive) async {
    await _db.updateSessionArchive(s.id, archive);
    _loadInitialData();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          IconButton(onPressed: () => _scaffoldKey.currentState?.openDrawer(), icon: const Icon(Icons.auto_awesome_mosaic_rounded, color: Colors.white24, size: 20)),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_currentSession?.title.toUpperCase() ?? 'ZEN AI', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white)),
              Text('ACTIVE NEURAL LINK', style: GoogleFonts.spaceMono(fontSize: 7, fontWeight: FontWeight.bold, color: _accentColor.withValues(alpha: 0.6))),
            ],
          )),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StandbyScreen())), icon: const Icon(Icons.flash_on_rounded, color: Colors.white24, size: 20)),
        ],
      ),
    );
  }

  Widget _buildQuickPrompts() {
    final prompts = ['Daily Summary', 'Plan My Work', 'Analyze Startup', 'Creative Focus'];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, color: _accentColor.withValues(alpha: 0.05), border: Border.all(color: _accentColor.withValues(alpha: 0.1))), child: Icon(Icons.auto_awesome_rounded, color: _accentColor)),
          const SizedBox(height: 24),
          Text('HOW CAN I ASSIST?', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white24, letterSpacing: 2)),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
            children: prompts.map((p) => GestureDetector(
              onTap: () => _sendMessage(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                child: Text(p, style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white60)),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        return ZenChatBubble(
          content: m.content, 
          isUser: m.role == 'user', 
          timestamp: m.timestamp,
          onDelete: () => _deleteMessage(m.id),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(padding: const EdgeInsets.fromLTRB(28, 0, 0, 16), child: Row(children: [Text('ZEN IS PROCESSING', style: GoogleFonts.spaceMono(fontSize: 7, color: Colors.white24, letterSpacing: 2)), const SizedBox(width: 8), CircularProgressIndicator(strokeWidth: 1, valueColor: AlwaysStoppedAnimation<Color>(_accentColor.withValues(alpha: 0.3)),)]));
  }

  Widget _buildInputBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: GoogleFonts.dmSans(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: _isListening ? 'Listening...' : 'Type message...', 
                hintStyle: GoogleFonts.dmSans(color: Colors.white24, fontSize: 14), 
                border: InputBorder.none, 
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          IconButton(
            onPressed: () {
              if (_isListening) {
                _voice.stopListening();
                setState(() => _isListening = false);
              } else {
                _voice.startListening();
                setState(() => _isListening = true);
              }
            }, 
            icon: Icon(_isListening ? Icons.mic_rounded : Icons.mic_none_rounded, color: _isListening ? _accentColor : Colors.white24, size: 20)
          ),
          IconButton(onPressed: () => _sendMessage(_controller.text), icon: Icon(Icons.arrow_upward_rounded, color: _accentColor)),
        ],
      ),
    );
  }
}
