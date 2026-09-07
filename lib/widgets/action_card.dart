import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/commerce_service.dart';
import '../theme.dart';

const _paymentPollInterval = Duration(seconds: 10); // matches Swiggy's own docs' polling guidance (no faster than every 10s)
const _defaultTrackPollInterval = Duration(seconds: 30); // fallback when Swiggy's own pollingDuration hint is missing/unparseable
const _maxTrackPolls = 60; // ~30min+ at the default interval -- stop background polling eventually even if the order never reaches a state we recognize as final

/// Cognitive Commerce (Swiggy MCP): the "want me to order this?" card a
/// global-chat reply carries as ChatMessage.actionCard. Purely
/// presentational plus its own tiny confirm/dismiss/poll network calls --
/// the parent screen doesn't need to know the outcome, this widget owns its
/// own resolved state once a button is tapped. Never calls anything on
/// build for the normal pending card: nothing happens until the user taps
/// a button, matching the "recommend -> ask -> act" rule this feature is
/// built around. The one exception is a card already in tracking mode
/// (see swiggy_adapter.py's build_tracking_context, for "where is my
/// order" messages) -- that one starts polling immediately since there's
/// nothing to confirm.
class ActionCard extends StatefulWidget {
  final Map<String, dynamic> card;

  const ActionCard({super.key, required this.card});

  @override
  State<ActionCard> createState() => _ActionCardState();
}

enum _CardState { pending, busy, awaitingPayment, tracking, done }

class _ActionCardState extends State<ActionCard> {
  final _service = CommerceService();
  late _CardState _state;
  String? _result;
  String? _selectedMenuItemId;
  String? _paymentLink;
  Map<String, dynamic>? _tracking;
  Timer? _pollTimer;
  int _trackPollCount = 0;

  bool get _isTrackingCard => widget.card['mode'] == 'tracking';

  @override
  void initState() {
    super.initState();
    _state = _isTrackingCard ? _CardState.tracking : _CardState.pending;
    if (_isTrackingCard) {
      _tracking = widget.card;
    } else {
      final items = (widget.card['items'] as List?) ?? const [];
      // Only Food items carry their own menu_item_id (Instamart/Dineout's
      // fallback path doesn't) -- default to the first one so "Order
      // selected" works immediately without forcing an explicit tap first.
      for (final item in items) {
        final id = (item as Map)['menu_item_id'] as String?;
        if (id != null) {
          _selectedMenuItemId = id;
          break;
        }
      }
    }
    if (_isTrackingCard) {
      _trackOrder(widget.card['id'] as int, widget.card['external_order_id'] as String?);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _trackOrder(int actionId, String? externalOrderId) {
    _trackPollCount = 0;
    Future<void> poll() async {
      if (_trackPollCount >= _maxTrackPolls) {
        _pollTimer?.cancel();
        return;
      }
      _trackPollCount += 1;
      try {
        final data = await _service.trackOrder(actionId);
        if (!mounted) return;
        setState(() {
          _tracking = {...data, 'external_order_id': externalOrderId};
          _state = _CardState.tracking;
        });
        final seconds = double.tryParse((data['polling_duration'] ?? '').toString().replaceAll(RegExp('[^0-9.]'), ''));
        final next = seconds != null ? Duration(milliseconds: (seconds * 1000).round()) : _defaultTrackPollInterval;
        _pollTimer?.cancel();
        _pollTimer = Timer(next, poll);
      } catch (_) {
        _pollTimer?.cancel();
      }
    }

    setState(() => _state = _CardState.tracking);
    poll();
  }

  void _pollPayment(int paymentActionId) {
    _pollTimer = Timer.periodic(_paymentPollInterval, (_) async {
      try {
        final data = await _service.paymentStatus(paymentActionId);
        if (data['status'] == 'order_placed') {
          _pollTimer?.cancel();
          _trackOrder(data['action_id'] as int, data['external_order_id'] as String?);
        } else if (data['status'] == 'order_failed') {
          _finish('Payment did not go through -- order was not placed.');
        }
        // 'awaiting_payment' -- keep polling, no state change
      } catch (e) {
        _finish('Could not check payment status.');
      }
    });
  }

  void _finish(String text) {
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _result = text;
      _state = _CardState.done;
    });
  }

  Future<void> _confirm() async {
    setState(() => _state = _CardState.busy);
    try {
      final data = await _service.confirm(widget.card['id'] as int, menuItemId: _selectedMenuItemId);
      if (data['status'] == 'awaiting_payment') {
        setState(() {
          _paymentLink = data['payment_link'] as String?;
          _state = _CardState.awaitingPayment;
        });
        _pollPayment(data['payment_action_id'] as int);
        return;
      }
      _trackOrder(data['action_id'] as int, data['external_order_id'] as String?);
    } catch (e) {
      _finish('Order could not be placed.');
    }
  }

  Future<void> _dismiss() async {
    setState(() => _state = _CardState.busy);
    try {
      await _service.dismiss(widget.card['id'] as int);
    } catch (_) {
      // dismiss failing silently is fine -- worst case the card just stays
      // shown; it can never accidentally place an order either way
    } finally {
      _finish('Okay, not ordering.');
    }
  }

  Future<void> _openPaymentLink() async {
    if (_paymentLink == null) return;
    await launchUrl(Uri.parse(_paymentLink!), mode: LaunchMode.externalApplication);
  }

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
      );

  @override
  Widget build(BuildContext context) {
    if (_state == _CardState.tracking) {
      final pct = int.tryParse((_tracking?['progress_percentage'] ?? '').toString());
      final orderId = _tracking?['external_order_id'];
      return _card(children: [
        Text(
          'Order${orderId != null ? ' #$orderId' : ''} placed and being tracked live.',
          style: TextStyle(fontSize: 12, color: AppColors.textSoft),
        ),
        const SizedBox(height: 4),
        Text(_tracking?['title'] as String? ?? 'Order placed', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        if ((_tracking?['subtitle'] as String?)?.isNotEmpty == true)
          Text(_tracking!['subtitle'] as String, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        if ((_tracking?['eta_text'] as String?)?.isNotEmpty == true)
          Text('ETA: ${_tracking!['eta_text']}', style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        if (pct != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 6, backgroundColor: AppColors.border),
          ),
        ],
      ]);
    }

    if (_state == _CardState.done) {
      return _card(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.restaurant, size: 16),
          const SizedBox(width: 8),
          Flexible(child: Text(_result ?? '', style: TextStyle(fontSize: 13.5, color: AppColors.textSoft))),
        ]),
      ]);
    }

    if (_state == _CardState.awaitingPayment) {
      // Swiggy's place_food_order response carries no QR image at all --
      // the payment_link (bridgeUrl) is a real https:// page Swiggy hosts
      // itself, with whatever real QR/UPI UI it renders.
      return _card(children: [
        Text("Pay to complete the order -- it's placed the moment payment completes.",
            style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        const SizedBox(height: 8),
        if (_paymentLink != null)
          ElevatedButton(onPressed: _openPaymentLink, child: const Text('Open payment page'))
        else
          Text('No payment link was returned -- check the backend logs.', style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        const SizedBox(height: 8),
        Text('Waiting for payment...', style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
      ]);
    }

    final items = (widget.card['items'] as List?) ?? const [];
    final need = widget.card['need'] as String? ?? '';
    final selectable = items.any((item) => (item as Map)['menu_item_id'] != null);

    return _card(children: [
      if (need.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(need, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        ),
      ...items.map((item) {
        final menuItemId = (item as Map)['menu_item_id'] as String?;
        if (menuItemId == null) {
          // Instamart/Dineout fallback path -- no per-item id to select,
          // same plain-line rendering as before.
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('•  ${item['label']}', style: const TextStyle(fontSize: 13.5)),
          );
        }
        return InkWell(
          onTap: () => setState(() => _selectedMenuItemId = menuItemId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Radio<String>(
                  value: menuItemId,
                  groupValue: _selectedMenuItemId,
                  onChanged: (v) => setState(() => _selectedMenuItemId = v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(child: Text(item['label'] as String, style: const TextStyle(fontSize: 13.5))),
              ],
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _state == _CardState.busy || (selectable && _selectedMenuItemId == null) ? null : _confirm,
              icon: const Icon(Icons.restaurant, size: 16),
              label: Text(selectable ? 'Order selected' : 'Order this'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: _state == _CardState.busy ? null : _dismiss,
              child: const Text('Not hungry'),
            ),
          ),
        ],
      ),
    ]);
  }
}
