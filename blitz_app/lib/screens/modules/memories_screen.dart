import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import '../../core/database.dart';
import '../../models/memory_slot.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});
  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final _db = ZenDatabase();
  List<MemorySlot> _memories = [];
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();
    _loadMemories();
  }
  
  Future<void> _loadMemories() async {
    final memories = await _db.getAllMemories();
    if (mounted) {
      setState(() {
        _memories = memories;
        _loading = false;
      });
    }
  }
  
  void _addMemory() {
    _showMemoryDialog();
  }
  
  void _editMemory(MemorySlot memory) {
    _showMemoryDialog(memory: memory);
  }
  
  Future<void> _deleteMemory(String key) async {
    await _db.deleteMemory(key);
    _loadMemories();
  }

  void _showMemoryDialog({MemorySlot? memory}) {
    final keyCtrl = TextEditingController(text: memory?.key ?? '');
    final valueCtrl = TextEditingController(text: memory?.value ?? '');
    
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: BlitzTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(memory == null ? 'New Memory' : 'Edit Memory',
            style: GoogleFonts.syne(
              color: BlitzTheme.textPrimary,
              fontWeight: FontWeight.w700,
            )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: keyCtrl,
              enabled: memory == null, // disable key edit if updating
              style: GoogleFonts.spaceMono(color: memory == null ? BlitzTheme.textPrimary : BlitzTheme.textMuted, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Topic (e.g. Favorite Color)',
                hintStyle: GoogleFonts.spaceMono(color: BlitzTheme.textMuted.withValues(alpha: 0.5)),
                border: InputBorder.none,
              ),
            ),
            const Divider(color: BlitzTheme.border),
            TextField(
              controller: valueCtrl,
              maxLines: 4,
              autofocus: memory != null,
              style: GoogleFonts.spaceMono(color: BlitzTheme.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'What should I remember about this?',
                hintStyle: GoogleFonts.spaceMono(color: BlitzTheme.textMuted.withValues(alpha: 0.5)),
                border: InputBorder.none,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: GoogleFonts.syne(color: BlitzTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final k = keyCtrl.text.trim();
              final v = valueCtrl.text.trim();
              if (k.isNotEmpty && v.isNotEmpty) {
                await _db.setMemory(k, v);
                if (mounted) _loadMemories();
                if (c.mounted) Navigator.pop(c);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: BlitzTheme.accent),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                alignment: Alignment.centerLeft,
                child: Text(
                  'These details are injected into Zen\'s context during conversation.',
                  style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted),
                ),
              ),
              Expanded(
                child: _loading 
                  ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent))
                  : _memories.isEmpty
                    ? Center(
                        child: Text(
                          'No memories stored yet.\n\nTell Zen "Remember that..."\nor add one manually.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceMono(fontSize: 12, color: BlitzTheme.textMuted),
                        )
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _memories.length,
                        itemBuilder: (context, index) {
                          final mem = _memories[index];
                          return GestureDetector(
                            onTap: () => _editMemory(mem),
                            child: GlassContainer(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        mem.key.toUpperCase(),
                                        style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.bold, color: BlitzTheme.cyan),
                                      ),
                                      GestureDetector(
                                        onTap: () => _deleteMemory(mem.key),
                                        child: const Icon(Icons.close_rounded, size: 16, color: BlitzTheme.red),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    mem.value,
                                    style: GoogleFonts.spaceMono(fontSize: 12, color: BlitzTheme.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMemory,
        backgroundColor: BlitzTheme.accent,
        child: const Icon(Icons.add, color: Colors.white),
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
          const Icon(Icons.memory_rounded, size: 24, color: BlitzTheme.accent),
          const SizedBox(width: 8),
          Text(
            'ZEN MEMORY',
            style: GoogleFonts.syne(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: BlitzTheme.textPrimary,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
