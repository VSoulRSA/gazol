import 'dart:convert';

import 'package:http/http.dart' as http;

/// Decodes text responses using their declared charset, with UTF-8 as the
/// standards-based default for JSON and the app's HTML/text endpoints.
String decodeHttpResponseBody(http.Response response) {
  final contentType = response.headers['content-type'] ?? '';
  final charset = RegExp(
    r'charset\s*=\s*([^;\s]+)',
    caseSensitive: false,
  ).firstMatch(contentType)?.group(1)?.replaceAll('"', '').replaceAll("'", '');
  final encoding = charset == null ? utf8 : Encoding.getByName(charset) ?? utf8;
  return encoding.decode(response.bodyBytes);
}
