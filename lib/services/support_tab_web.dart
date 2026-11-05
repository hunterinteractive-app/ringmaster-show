// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

const supportTabKey = 'ringmaster.support.session.v1';
String? get savedSupportSession {
  try {
    return html.window.sessionStorage[supportTabKey];
  } catch (_) {
    return null;
  } // Ordinary sign-in also works with tab storage disabled.
}

bool restartSupportTab(String? id) {
  if (id == null) {
    html.window.sessionStorage.remove(supportTabKey);
  } else {
    html.window.sessionStorage[supportTabKey] = id;
  }
  html.window.location.assign(html.window.location.pathname ?? '/');
  return true;
}
