// Ответы ИИ и конспекты приходят разметкой Telegram (b, i, u, s, code, pre,
// a, blockquote, перевод строки). Здесь — разбор в TextSpan без WebView.
// Цель API на потом — блоки JSON без HTML (PLAN.md, «Своё приложение»).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _entities = {'&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ', '&amp;': '&'};

String unescape(String s) {
  var out = s;
  for (final e in _entities.entries) {
    out = out.replaceAll(e.key, e.value);
  }
  return out;
}

/// Ссылки ИИ на источники «[1]», «[2]» в тексте ответа.
final citeRe = RegExp(r'\[(\d{1,2})\]');

/// Текст кусками: «[n]» — через [cite] (кнопка к источнику), остальное —
/// обычным текстом. cite вернул null — «[n]» остаётся как есть.
List<InlineSpan> citeSpans(String text, TextStyle style, InlineSpan? Function(int n) cite) {
  final out = <InlineSpan>[];
  var pos = 0;
  for (final m in citeRe.allMatches(text)) {
    final span = cite(int.parse(m.group(1)!));
    if (span == null) continue;
    if (m.start > pos) out.add(TextSpan(text: text.substring(pos, m.start), style: style));
    out.add(span);
    pos = m.end;
  }
  if (pos < text.length) out.add(TextSpan(text: text.substring(pos), style: style));
  return out;
}

/// HTML Telegram → один TextSpan. Незнакомые теги пропускаются, текст остаётся.
/// cite — «[1]» в тексте нажимается (помощник: страница лекции-источника).
TextSpan tgHtml(String html, TextStyle base, {Color? link, Color? codeBg, InlineSpan? Function(int n)? cite}) {
  final spans = <InlineSpan>[];
  final stack = <String>[];
  final hrefs = <String>[];
  final tag = RegExp(r'<(/?)([a-zA-Z0-9-]+)([^>]*)>');
  var pos = 0;

  TextStyle styleNow() {
    var st = base;
    for (final t in stack) {
      switch (t) {
        case 'b' || 'strong':
          st = st.copyWith(fontWeight: FontWeight.w700);
        case 'i' || 'em':
          st = st.copyWith(fontStyle: FontStyle.italic);
        case 'u' || 'ins':
          st = st.copyWith(decoration: TextDecoration.underline);
        case 's' || 'strike' || 'del':
          st = st.copyWith(decoration: TextDecoration.lineThrough);
        case 'code' || 'pre':
          st = st.copyWith(fontFamily: 'monospace', backgroundColor: codeBg, fontSize: (base.fontSize ?? 15) * 0.92);
        case 'blockquote':
          st = st.copyWith(color: base.color?.withValues(alpha: 0.75), fontStyle: FontStyle.italic);
        case 'a':
          st = st.copyWith(color: link, decoration: TextDecoration.underline, decorationColor: link);
        case 'tg-spoiler' || 'span':
          break;
      }
    }
    return st;
  }

  void text(String raw) {
    if (raw.isEmpty) return;
    final st = styleNow();
    final href = stack.contains('a') && hrefs.isNotEmpty ? hrefs.last : null;
    if (cite != null && href == null && !stack.contains('code') && !stack.contains('pre')) {
      spans.addAll(citeSpans(unescape(raw), st, cite));
      return;
    }
    spans.add(
      TextSpan(
        text: unescape(raw),
        style: st,
        recognizer: href == null
            ? null
            : (TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication)),
      ),
    );
  }

  for (final m in tag.allMatches(html)) {
    text(html.substring(pos, m.start));
    pos = m.end;
    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();
    if (name == 'br') {
      text('\n');
      continue;
    }
    if (closing) {
      final i = stack.lastIndexOf(name);
      if (i >= 0) stack.removeRange(i, stack.length);
      if (name == 'a' && hrefs.isNotEmpty) hrefs.removeLast();
      if (name == 'blockquote' || name == 'pre') text('\n');
    } else {
      stack.add(name);
      if (name == 'a') {
        final h = RegExp(r'''href\s*=\s*["']([^"']*)["']''').firstMatch(m.group(3) ?? '');
        hrefs.add(unescape(h?.group(1) ?? ''));
      }
    }
  }
  text(html.substring(pos));
  return TextSpan(style: base, children: spans);
}
