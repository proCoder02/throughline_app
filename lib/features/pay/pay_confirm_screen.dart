import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/local_cache.dart';
import '../../theme.dart';
import 'pay_api.dart';
import 'upi_apps.dart';
import 'upi_link.dart';

/// Shows who is being paid, takes the amount (unless the QR fixes it), then
/// opens the chosen UPI app pre-filled via a UPI intent link. The user
/// authorises with their PIN inside that app -- Throughline never sees or
/// handles the money.
///
/// Layout follows a single-primary-action pattern: payee (trust) at the
/// top, the amount as the focal point, one app picker with the last-used
/// app preselected, and one "Pay" button pinned in the thumb zone above
/// the keyboard.
///
/// When the user comes back we ask whether it went through and, if so, save
/// it as a Transaction (same POST /transactions as receipt screenshots).
/// We ask rather than trust a callback: url_launcher returns no result, and
/// UPI apps' intent responses can't be relied on as proof of payment anyway.
class PayConfirmScreen extends StatefulWidget {
  final UpiLink link;

  /// The promise this pays ("Send Ravi 500 for the tickets"), when opened
  /// from "You owe": its amount is prefilled and it's closed once paid.
  final OwedItem? owed;

  const PayConfirmScreen({super.key, required this.link, this.owed});

  @override
  State<PayConfirmScreen> createState() => _PayConfirmScreenState();
}

class _PayConfirmScreenState extends State<PayConfirmScreen> with WidgetsBindingObserver {
  /// Most UPI apps cap a single payment at ₹1,00,000 (some merchant
  /// categories allow more) -- above this we warn, we don't block.
  static const _upiLimit = 100000.0;
  static const _quickAmounts = [100, 200, 500, 1000];
  static final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late UpiApp _app;

  /// Set once a UPI app was launched; cleared after the "did it go through"
  /// question is answered.
  ({UpiApp app, double amount, String? note})? _pending;
  bool _leftApp = false;
  bool _asking = false;

  /// What Throughline remembers about this UPI ID (null until loaded, or if
  /// the server can't say -- paying works the same either way).
  PayeeMemory? _memory;

  UpiLink get _link => widget.link;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final fixed = _link.fixedAmount;
    if (fixed != null) {
      _amountController.text = fixed.toStringAsFixed(2);
    } else if (widget.owed?.amount != null) {
      _amountController.text = _plain(widget.owed!.amount!);
    }
    _loadMemory();
    final apps = UpiApp.forPlatform;
    String? last;
    try {
      last = LocalCache.instance.getLastUpiApp();
    } catch (_) {
      last = null;
    }
    _app = apps.firstWhere((a) => a.name == last, orElse: () => apps.first);
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _loadMemory() async {
    final m = await PayApi.instance.payee(_link.payeeVpa!, shownName: _link.payeeName);
    if (!mounted || m == null) return;
    setState(() => _memory = m);
  }

  Future<void> _nameThisPayee() async {
    final controller = TextEditingController(text: _memory?.label ?? '');
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Who is this?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Ramesh (milk)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (label == null || !mounted) return;
    try {
      await PayApi.instance.setLabel(_link.payeeVpa!, label);
      await _loadMemory();
    } catch (_) {
      _toast("Couldn't save the name. Check your connection.");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_pending == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftApp = true;
    } else if (state == AppLifecycleState.resumed && _leftApp) {
      _leftApp = false;
      _askOutcome();
    }
  }

  double? get _amount {
    final v = double.tryParse(_amountController.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  void _setQuickAmount(int v) {
    HapticFeedback.selectionClick();
    _amountController.text = v.toString();
    _amountController.selection = TextSelection.collapsed(offset: _amountController.text.length);
    setState(() {});
  }

  Future<void> _pay() async {
    final amount = _amount;
    if (amount == null) return;
    final app = _app;
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    final uri = _link.build(scheme: app.scheme, amount: amount, note: note);
    _pending = (app: app, amount: amount, note: note ?? _link.note);
    _leftApp = false;
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      _pending = null;
      _toast("Couldn't open ${app.name}. Is it installed? Pick another app.");
      return;
    }
    try {
      await LocalCache.instance.setLastUpiApp(app.name);
    } catch (_) {}
  }

  Future<void> _askOutcome() async {
    final pending = _pending;
    if (pending == null || _asking || !mounted) return;
    _asking = true;
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.dmBubbleIn,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _OutcomeSheet(
        amount: _inr.format(pending.amount),
        payee: _link.displayName,
        app: pending.app.name,
      ),
    );
    _asking = false;
    _pending = null;
    if (!mounted || paid != true) return;

    try {
      // /pay/record remembers the payee and closes the promise; it falls back
      // to the original POST /transactions on a server without it.
      final closed = await PayApi.instance.record(
        vpa: _link.payeeVpa!,
        payeeName: _link.displayName,
        amount: pending.amount,
        app: pending.app.name,
        note: pending.note,
        taskId: widget.owed?.taskId,
      );
      if (!mounted) return;
      _toast(closed != null ? 'Paid. Promise closed: $closed' : 'Saved to your spending');
      Navigator.of(context).pop();
    } catch (_) {
      _toast("Payment noted, but it couldn't be saved. Check your connection.");
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final fixed = _link.fixedAmount != null;
    final amount = _amount;
    return Scaffold(
      backgroundColor: AppColors.dmGradient[1],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.dmText,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Pay'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  _payeeCard(),
                  if (widget.owed != null) ...[
                    const SizedBox(height: 12),
                    _owedCard(widget.owed!),
                  ],
                  if (_memory != null) ...[
                    const SizedBox(height: 12),
                    _memoryCard(_memory!),
                  ],
                  const SizedBox(height: 28),
                  _amountField(fixed),
                  const SizedBox(height: 4),
                  _amountHint(amount, fixed),
                  if (!fixed) ...[
                    const SizedBox(height: 16),
                    _quickAmountChips(),
                  ],
                  const SizedBox(height: 20),
                  _noteField(),
                  const SizedBox(height: 28),
                  _sectionLabel('Pay with'),
                  const SizedBox(height: 10),
                  _appPicker(),
                ],
              ),
            ),
            _payBar(amount),
          ],
        ),
      ),
    );
  }

  // -- Payee: who you're paying, first and clearest (trust before action).
  Widget _payeeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.dmAccent.withValues(alpha: 0.18),
                child: Text(
                  _link.displayName.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.dmAccentDark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_link.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.dmText)),
                    const SizedBox(height: 2),
                    Text(_link.payeeVpa!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft)),
                  ],
                ),
              ),
              if (_link.isMerchant) _badge(Icons.storefront_outlined, 'Business'),
            ],
          ),
          if (!_link.isMerchant) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dmPillFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.dmTextSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Personal UPI ID. Some apps decline these when opened from another app. If that happens, pay from the UPI app directly.',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.dmTextSoft),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The promise being paid, and where it was made.
  Widget _owedCard(OwedItem o) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dmAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmAccent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.handshake_outlined, size: 20, color: AppColors.dmAccentDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paying what you promised', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
                const SizedBox(height: 2),
                Text(o.text, style: TextStyle(color: AppColors.dmText)),
                if (o.sourceTitle != null)
                  Text('From: ${o.sourceTitle}', style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
                const SizedBox(height: 2),
                Text("It's closed once you confirm the payment.",
                    style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What Throughline remembers about this UPI ID, plus anything to check.
  Widget _memoryCard(PayeeMemory m) {
    final lines = <String>[];
    if (m.timesPaid > 0) {
      final last = m.lastAt == null ? '' : ' on ${DateFormat('d MMM').format(m.lastAt!)}';
      lines.add('Paid ${m.timesPaid == 1 ? 'once' : '${m.timesPaid} times'} \u00b7 last ${_inr.format(m.lastAmount ?? 0)}$last');
      if (m.recentNotes.isNotEmpty) lines.add('For: ${m.recentNotes.join(', ')}');
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 18, color: AppColors.dmTextSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.label ?? (m.newPayee ? 'First time paying them' : 'You know this payee'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText),
                ),
              ),
              TextButton(
                onPressed: _nameThisPayee,
                child: Text(m.label == null ? 'Name them' : 'Rename'),
              ),
            ],
          ),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft)),
            ),
          for (final w in m.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.dmText))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.dmPillFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.dmText),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.dmText)),
        ],
      ),
    );
  }

  // -- Amount: the focal point of the screen.
  Widget _amountField(bool fixed) {
    final style = appHeadlineFont(color: AppColors.dmText, fontSize: 44);
    return TextField(
      controller: _amountController,
      readOnly: fixed,
      autofocus: !fixed,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}(\.\d{0,2})?'))],
      textAlign: TextAlign.center,
      cursorColor: AppColors.dmAccent,
      style: style,
      decoration: InputDecoration(
        prefixText: '₹ ',
        prefixStyle: style.copyWith(color: AppColors.dmTextSoft),
        hintText: '0',
        hintStyle: style.copyWith(color: AppColors.dmTextSoft.withValues(alpha: 0.5)),
        border: InputBorder.none,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  /// One line under the amount: readable grouping (₹1,00,000.00), the
  /// fixed-by-QR notice, or a limit warning -- never more than one at once.
  Widget _amountHint(double? amount, bool fixed) {
    String? text;
    var warn = false;
    if (amount != null && amount > _upiLimit) {
      text = 'Above ₹1,00,000. Most UPI apps will decline this.';
      warn = true;
    } else if (fixed) {
      text = 'Amount set by the QR code';
    } else if (amount != null && amount >= 1000) {
      text = _inr.format(amount);
    }
    return SizedBox(
      height: 20,
      child: text == null
          ? null
          : Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: warn ? FontWeight.w600 : FontWeight.w400,
                color: warn ? AppColors.danger : AppColors.dmTextSoft,
              ),
            ),
    );
  }

  Widget _quickAmountChips() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_memory?.usualAmount != null)
          ActionChip(
            avatar: const Icon(Icons.replay, size: 16, color: AppColors.dmAccentDark),
            label: Text('${_inr.format(_memory!.usualAmount!).replaceAll('.00', '')} usual'),
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText),
            backgroundColor: AppColors.dmAccent.withValues(alpha: 0.14),
            side: BorderSide(color: AppColors.dmAccent.withValues(alpha: 0.5)),
            shape: const StadiumBorder(),
            onPressed: () {
              HapticFeedback.selectionClick();
              _amountController.text = _plain(_memory!.usualAmount!);
              _amountController.selection = TextSelection.collapsed(offset: _amountController.text.length);
              setState(() {});
            },
          ),
        for (final v in _quickAmounts)
          ActionChip(
            label: Text('₹$v'),
            labelStyle: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dmText),
            backgroundColor: AppColors.dmPillFill,
            side: BorderSide(color: AppColors.dmBubbleBorder),
            shape: const StadiumBorder(),
            onPressed: () => _setQuickAmount(v),
          ),
      ],
    );
  }

  Widget _noteField() {
    if (_link.note != null) {
      return Text('Note: ${_link.note}', textAlign: TextAlign.center, style: TextStyle(color: AppColors.dmTextSoft));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      child: TextField(
        controller: _noteController,
        maxLength: 50,
        style: TextStyle(color: AppColors.dmText),
        cursorColor: AppColors.dmAccent,
        decoration: InputDecoration(
          icon: Icon(Icons.edit_note, color: AppColors.dmTextSoft),
          hintText: _memory?.lastNote != null ? "What's this for? (last: ${_memory!.lastNote})" : "What's this for? (optional)",
          hintStyle: TextStyle(color: AppColors.dmTextSoft),
          border: InputBorder.none,
          counterText: '',
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: AppColors.dmTextSoft),
      );

  // -- App picker: one selection, not one button per app (Hick's law).
  Widget _appPicker() {
    return Column(
      children: [
        for (final app in UpiApp.forPlatform)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AppOption(
              app: app,
              selected: app == _app,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _app = app);
              },
            ),
          ),
      ],
    );
  }

  // -- Single primary action, pinned in the thumb zone (Fitts's law).
  Widget _payBar(double? amount) {
    final enabled = amount != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        border: Border(top: BorderSide(color: AppColors.dmBubbleBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dmAccent,
                // Dark text on the amber: ~5.9:1 contrast (white was ~2.6:1,
                // below WCAG AA).
                foregroundColor: const Color(0xFF2B211A),
                disabledBackgroundColor: AppColors.dmPillFill,
                disabledForegroundColor: AppColors.dmTextSoft,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: enabled ? _pay : null,
              child: Text(
                enabled ? 'Pay ${_inr.format(amount)} with ${_app.name}' : 'Enter an amount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 13, color: AppColors.dmTextSoft),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  "You'll enter your UPI PIN in ${_app.name}. Throughline never sees it.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.dmTextSoft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppOption extends StatelessWidget {
  final UpiApp app;
  final bool selected;
  final VoidCallback onTap;

  const _AppOption({required this.app, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Pay with ${app.name}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.dmBubbleIn,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.dmAccent : AppColors.dmBubbleBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.dmPillFill,
                child: app == UpiApp.other
                    ? Icon(Icons.apps, size: 18, color: AppColors.dmText)
                    : Text(app.name[0],
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(app.name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.dmText)),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.dmAccent : AppColors.dmTextSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutcomeSheet extends StatelessWidget {
  final String amount;
  final String payee;
  final String app;

  const _OutcomeSheet({required this.amount, required this.payee, required this.app});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 36, color: AppColors.dmAccent),
            const SizedBox(height: 12),
            Text('Did the payment go through?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.dmText)),
            const SizedBox(height: 6),
            Text('$amount to $payee via $app',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.dmTextSoft)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: AppColors.dmText,
                      side: BorderSide(color: AppColors.dmBubbleBorder, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No, it failed'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppColors.dmAccent,
                      foregroundColor: const Color(0xFF2B211A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Yes, paid', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
