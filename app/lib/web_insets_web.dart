import 'dart:js_interop';

@JS('uibInsets')
external JSString? _insets();

String insets() {
  try {
    return _insets()?.toDart ?? '';
  } catch (_) {
    return '';
  }
}
