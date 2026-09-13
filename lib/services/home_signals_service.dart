import '../motion/motion_profile.dart';
import 'api_client.dart';

/// Fetches the two plain server-derived signals the home screen's motion
/// decision (see motion_profile.dart / ADAPTIVE_HOME_ANIMATION_PLAN.md)
/// depends on. No local cache of its own: a failed/slow fetch just means
/// the caller keeps using MotionProfile.balanced (the always-safe default)
/// for this load -- there is nothing to fall back to because the fallback
/// *is* the current, already-correct default behavior.
class HomeSignalsService {
  final _api = ApiClient.instance;

  Future<({MoodBucket? mood, ChatTone? chatTone})> fetch() async {
    final r = await _api.dio.get('/me/home-signals');
    return (
      mood: moodBucketFromString(r.data['mood_bucket'] as String?),
      chatTone: chatToneFromString(r.data['chat_tone'] as String?),
    );
  }

  /// Called once from GlobalChatScreen when it closes after an actual
  /// exchange happened -- best-effort/fire-and-forget from the caller's
  /// point of view, see that screen's dispose().
  Future<void> wrapUpGlobalChat() => _api.dio.post('/chat/global/wrap-up');
}
