import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../core/database.dart';
import '../core/zen_brain.dart';
import '../models/task.dart';
import '../services/zen_notifier.dart';
import '../widgets/shared_widgets.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with AutomaticKeepAliveClientMixin {
  final _db = ZenDatabase();
  final _brain = ZenBrain();
  
  List<Task> _tasks = [];
  bool _loading = true;
  bool _showCompleted = true;
  String _filter = 'all'; // all, critical, high, medium, low

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    final tasks = await _db.getTasks(includeCompleted: _showCompleted);
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    }
  }

  List<Task> get _filteredTasks {
    List<Task> filtered = _filter == 'all' 
        ? List<Task>.from(_tasks) 
        : _tasks.where((t) => t.priority == _filter).toList();
        
    filtered.sort((a,b) {
      if (!a.completed && b.completed) return -1;
      if (a.completed && !b.completed) return 1;
      int c = _priorityWeight(b.priority).compareTo(_priorityWeight(a.priority));
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
    return filtered;
  }

  int _priorityWeight(String p) {
    switch (p.toLowerCase()) {
      case 'critical': return 4;
      case 'high': return 3;
      case 'medium': return 2;
      case 'low': return 1;
      default: return 0;
    }
  }

  Future<void> _addTask() async {
    await _showTaskDialog();
  }

  Future<void> _editTask(Task task) async {
    await _showTaskDialog(existingTask: task);
  }

  Future<void> _showTaskDialog({Task? existingTask}) async {
    final titleController = TextEditingController(text: existingTask?.title ?? '');
    final descController = TextEditingController(text: existingTask?.description ?? '');
    String priority = existingTask?.priority ?? 'medium';
    DateTime? dueDate = existingTask?.dueDate;
    final isEditing = existingTask != null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BlitzTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: BlitzTheme.textMuted.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    isEditing ? 'Edit Task' : 'New Task',
                    style: GoogleFonts.syne(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: BlitzTheme.textPrimary,
                    ),
                  ),
                  if (isEditing) ...[ 
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _db.deleteTask(existingTask.id);
                        await ZenNotifier().cancelReminder(existingTask.id); // Cancel reminder on delete
                        _loadTasks();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: BlitzTheme.red.withValues(alpha: 0.1),
                          border: Border.all(color: BlitzTheme.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.delete_outline_rounded, size: 14, color: BlitzTheme.red),
                          const SizedBox(width: 4),
                          Text('Delete', style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.red)),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                autofocus: !isEditing,
                style: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 16),
                decoration: const InputDecoration(hintText: 'What needs to be done?'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descController,
                style: GoogleFonts.syne(color: BlitzTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Add notes (optional)',
                  hintStyle: GoogleFonts.syne(color: BlitzTheme.textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              // Priority selector
              Text('Priority', style: GoogleFonts.spaceMono(fontSize: 10, color: BlitzTheme.textMuted, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Row(
                children: ['high', 'medium', 'low'].map((p) {
                  final selected = priority == p;
                  final color = _priorityColor(p);
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(() => priority = p),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
                          border: Border.all(
                            color: selected ? color : BlitzTheme.border,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            p.toUpperCase(),
                            style: GoogleFonts.spaceMono(
                              fontSize: 7, fontWeight: FontWeight.w700,
                              color: selected ? color : BlitzTheme.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Due date
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: dueDate ?? DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    if (!context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: dueDate != null 
                          ? TimeOfDay(hour: dueDate!.hour, minute: dueDate!.minute)
                          : const TimeOfDay(hour: 17, minute: 0),
                    );
                    if (!context.mounted) return;
                    setModalState(() {
                      dueDate = DateTime(
                        date.year, date.month, date.day,
                        time?.hour ?? 17, time?.minute ?? 0,
                      );
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: dueDate != null ? ZenTheme.accent.withValues(alpha: 0.4) : BlitzTheme.border,
                    ),
                    color: dueDate != null ? ZenTheme.accent.withValues(alpha: 0.05) : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 16, 
                          color: dueDate != null ? ZenTheme.accent : BlitzTheme.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          dueDate != null
                              ? DateFormat('MMM d, y · HH:mm').format(dueDate!)
                              : 'Set due date (optional)',
                          style: GoogleFonts.syne(
                            fontSize: 13,
                            color: dueDate != null ? BlitzTheme.textPrimary : BlitzTheme.textMuted,
                          ),
                        ),
                      ),
                      if (dueDate != null)
                        GestureDetector(
                          onTap: () => setModalState(() => dueDate = null),
                          child: const Icon(Icons.close_rounded, size: 14, color: BlitzTheme.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZenTheme.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) return;
                    if (isEditing) {
                      final updated = existingTask.copyWith(
                        title: titleController.text.trim(),
                        description: descController.text.trim(),
                        priority: priority,
                        dueDate: dueDate,
                      );
                      await _db.updateTask(updated);
                      if (updated.dueDate != null) {
                        await ZenNotifier().scheduleTaskReminder(updated);
                      } else {
                        await ZenNotifier().cancelReminder(updated.id); // Cancel if due date removed
                      }
                    } else {
                      final task = Task(
                        title: titleController.text.trim(),
                        description: descController.text.trim(),
                        priority: priority,
                        dueDate: dueDate,
                      );
                      await _db.insertTask(task);
                      if (task.dueDate != null) {
                        await ZenNotifier().scheduleTaskReminder(task);
                      }
                    }
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEditing ? 'Task updated!' : 'Task added!', style: GoogleFonts.syne()),
                          backgroundColor: BlitzTheme.surface,
                        ),
                      );
                    }
                    _loadTasks();
                  },
                  child: Text(
                    isEditing ? 'Save Changes' : 'Add Task',
                    style: GoogleFonts.syne(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical': return const Color(0xFFEF4444);
      case 'high': return BlitzTheme.red;
      case 'medium': return BlitzTheme.gold;
      case 'low': return BlitzTheme.green;
      default: return BlitzTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(gradient: BlitzTheme.bgGradient),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterChips(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadTasks,
                color: BlitzTheme.accent,
                backgroundColor: BlitzTheme.surface,
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: BlitzTheme.accent))
                    : _filteredTasks.isEmpty
                        ? EmptyState(
                            icon: Icons.checklist_rounded,
                            title: 'No Tasks',
                            subtitle: 'Add your first task or Ask Zen to help prioritize your day.',
                            color: ZenTheme.accent,
                            onAction: _addTask,
                            actionLabel: 'Add Task',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                            itemCount: _filteredTasks.length,
                            itemBuilder: (context, i) => _buildTaskCard(_filteredTasks[i]),
                          ),
              ),
            ),
          ],
        ),
      ),
    ),
   );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          const Icon(Icons.checklist_rounded, size: 20, color: ZenTheme.accent),
          const SizedBox(width: 10),
          Text(
            'TASKS',
            style: GoogleFonts.syne(
              fontSize: 20, fontWeight: FontWeight.w800,
              color: BlitzTheme.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              setState(() => _showCompleted = !_showCompleted);
              _loadTasks();
            },
            icon: Icon(
              _showCompleted ? Icons.visibility_off : Icons.visibility,
              size: 16, color: BlitzTheme.textMuted,
            ),
            label: Text(
              _showCompleted ? 'Hide Done' : 'Show Done',
              style: GoogleFonts.spaceMono(fontSize: 9, color: BlitzTheme.textMuted),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 20, color: ZenTheme.accent),
            tooltip: 'AI Reprioritize',
            onPressed: () async {
              await _brain.analyzeAndPrioritizeTasks();
              _loadTasks();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tasks re-ranked by Zen', style: GoogleFonts.syne()),
                    backgroundColor: BlitzTheme.surface,
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24, color: ZenTheme.accent),
            onPressed: _addTask,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: ['all', 'high', 'medium', 'low'].map((f) {
          final selected = _filter == f;
          final color = f == 'all' ? BlitzTheme.accent : _priorityColor(f);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
                  border: Border.all(
                    color: selected ? color.withValues(alpha: 0.4) : BlitzTheme.border,
                  ),
                ),
                child: Text(
                  f.toUpperCase(),
                  style: GoogleFonts.spaceMono(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: selected ? color : BlitzTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTaskCard(Task task) {
    final isOverdue = task.dueDate != null && task.dueDate!.isBefore(DateTime.now()) && !task.completed;
    
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: BlitzTheme.red.withValues(alpha: 0.15),
        ),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete_rounded, color: BlitzTheme.red),
      ),
      onDismissed: (_) async {
        await _db.deleteTask(task.id);
        await ZenNotifier().cancelReminder(task.id);
        _loadTasks();
      },
      child: GestureDetector(
        onLongPress: () => _editTask(task),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: task.completed ? 0.02 : 0.04),
            border: Border.all(
              color: isOverdue 
                  ? BlitzTheme.red.withValues(alpha: 0.3)
                  : task.completed 
                      ? BlitzTheme.green.withValues(alpha: 0.2)
                      : BlitzTheme.border,
            ),
          ),
          child: Row(
            children: [
              // Completion checkbox — tap to toggle complete/incomplete
              GestureDetector(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  if (task.completed) {
                    await _db.uncompleteTask(task.id);
                  } else {
                    await _db.completeTask(task.id);
                  }
                  _loadTasks();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: task.completed 
                        ? BlitzTheme.green.withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: task.completed ? BlitzTheme.green : _priorityColor(task.priority).withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: task.completed
                      ? const Icon(Icons.check, size: 14, color: BlitzTheme.green)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              // Task info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: GoogleFonts.syne(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: task.completed 
                            ? BlitzTheme.textMuted 
                            : BlitzTheme.textPrimary,
                        decoration: task.completed ? TextDecoration.lineThrough : null,
                        decorationColor: BlitzTheme.textMuted,
                      ),
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.description,
                        style: GoogleFonts.syne(
                          fontSize: 11,
                          color: BlitzTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (task.dueDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        isOverdue
                            ? 'OVERDUE · ${DateFormat('MMM d').format(task.dueDate!)}'
                            : 'Due ${DateFormat('MMM d, HH:mm').format(task.dueDate!)}',
                        style: GoogleFonts.spaceMono(
                          fontSize: 9,
                          color: isOverdue ? BlitzTheme.red : BlitzTheme.textMuted,
                          fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                    if (task.completed) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Tap circle to reopen',
                        style: GoogleFonts.spaceMono(fontSize: 8, color: BlitzTheme.green.withValues(alpha: 0.5)),
                      ),
                    ],
                  ],
                ),
              ),
              // Right actions
              if (!task.completed) ...[ 
                // Edit button
                GestureDetector(
                  onTap: () => _editTask(task),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.edit_rounded, size: 16, color: BlitzTheme.textMuted.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 4, height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: _priorityColor(task.priority).withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                PriorityTag(priority: task.priority, compact: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
