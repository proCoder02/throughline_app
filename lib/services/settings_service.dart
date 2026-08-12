import 'api_client.dart';
import 'local_cache.dart';

class SettingsService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  Map<String, dynamic>? getCached() => _cache.getSettings();

  Future<Map<String, dynamic>> get() async {
    final r = await _api.dio.get('/settings');
    final settings = Map<String, dynamic>.from(r.data);
    await _cache.setSettings(settings);
    return settings;
  }

  Future<void> update(String personalization) {
    return _api.dio.post('/settings', data: {'personalization': personalization});
  }

  Map<String, dynamic>? getCachedNudgeSettings() => _cache.getNudgeSettings();

  Future<Map<String, dynamic>> getNudgeSettings() async {
    final r = await _api.dio.get('/settings/nudges');
    final settings = Map<String, dynamic>.from(r.data);
    await _cache.setNudgeSettings(settings);
    return settings;
  }

  Future<Map<String, dynamic>> updateNudgeSettings({
    bool? nudgesEnabled,
    bool? cognitiveIntelligenceEnabled,
    bool? taskReminderNotificationsEnabled,
    bool? tagsQuestionsEnabled,
  }) async {
    final r = await _api.dio.post('/settings/nudges', data: {
      if (nudgesEnabled != null) 'nudges_enabled': nudgesEnabled,
      if (cognitiveIntelligenceEnabled != null) 'cognitive_intelligence_enabled': cognitiveIntelligenceEnabled,
      if (taskReminderNotificationsEnabled != null)
        'task_reminder_notifications_enabled': taskReminderNotificationsEnabled,
      if (tagsQuestionsEnabled != null) 'tags_questions_enabled': tagsQuestionsEnabled,
    });
    final settings = Map<String, dynamic>.from(r.data);
    await _cache.setNudgeSettings(settings);
    return settings;
  }

  /// Master toggle -- sets nudges/cognitive-intelligence/task-reminder/
  /// tags-questions together and is the ONLY one of these calls that
  /// triggers a "Setting updated" notification server-side (see
  /// app.py's update_nudge_settings: individual field updates above stay
  /// silent on purpose).
  Future<Map<String, dynamic>> updateSmartFeatures(bool enabled) async {
    final r = await _api.dio.post('/settings/nudges', data: {'smart_features_enabled': enabled});
    final settings = Map<String, dynamic>.from(r.data);
    await _cache.setNudgeSettings(settings);
    return settings;
  }
}
