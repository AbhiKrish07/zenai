import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../core/database.dart';
import '../../models/reading_item.dart';
import '../../widgets/shared_widgets.dart';

class ReadingModuleScreen extends StatefulWidget {
  const ReadingModuleScreen({super.key});
  @override
  State<ReadingModuleScreen> createState() => _ReadingModuleScreenState();
}

class _ReadingModuleScreenState extends State<ReadingModuleScreen> with SingleTickerProviderStateMixin {
  final _db = ZenDatabase();
  late TabController _tabController;
  List<ReadingItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    final items = await _db.getReadingItems();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  List<ReadingItem> _filteredItems(String status) => _items.where((i) => i.status == status).toList();

  Future<void> _addItem() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String type = 'article';
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(builder: (c, ss) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: BlitzTheme.textMuted.withValues(alpha: 0.3)))),
          const SizedBox(height: 20),
          Text('Add to Queue', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800, color: BlitzTheme.textPrimary)),
          const SizedBox(height: 16),
          TextField(controller: titleCtrl, autofocus: true, style: GoogleFonts.syne(color: BlitzTheme.textPrimary), decoration: const InputDecoration(hintText: 'Title')),
          const SizedBox(height: 8),
          TextField(controller: urlCtrl, style: GoogleFonts.syne(color: BlitzTheme.textPrimary), decoration: const InputDecoration(hintText: 'URL (optional)')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: ['article', 'book', 'paper', 'video'].map((t) {
            final sel = type == t;
            return GestureDetector(
              onTap: () => ss(() => type = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: sel ? BlitzTheme.green.withValues(alpha: 0.12) : Colors.transparent, border: Border.all(color: sel ? BlitzTheme.green : BlitzTheme.border)),
                child: Text(t.toUpperCase(), style: GoogleFonts.spaceMono(fontSize: 9, fontWeight: FontWeight.w700, color: sel ? BlitzTheme.green : BlitzTheme.textMuted)),
              ),
            );
          }).toList()),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty) return;
              await _db.insertReadingItem(ReadingItem(title: titleCtrl.text.trim(), url: urlCtrl.text.trim(), itemType: type));
              if (c.mounted) Navigator.pop(c);
              _loadData();
            },
            child: const Text('Add Item'),
          )),
        ]),
      )),
    );
  }

  void _cycleStatus(ReadingItem item) async {
    const cycle = ['queued', 'in_progress', 'completed', 'archived'];
    final idx = cycle.indexOf(item.status);
    final next = cycle[(idx + 1) % cycle.length];
    await _db.updateReadingStatus(item.id, next);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlitzTheme.bg,
      appBar: AppBar(
        title: Text('Reading Queue', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addItem)],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: BlitzTheme.accent,
          labelStyle: GoogleFonts.spaceMono(fontSize: 9, fontWeight: FontWeight.w700),
          unselectedLabelColor: BlitzTheme.textMuted,
          tabs: const [Tab(text: 'QUEUED'), Tab(text: 'READING'), Tab(text: 'DONE'), Tab(text: 'ALL')],
        ),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent)) : TabBarView(
        controller: _tabController,
        children: [
          _buildList(_filteredItems('queued')),
          _buildList(_filteredItems('in_progress')),
          _buildList(_filteredItems('completed')),
          _buildList(_items),
        ],
      ),
    );
  }

  Widget _buildList(List<ReadingItem> items) {
    if (items.isEmpty) return const EmptyState(icon: Icons.menu_book, title: 'Nothing here', subtitle: 'Add articles, books, or papers to read.', color: BlitzTheme.green);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return GestureDetector(
          onTap: () => _cycleStatus(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withValues(alpha: 0.04), border: Border.all(color: BlitzTheme.border)),
            child: Row(children: [
              Text(item.typeEmoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: BlitzTheme.textPrimary)),
                if (item.author.isNotEmpty) Text(item.author, style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: BlitzTheme.green.withValues(alpha: 0.12)),
                child: Text(item.statusLabel, style: GoogleFonts.spaceMono(fontSize: 8, fontWeight: FontWeight.w700, color: BlitzTheme.green)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
