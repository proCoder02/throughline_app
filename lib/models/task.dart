class Task {
  final int id;
  final int? conversationId;
  final String description;
  final String? owner;
  final String? dueDate; // free-text phrase, not a real date
  final DateTime? reminderAt;
  final bool reminderSent;
  final bool emailSent;
  final String status; // "open" | "done"
  final DateTime createdAt;
  final String category;

  Task({
    required this.id,
    required this.conversationId,
    required this.description,
    required this.owner,
    required this.dueDate,
    required this.reminderAt,
    required this.reminderSent,
    required this.emailSent,
    required this.status,
    required this.createdAt,
    required this.category,
  });

  bool get isDone => status == 'done';

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        conversationId: json['conversation_id'],
        description: json['description'],
        owner: json['owner'],
        dueDate: json['due_date'],
        reminderAt: json['reminder_at'] != null ? DateTime.parse(json['reminder_at']) : null,
        reminderSent: json['reminder_sent'] ?? false,
        emailSent: json['email_sent'] ?? false,
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
        category: json['category'] ?? 'personal',
      );
}
