import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Cognitive Commerce (Swiggy MCP) -- connect/status/disconnect for the
/// Settings screen, plus confirm/dismiss for ActionCard. Every call here
/// is a thin wrapper over the commerce/swiggy_adapter.py-backed routes in
/// app.py; when SWIGGY_MCP_ENABLED is off server-side, status() reports
/// enabled:false and every other call 404s with a clear error, same
/// contract the React client relies on.
class CommerceService {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> status() async {
    final r = await _api.dio.get('/integrations/swiggy/status');
    return Map<String, dynamic>.from(r.data);
  }

  /// Opens the real Swiggy OAuth screen in the system browser. Fetches the
  /// authorize URL over an authenticated Dio request first (connect_url,
  /// not the plain /connect redirect React uses) because a system browser
  /// opened via url_launcher has no way to carry this app's Bearer token --
  /// see app.py's swiggy_connect_url for the full reasoning.
  Future<void> connect(String server) async {
    final r = await _api.dio.get('/integrations/swiggy/connect_url', queryParameters: {'server': server});
    final url = Uri.parse(r.data['url'] as String);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> disconnect(String server) {
    return _api.dio.post('/integrations/swiggy/disconnect', data: {'server': server});
  }

  /// menuItemId lets the user pick which of the (up to 3) shown items to
  /// order -- omit it to let the backend default to the top/first item.
  Future<Map<String, dynamic>> confirm(int actionId, {String? menuItemId}) async {
    final r = await _api.dio.post('/commerce/swiggy/confirm', data: {
      'action_id': actionId,
      if (menuItemId != null) 'menu_item_id': menuItemId,
    });
    return Map<String, dynamic>.from(r.data);
  }

  Future<void> dismiss(int actionId) {
    return _api.dio.post('/commerce/swiggy/dismiss', data: {'action_id': actionId});
  }

  /// Polled by ActionCard every ~10s while a UPI payment link is shown.
  Future<Map<String, dynamic>> paymentStatus(int paymentActionId) async {
    final r = await _api.dio.get('/commerce/swiggy/payment-status', queryParameters: {'payment_action_id': paymentActionId});
    return Map<String, dynamic>.from(r.data);
  }

  /// Live delivery status for an already-placed order -- polled at
  /// whatever pollingDuration Swiggy's own response suggests.
  Future<Map<String, dynamic>> trackOrder(int actionId) async {
    final r = await _api.dio.get('/commerce/swiggy/track-order', queryParameters: {'action_id': actionId});
    return Map<String, dynamic>.from(r.data);
  }
}
