// language: dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TagStorage {
  static const _key = 'saved_tags';

  static Future<Map<String, String>> getSavedTags() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    if (jsonString != null) {
      Map data = json.decode(jsonString);
      return data.map((key, value) => MapEntry(key.toString(), value.toString()));
    }
    return {};
  }

  static Future<void> saveTag(String deviceId, String tagName) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getSavedTags();
    current[deviceId] = tagName;
    await prefs.setString(_key, json.encode(current));
  }
}