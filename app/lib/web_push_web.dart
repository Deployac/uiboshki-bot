import 'dart:js_interop';

@JS('uibPush.state')
external JSPromise<JSString> _state();

@JS('uibPush.enable')
external JSPromise<JSString> _enable(JSString vapidKey);

@JS('uibPush.disable')
external JSPromise<JSString> _disable();

Future<String> state() async {
  try {
    return (await _state().toDart).toDart;
  } catch (_) {
    return 'unsupported';
  }
}

Future<String> enable(String vapidKey) async => (await _enable(vapidKey.toJS).toDart).toDart;

Future<String> disable() async => (await _disable().toDart).toDart;
