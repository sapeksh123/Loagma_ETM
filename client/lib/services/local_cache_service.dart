import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class LocalCacheService {
  static const String _boxName = 'api_cache';
  static Box<dynamic>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box ??= await Hive.openBox<dynamic>(_boxName);
  }

  static Future<Map<String, dynamic>?> getJsonMap(
    String key, {
    required Duration ttl,
  }) async {
    final value = await _readValue(key, ttl: ttl);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static Future<List<dynamic>?> getJsonList(
    String key, {
    required Duration ttl,
  }) async {
    final value = await _readValue(key, ttl: ttl);
    if (value is List<dynamic>) return value;
    if (value is List) return List<dynamic>.from(value);
    return null;
  }

  static Future<void> putJson(
    String key,
    Object value, {
    required Duration ttl,
  }) async {
    final box = await _ensureBox();
    final payload = jsonEncode({
      'expires_at': DateTime.now().add(ttl).millisecondsSinceEpoch,
      'value': value,
    });
    await box.put(key, payload);
  }

  static Future<void> invalidatePrefix(String prefix) async {
    final box = await _ensureBox();
    final keys = box.keys
        .where((k) => k is String && k.startsWith(prefix))
        .toList(growable: false);
    if (keys.isEmpty) return;
    await box.deleteAll(keys);
  }

  static Future<dynamic> _readValue(
    String key, {
    required Duration ttl,
  }) async {
    final box = await _ensureBox();
    final raw = box.get(key);
    if (raw is! String || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await box.delete(key);
        return null;
      }

      final payload = Map<String, dynamic>.from(decoded);
      final expiresAt = (payload['expires_at'] as num?)?.toInt();
      if (expiresAt == null ||
          expiresAt < DateTime.now().millisecondsSinceEpoch) {
        await box.delete(key);
        return null;
      }

      return payload['value'];
    } catch (_) {
      await box.delete(key);
      return null;
    }
  }

  static Future<Box<dynamic>> _ensureBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox<dynamic>(_boxName);
    }
    return _box!;
  }
}
