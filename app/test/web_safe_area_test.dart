import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/web_safe_area.dart';

void main() {
  test('отступы из браузера: t,r,b,l', () {
    expect(parseInsets('47,0,34,0'), const EdgeInsets.fromLTRB(0, 47, 0, 34));
    expect(parseInsets('59.5, 1, 2, 3'), const EdgeInsets.fromLTRB(3, 59.5, 1, 2));
  });

  test('пусто или мусор — без отступов', () {
    expect(parseInsets(''), EdgeInsets.zero);
    expect(parseInsets('1,2,3'), EdgeInsets.zero);
    expect(parseInsets('a,b,c,d'), EdgeInsets.zero);
    expect(parseInsets('-5,0,0,0'), EdgeInsets.zero);
  });
}
