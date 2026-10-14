// Модели ответов API — только нужные экранам поля.

class Lesson {
  final String start, end, title, kind, room, teacher, status;

  /// Чьи это пары: поток («УИБО-01-24, УИБО-02-24…»), у преподавателя — группы.
  final String groups;

  /// Номер пары по звонку: «4», у сдвоенной — «1–5» (поле `num` в API).
  final String number;

  /// Сколько пар в блоке: подряд идущие одинаковые склеены в один (`pairs`).
  final int pairs;
  final DateTime? startAt, endAt;

  /// Пары блока по отдельности (`parts`, только у блока): «до конца пары» в
  /// пяти парах военки — до конца текущей, а не всего блока (14.10).
  final List<(DateTime, DateTime)> parts;

  /// Изменения в расписании (5.79, своя группа): прежний кабинет и когда
  /// заметили перенос; отменённая пара — [cancelled] (её нет в счёте пар).
  final String roomWas, changedAt;
  final bool cancelled;

  const Lesson({
    required this.start,
    required this.end,
    required this.title,
    required this.kind,
    required this.room,
    required this.teacher,
    required this.status,
    this.groups = '',
    this.number = '',
    this.pairs = 1,
    this.startAt,
    this.endAt,
    this.parts = const [],
    this.roomWas = '',
    this.changedAt = '',
    this.cancelled = false,
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
    start: j['start'] ?? '',
    end: j['end'] ?? '',
    title: j['title'] ?? '',
    kind: j['kind'] ?? '',
    room: j['room'] ?? '',
    teacher: j['teacher'] ?? '',
    status: j['status'] ?? '',
    groups: j['groups'] ?? '',
    number: j['num'] == null ? '' : '${j['num']}',
    pairs: j['pairs'] is int ? j['pairs'] as int : 1,
    startAt: j['start_iso'] != null ? DateTime.tryParse(j['start_iso']) : null,
    endAt: j['end_iso'] != null ? DateTime.tryParse(j['end_iso']) : null,
    parts: [
      for (final x in (j['parts'] as List? ?? const []))
        if (x is List && x.length == 2 && DateTime.tryParse('${x[0]}') != null && DateTime.tryParse('${x[1]}') != null)
          (DateTime.parse('${x[0]}'), DateTime.parse('${x[1]}')),
    ],
    roomWas: j['room_was'] ?? '',
    changedAt: j['room_changed_at'] ?? j['cancelled_at'] ?? '',
    cancelled: j['cancelled_at'] != null,
  );

  /// Что идёт в [t] внутри пары или блока: номер пары блока (с 1), сколько
  /// их, начало и конец текущей пары; [pause] — перемена между парами блока
  /// (тогда начало и конец — самой перемены). Не идёт — null.
  ({int index, int of, DateTime start, DateTime end, bool pause})? liveAt(DateTime t) {
    final s = startAt, e = endAt;
    if (s == null || e == null || t.isBefore(s) || !t.isBefore(e)) return null;
    for (var i = 0; i < parts.length; i++) {
      final (a, b) = parts[i];
      if (!t.isBefore(a) && t.isBefore(b)) return (index: i + 1, of: parts.length, start: a, end: b, pause: false);
      if (i + 1 < parts.length && !t.isBefore(b) && t.isBefore(parts[i + 1].$1)) {
        return (index: i + 2, of: parts.length, start: b, end: parts[i + 1].$1, pause: true);
      }
    }
    return (index: 1, of: 1, start: s, end: e, pause: false);
  }

  /// «Лекция · А-17 (В-78)»
  String get place =>
      [if (kind.isNotEmpty) kind[0].toUpperCase() + kind.substring(1), if (room.isNotEmpty) room].join(' · ');
}

/// «Итоги дня» (поле `summary` в /day): что сдал и сколько баллов прибавилось.
class DaySummary {
  /// Сданные работы по частям: (работа, предмет) — «Практика 1», «Анализ данных».
  /// Предмет бывает пустым (своё название без курса); у старого сервера есть
  /// только `title` — тогда он целиком в работе.
  final List<(String, String)> done;

  /// Прирост баллов по предметам: (предмет, изменение), бывает и минус.
  final List<(String, double)> grades;

  /// Сумма изменений баллов за день.
  final double points;

  const DaySummary({this.done = const [], this.grades = const [], this.points = 0});

  factory DaySummary.fromJson(Map<String, dynamic> j) => DaySummary(
    done: [
      for (final d in (j['done'] as List? ?? const []))
        if (d is Map && '${d['task'] ?? d['title'] ?? ''}'.isNotEmpty)
          ('${d['task'] ?? d['title']}', '${d['course'] ?? ''}'),
    ],
    grades: [
      for (final g in (j['grades'] as List? ?? const []))
        if (g is Map && g['delta'] is num) ('${g['name'] ?? 'Предмет'}', (g['delta'] as num).toDouble()),
    ],
    points: (j['points'] as num?)?.toDouble() ?? 0,
  );

  bool get isEmpty => done.isEmpty && grades.isEmpty;
}

class Deadline {
  final int id;
  final String subject, dueDate, dueTime;
  final bool done;

  /// Задание СДО, которое можно сдать файлом из приложения.
  final bool canSubmit;

  const Deadline({
    required this.id,
    required this.subject,
    required this.dueDate,
    required this.dueTime,
    this.done = false,
    this.canSubmit = false,
  });

  factory Deadline.fromJson(Map<String, dynamic> j) => Deadline(
    id: j['id'] as int,
    subject: j['subject'] ?? '',
    dueDate: j['due_date'] ?? '',
    dueTime: j['due_time'] ?? '',
    done: (j['done'] ?? 0) == 1 || j['done'] == true,
    canSubmit: j['can_submit'] == true,
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

/// Месяц коротко: «9 окт» (в листах, где дат много).
const monthsShort = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

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
