// Модели ответов API — только нужные экранам поля.

class Lesson {
  final String start, end, title, kind, room, teacher, status;
  final DateTime? startAt, endAt;

  const Lesson({
    required this.start,
    required this.end,
    required this.title,
    required this.kind,
    required this.room,
    required this.teacher,
    required this.status,
    this.startAt,
    this.endAt,
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
    start: j['start'] ?? '',
    end: j['end'] ?? '',
    title: j['title'] ?? '',
    kind: j['kind'] ?? '',
    room: j['room'] ?? '',
    teacher: j['teacher'] ?? '',
    status: j['status'] ?? '',
    startAt: j['start_iso'] != null ? DateTime.tryParse(j['start_iso']) : null,
    endAt: j['end_iso'] != null ? DateTime.tryParse(j['end_iso']) : null,
  );

  /// «Лекция · А-17 (В-78)»
  String get place =>
      [if (kind.isNotEmpty) kind[0].toUpperCase() + kind.substring(1), if (room.isNotEmpty) room].join(' · ');
}

class Deadline {
  final int id;
  final String subject, dueDate, dueTime;
  final bool done;

  const Deadline({
    required this.id,
    required this.subject,
    required this.dueDate,
    required this.dueTime,
    this.done = false,
  });

  factory Deadline.fromJson(Map<String, dynamic> j) => Deadline(
    id: j['id'] as int,
    subject: j['subject'] ?? '',
    dueDate: j['due_date'] ?? '',
    dueTime: j['due_time'] ?? '',
    done: (j['done'] ?? 0) == 1 || j['done'] == true,
  );

  DateTime get due {
    final t = dueTime.isEmpty ? '23:59' : dueTime;
    return DateTime.tryParse('${dueDate}T$t:00') ?? DateTime(2100);
  }
}

const weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
const weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const monthsGen = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String dayTitle(DateTime d) => '${weekdays[d.weekday - 1]}, ${d.day} ${monthsGen[d.month - 1]}';

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// «13 ч 02 мин», «73 мин», «2 дня»
String leftText(Duration d) {
  if (d.isNegative) return 'срок прошёл';
  if (d.inHours >= 48) return '${d.inDays} ${plural(d.inDays, 'день', 'дня', 'дней')}';
  if (d.inHours >= 1) return '${d.inHours} ч ${(d.inMinutes % 60).toString().padLeft(2, '0')} мин';
  return '${d.inMinutes} мин';
}

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}
