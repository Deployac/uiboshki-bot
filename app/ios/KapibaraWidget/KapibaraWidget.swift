// Виджеты Капибары (WidgetKit, iOS 16+): «Пара» — маленький на рабочем столе
// и на экране блокировки (прямоугольный «10:40 · А-17» и круглый «23’»),
// «Весь день» — большой: пары дня и горящий срок.
// Данные — снимок дня, который приложение кладёт файлом в общую папку App
// Group (lib/widget_data.dart → Runner/WidgetBridge.swift). «Через 12 мин»
// виджет считает сам: записи таймлайна — каждую минуту в ближайший час, потом
// раз в 15 минут и на началах и концах пар. День — по дате в Москве.
import SwiftUI
import WidgetKit

// MARK: - Снимок

struct WLesson: Decodable {
  let s: String
  let e: String
  let sa: Double
  let ea: Double
  let t: String
  let r: String
  /// Пара блока (5 пар военки): номер, сколько их и конец блока «15:50».
  /// Снимок кладёт блок по паре на запись — «до конца» считается до конца
  /// текущей пары, а не всего блока («530′», 14.10).
  var n: Int? = nil
  var of: Int? = nil
  var be: String? = nil

  var start: Date { Date(timeIntervalSince1970: sa / 1000) }
  var end: Date { Date(timeIntervalSince1970: ea / 1000) }
  var inBlock: Bool { (of ?? 1) > 1 }
}

/// Строка большого виджета: блок пар — одной строкой.
struct WRow {
  let s: String
  let t: String
  let r: String
  let start: Date
  let end: Date
}

struct WDay: Decodable {
  let d: String
  let h: String
  let part: Bool?
  let l: [WLesson]
}

struct WDeadline: Decodable {
  let t: String
  let due: Double

  var date: Date { Date(timeIntervalSince1970: due / 1000) }
}

struct WSnapshot: Decodable {
  let v: Int
  let at: Double
  let days: [WDay]
  let dl: WDeadline?
}

enum Store {
  /// Папка App Group: от id приложения (AltStore дописывает к нему Team ID),
  /// иначе — как в проекте.
  static func fileURL() -> URL? {
    var parts = (Bundle.main.bundleIdentifier ?? "").split(separator: ".").map(String.init)
    if parts.last == "KapibaraWidget" { parts.removeLast() }
    let app = parts.isEmpty ? "ru.uiboshki.app" : parts.joined(separator: ".")
    for group in ["group.\(app)", "group.ru.uiboshki.app"] {
      if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
        return dir.appendingPathComponent("widget.json")
      }
    }
    return nil
  }

  static func load() -> WSnapshot? {
    guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WSnapshot.self, from: data)
  }
}

// MARK: - Что показать сейчас

enum LessonState {
  /// Снимка нет или он старый — «Открой Капибару».
  case noData
  /// Пар больше нет ни сегодня, ни завтра.
  case free
  case now(WLesson, minutesLeft: Int, progress: Double)
  case next(WLesson, minutes: Int, tomorrow: Bool)
}

enum Sched {
  static let msk = TimeZone(identifier: "Europe/Moscow") ?? TimeZone(secondsFromGMT: 3 * 3600) ?? .current

  static func dayString(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = msk
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
  }

  /// Минут до момента с округлением вверх: за 30 секунд до начала — «1», не «0».
  static func minutes(_ from: Date, _ to: Date) -> Int {
    max(0, Int((to.timeIntervalSince(from) / 60).rounded(.up)))
  }

  static func days(_ s: WSnapshot, _ now: Date) -> (today: WDay?, tomorrow: WDay?) {
    let t = dayString(now)
    let n = dayString(now.addingTimeInterval(86400))
    return (s.days.first { $0.d == t }, s.days.first { $0.d == n })
  }

  static func state(_ snap: WSnapshot?, _ now: Date) -> LessonState {
    guard let s = snap else { return .noData }
    let d = days(s, now)
    if d.today == nil && d.tomorrow == nil { return .noData }
    if let cur = d.today?.l.first(where: { $0.start <= now && now < $0.end }) {
      let total = cur.end.timeIntervalSince(cur.start)
      let p = total > 0 ? now.timeIntervalSince(cur.start) / total : 0
      return .now(cur, minutesLeft: minutes(now, cur.end), progress: min(max(p, 0), 1))
    }
    if let nxt = d.today?.l.first(where: { $0.start > now }) {
      return .next(nxt, minutes: minutes(now, nxt.start), tomorrow: false)
    }
    if let first = d.tomorrow?.l.first {
      return .next(first, minutes: minutes(now, first.start), tomorrow: true)
    }
    return .free
  }

  /// Что после идущей пары сегодня (следующая пара или следующая пара блока).
  static func after(_ snap: WSnapshot?, _ now: Date, _ cur: WLesson) -> WLesson? {
    guard let s = snap else { return nil }
    return days(s, now).today?.l.first { $0.start >= cur.end }
  }

  /// Пары дня строками: блок (военка) — одной, «09:00 … 15:50».
  static func rows(_ day: WDay) -> [WRow] {
    var out: [WRow] = []
    for l in day.l {
      if let n = l.n, n > 1, let last = out.last, last.t == l.t, last.r == l.r {
        out[out.count - 1] = WRow(s: last.s, t: last.t, r: last.r, start: last.start, end: l.end)
      } else {
        out.append(WRow(s: l.s, t: l.t, r: l.r, start: l.start, end: l.end))
      }
    }
    return out
  }

  /// День для большого виджета: сегодня, пока пары не кончились, потом завтра.
  static func dayToShow(_ snap: WSnapshot?, _ now: Date) -> (day: WDay, tomorrow: Bool)? {
    guard let s = snap else { return nil }
    let d = days(s, now)
    if let t = d.today, t.l.contains(where: { $0.end > now }) { return (t, false) }
    if let n = d.tomorrow { return (n, true) }
    if let t = d.today { return (t, false) }
    return nil
  }

  /// «через 12 мин», «через 1 ч 05 мин», «сегодня в 16:20», «завтра в 09:00».
  static func nextLabel(_ l: WLesson, _ m: Int, _ tomorrow: Bool) -> String {
    if tomorrow { return "завтра в \(l.s)" }
    if m < 60 { return "через \(m) мин" }
    if m < 180 { return "через \(m / 60) ч " + String(format: "%02d", m % 60) + " мин" }
    return "сегодня в \(l.s)"
  }

  /// Сколько до срока коротко: «45 мин», «13 ч», «2 дн».
  static func leftShort(_ now: Date, _ due: Date) -> String {
    let m = minutes(now, due)
    if m < 60 { return "\(m) мин" }
    if m < 48 * 60 { return "\(m / 60) ч" }
    return "\(m / (24 * 60)) дн"
  }

  static func deadline(_ snap: WSnapshot?, _ now: Date) -> WDeadline? {
    guard let dl = snap?.dl, dl.date > now, !dl.t.isEmpty else { return nil }
    return dl
  }

  /// Ближайшая полночь по Москве — смена дня.
  static func midnight(after now: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = msk
    let start = cal.startOfDay(for: now)
    return cal.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86400)
  }
}

// MARK: - Таймлайн

struct DayEntry: TimelineEntry {
  let date: Date
  let snap: WSnapshot?
}

/// Пример для списка виджетов: идёт пара, следующая — через 12 минут.
enum Sample {
  static func snapshot(_ now: Date) -> WSnapshot {
    func lesson(_ from: Double, _ to: Double, _ title: String, _ room: String) -> WLesson {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.timeZone = Sched.msk
      f.dateFormat = "HH:mm"
      let a = now.addingTimeInterval(from * 60)
      let b = now.addingTimeInterval(to * 60)
      return WLesson(
        s: f.string(from: a), e: f.string(from: b),
        sa: a.timeIntervalSince1970 * 1000, ea: b.timeIntervalSince1970 * 1000, t: title, r: room)
    }
    let lessons = [
      lesson(-100, -10, "Моделирование бизнес-процессов", "А-17"),
      lesson(12, 102, "Анализ данных", "А-17"),
      lesson(132, 222, "Архитектура предприятия", "А-223"),
    ]
    let day = WDay(d: Sched.dayString(now), h: "СЕГОДНЯ · 3 ПАРЫ", part: false, l: lessons)
    let dl = WDeadline(t: "Лаба 3", due: now.addingTimeInterval(13 * 3600 + 120).timeIntervalSince1970 * 1000)
    return WSnapshot(v: 1, at: now.timeIntervalSince1970 * 1000, days: [day], dl: dl)
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> DayEntry {
    DayEntry(date: Date(), snap: Sample.snapshot(Date()))
  }

  func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
    let now = Date()
    let snap = Store.load()
    completion(DayEntry(date: now, snap: context.isPreview && snap == nil ? Sample.snapshot(now) : snap))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
    let now = Date()
    let snap = Store.load()
    guard let s = snap else {
      completion(Timeline(entries: [DayEntry(date: now, snap: nil)], policy: .after(now.addingTimeInterval(3600))))
      return
    }
    // каждую минуту — час, потом раз в 15 минут до шести часов; плюс начала
    // и концы пар и полночь в ближайшие сутки
    let minute = (now.timeIntervalSince1970 / 60).rounded(.down) * 60
    var times = Set<Date>([now])
    for i in 1...60 { times.insert(Date(timeIntervalSince1970: minute + Double(i) * 60)) }
    for i in 1...20 { times.insert(Date(timeIntervalSince1970: minute + 3600 + Double(i) * 900)) }
    let horizon = now.addingTimeInterval(24 * 3600)
    for day in s.days {
      for l in day.l {
        for t in [l.start, l.end] where t > now && t < horizon { times.insert(t) }
      }
    }
    times.insert(Sched.midnight(after: now))
    let entries = times.sorted().map { DayEntry(date: $0, snap: s) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

// MARK: - Цвета (светлый — «Тетрадь», тёмный — «Глубина»; по теме телефона)

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }
}

struct Pal {
  let bg: Color
  let text: Color
  let muted: Color
  let accent: Color
  let ok: Color
  let danger: Color

  static let light = Pal(
    bg: Color(hex: 0xF3EEE5), text: Color(hex: 0x2A2721), muted: Color(hex: 0x7D776B),
    accent: Color(hex: 0xB75438), ok: Color(hex: 0x5C8A4E), danger: Color(hex: 0xC4473A))
  static let dark = Pal(
    bg: Color(hex: 0x1F2331), text: Color.white, muted: Color(hex: 0x9AA0B2),
    accent: Color(hex: 0x9FA6FF), ok: Color(hex: 0x2FBF71), danger: Color(hex: 0xFF6B6B))

  static func of(_ scheme: ColorScheme) -> Pal { scheme == .dark ? dark : light }
}

extension View {
  /// Фон виджета: с iOS 17 — containerBackground (иначе система рисует
  /// заглушку), до него — обычный фон с полями.
  @ViewBuilder
  func widgetBackground(_ color: Color, padded: Bool = true) -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(for: .widget) { color }
    } else if padded {
      padding(16).background(color)
    } else {
      self
    }
  }
}

// MARK: - «Пара»: маленький

/// Тонкая полоска «сколько прошло».
struct Bar: View {
  let value: Double
  let color: Color
  let track: Color

  var body: some View {
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        Capsule().fill(color).frame(width: max(4, g.size.width * value))
      }
    }
    .frame(height: 5)
  }
}

/// Во время пары: где и что, крупно минуты до конца пары, полоска и что
/// дальше. До пары: через сколько, крупно кабинет, предмет и время.
struct SmallView: View {
  let entry: DayEntry
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let p = Pal.of(scheme)
    let now = entry.date
    return Group {
      switch Sched.state(entry.snap, now) {
      case .noData:
        message(p, top: nil, big: "Капибара", sub: "Открой приложение — здесь появятся пары")
      case .free:
        message(p, top: "сегодня и завтра", big: "Пар нет", sub: "Можно выдохнуть")
      case let .now(l, m, progress):
        live(p, l, m, progress, Sched.after(entry.snap, now, l))
      case let .next(l, m, tomorrow):
        next(p, l, m, tomorrow)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .widgetBackground(p.bg)
  }

  private func label(_ text: String, _ color: Color) -> some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(color).lineLimit(1)
    }
  }

  private func live(_ p: Pal, _ l: WLesson, _ m: Int, _ progress: Double, _ after: WLesson?) -> some View {
    let foot: String
    if l.inBlock, let n = l.n, let of = l.of {
      foot = "пара \(n) из \(of) · до \(l.be ?? l.e)"
    } else if let a = after {
      foot = a.r.isEmpty ? "дальше в \(a.s)" : "дальше \(a.s) · \(a.r)"
    } else {
      foot = "последняя · до \(l.e)"
    }
    return VStack(alignment: .leading, spacing: 0) {
      label(l.r.isEmpty ? "идёт" : "идёт · \(l.r)", p.ok)
      Text(l.t).font(.system(size: 12)).foregroundColor(p.muted).lineLimit(1).padding(.top, 2)
      Spacer(minLength: 0)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(m >= 60 ? "\(m / 60):" + String(format: "%02d", m % 60) : "\(m)")
          .font(.system(size: 40, weight: .bold, design: .rounded))
          .foregroundColor(p.text)
          .monospacedDigit()
        Text(m >= 60 ? "ч" : "мин").font(.system(size: 15, weight: .semibold)).foregroundColor(p.muted)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      Text("до конца пары").font(.system(size: 12)).foregroundColor(p.muted).padding(.bottom, 6)
      Bar(value: progress, color: p.ok, track: p.muted.opacity(0.25))
      Text(foot).font(.system(size: 12, weight: .medium)).foregroundColor(p.text).lineLimit(1).padding(.top, 6)
    }
  }

  private func next(_ p: Pal, _ l: WLesson, _ m: Int, _ tomorrow: Bool) -> some View {
    let pause = !tomorrow && l.inBlock && (l.n ?? 1) > 1
    return VStack(alignment: .leading, spacing: 0) {
      label(pause ? "перемена · \(m) мин" : Sched.nextLabel(l, m, tomorrow), pause ? p.ok : p.accent)
      Spacer(minLength: 0)
      Text(l.r.isEmpty ? l.s : l.r)
        .font(.system(size: 38, weight: .bold, design: .rounded))
        .foregroundColor(p.text)
        .lineLimit(1)
        .minimumScaleFactor(0.45)
      Text(l.t).font(.system(size: 13)).foregroundColor(p.muted).lineLimit(2)
      Spacer(minLength: 0)
      Text(l.inBlock ? "\(l.s)–\(l.be ?? l.e) · пара \(l.n ?? 1) из \(l.of ?? 1)" : "\(l.s)–\(l.e)")
        .font(.system(size: 12, weight: .medium)).foregroundColor(p.text).lineLimit(1)
    }
  }

  private func message(_ p: Pal, top: String?, big: String, sub: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if let top = top { label(top, p.muted) }
      Spacer(minLength: 0)
      Text(big)
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundColor(p.text)
        .lineLimit(1)
        .minimumScaleFactor(0.45)
      Spacer(minLength: 0)
      Text(sub).font(.system(size: 13)).foregroundColor(p.muted).lineLimit(2)
    }
  }
}

// MARK: - «Пара» на экране блокировки

struct RectView: View {
  let entry: DayEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch Sched.state(entry.snap, entry.date) {
      case .noData:
        Text("Капибара").font(.headline)
        Text("Открой приложение").font(.caption)
      case .free:
        Text("Пар нет").font(.headline)
        Text("сегодня и завтра").font(.caption)
      case let .now(l, m, _):
        Text(l.r.isEmpty ? "идёт" : "идёт · \(l.r)").font(.headline).widgetAccentable()
        Text(l.t).font(.caption).lineLimit(1)
        Text(l.inBlock ? "ещё \(m)’ · пара \(l.n ?? 1) из \(l.of ?? 1)" : "ещё \(m)’ до конца").font(.caption)
      case let .next(l, m, tomorrow):
        Text(l.r.isEmpty ? l.s : "\(l.s) · \(l.r)").font(.headline).widgetAccentable()
        Text(l.t).font(.caption).lineLimit(1)
        Text(Sched.nextLabel(l, m, tomorrow)).font(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .widgetBackground(Color.clear, padded: false)
  }
}

struct CircleView: View {
  let entry: DayEntry

  var body: some View {
    Group {
      switch Sched.state(entry.snap, entry.date) {
      case let .now(_, m, progress):
        Gauge(value: progress) {
          Text("идёт")
        } currentValueLabel: {
          Text("\(m)’").font(.system(size: 17, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
      case let .next(l, m, tomorrow):
        ZStack {
          AccessoryWidgetBackground()
          VStack(spacing: 0) {
            if !tomorrow && m < 100 {
              Text("через").font(.system(size: 10))
              Text("\(m)’").font(.system(size: 20, weight: .bold, design: .rounded))
            } else {
              Text(tomorrow ? "завтра" : "пара").font(.system(size: 10))
              Text(l.s).font(.system(size: 15, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            }
          }
        }
      case .free, .noData:
        ZStack {
          AccessoryWidgetBackground()
          Text("—").font(.system(size: 20, weight: .bold))
        }
      }
    }
    .widgetBackground(Color.clear, padded: false)
  }
}

struct LessonEntryView: View {
  let entry: DayEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .accessoryRectangular: RectView(entry: entry)
    case .accessoryCircular: CircleView(entry: entry)
    default: SmallView(entry: entry)
    }
  }
}

// MARK: - «Весь день»: большой

struct LargeView: View {
  let entry: DayEntry
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let p = Pal.of(scheme)
    let now = entry.date
    let shown = Sched.dayToShow(entry.snap, now)
    let dl = Sched.deadline(entry.snap, now)
    return VStack(alignment: .leading, spacing: 0) {
      if let shown = shown {
        Text(shown.tomorrow ? "ЗАВТРА · \(shown.day.h)" : shown.day.h)
          .font(.system(size: 12, weight: .bold))
          .tracking(0.8)
          .foregroundColor(p.muted)
          .lineLimit(1)
          .padding(.bottom, 6)
        if shown.day.l.isEmpty {
          Text("Пар нет — можно выдохнуть").font(.system(size: 15)).foregroundColor(p.text).padding(.top, 4)
        }
        ForEach(Array(Sched.rows(shown.day).prefix(8).enumerated()), id: \.offset) { _, l in
          let color = l.start <= now && now < l.end ? p.ok : (l.end <= now ? p.muted : p.text)
          HStack(spacing: 8) {
            Text(l.s).font(.system(size: 14, weight: .semibold)).monospacedDigit()
              .frame(width: 46, alignment: .leading)
            Text(l.t).font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 4)
            Text(l.r).font(.system(size: 14, weight: .semibold)).lineLimit(1)
          }
          .foregroundColor(color)
          .padding(.vertical, 5)
        }
      } else {
        Text("КАПИБАРА").font(.system(size: 12, weight: .bold)).tracking(0.8).foregroundColor(p.muted)
        Text("Открой приложение — здесь появятся пары")
          .font(.system(size: 15)).foregroundColor(p.text).padding(.top, 8)
      }
      Spacer(minLength: 0)
      if let dl = dl {
        HStack(spacing: 6) {
          Image(systemName: "flame.fill")
          Text("\(dl.t) · \(Sched.leftShort(now, dl.date))").lineLimit(1)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(p.danger)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetBackground(p.bg)
  }
}

// MARK: - Виджеты

struct LessonWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "KapibaraLesson", provider: Provider()) { entry in
      LessonEntryView(entry: entry)
    }
    .configurationDisplayName("Пара")
    .description("Через сколько следующая пара и где, во время пары — сколько до конца.")
    .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
  }
}

struct DayWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "KapibaraDay", provider: Provider()) { entry in
      LargeView(entry: entry)
    }
    .configurationDisplayName("Весь день")
    .description("Пары на день и горящий срок.")
    .supportedFamilies([.systemLarge])
  }
}

@main
struct KapibaraWidgets: WidgetBundle {
  var body: some Widget {
    LessonWidget()
    DayWidget()
  }
}
