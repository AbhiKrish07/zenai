import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class NotesModuleScreen extends StatefulWidget {
  const NotesModuleScreen({super.key});
  @override
  State<NotesModuleScreen> createState() => _NotesModuleScreenState();
}

class _NotesModuleScreenState extends State<NotesModuleScreen> {
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  
  @override
  void initState() {
    super.initState();
    _loadNotes();
  }
  
  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesString = prefs.getString('quick_notes');
    if (notesString != null) {
      final List<dynamic> decoded = jsonDecode(notesString);
      setState(() {
        _notes = List<Map<String, dynamic>>.from(decoded);
      });
    }
    setState(() => _loading = false);
  }
  
  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quick_notes', jsonEncode(_notes));
  }
  
  void _addNote() {
    _showNoteDialog();
  }
  
  void _editNote(int index) {
    _showNoteDialog(index: index, initialText: _notes[index]['content']);
  }
  
  void _deleteNote(int index) {
    setState(() {
      _notes.removeAt(index);
    });
    _saveNotes();
  }

  void _showNoteDialog({int? index, String initialText = ''}) {
    final ctrl = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: BlitzTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(index == null ? 'New Note' : 'Edit Note',
            style: GoogleFonts.syne(
              color: BlitzTheme.textPrimary,
              fontWeight: FontWeight.w700,
            )),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          autofocus: true,
          style: GoogleFonts.spaceMono(color: BlitzTheme.textPrimary, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Type your note here...',
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: GoogleFonts.syne(color: BlitzTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  if (index == null) {
                    _notes.insert(0, {
                      'content': text,
                      'timestamp': DateTime.now().toIso8601String(),
                    });
                  } else {
                    _notes[index]['content'] = text;
                    _notes[index]['timestamp'] = DateTime.now().toIso8601String();
                  }
                });
                _saveNotes();
              }
              Navigator.pop(c);
            },
            child: const Text('Save'),
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
              Expanded(
                child: _loading 
                  ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent))
                  : _notes.isEmpty
                    ? Center(
                        child: Text(
                          'No notes yet. Tap + to create one.',
                          style: GoogleFonts.syne(color: BlitzTheme.textMuted),
                        )
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          final date = DateTime.parse(note['timestamp']);
                          return GestureDetector(
                            onTap: () => _editNote(index),
                            child: GlassContainer(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted),
                                      ),
                                      GestureDetector(
                                        onTap: () => _deleteNote(index),
                                        child: const Icon(Icons.close_rounded, size: 16, color: BlitzTheme.red),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    note['content'],
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
        onPressed: _addNote,
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
          const Icon(Icons.notes_rounded, size: 24, color: BlitzTheme.cyan),
          const SizedBox(width: 8),
          Text(
            'QUICK NOTES',
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
