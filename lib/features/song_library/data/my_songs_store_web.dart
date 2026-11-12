import 'dart:js_interop';

import 'package:web/web.dart' as web;

String? read(String key) => web.window.localStorage.getItem(key);

void write(String key, String value) =>
    web.window.localStorage.setItem(key, value);

/// Calls [changed] when the Studio, in another tab, changes the storage,
/// and when the app comes back into view.
void onChange(void Function() changed) {
  web.window.addEventListener('storage', ((web.Event _) => changed()).toJS);
  web.window.addEventListener('focus', ((web.Event _) => changed()).toJS);
}
