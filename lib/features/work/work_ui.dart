import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import 'work_api.dart';
import 'work_glass.dart';

/// Shared pieces for the Work screens, in the app's warm palette.

/// Secondary text colour with enough contrast (WCAG AA, 4.5:1) on the warm
/// gradient in both themes -- the shared dmTextSoft is lighter than that.
Color get workSoftText => isAppDarkMode ? const Color(0xFFB3A698) : const Color(0xFF6F6255);

String fmtDay(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso.length == 10 ? '${iso}T00:00:00' : iso)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  if (diff == -1) return 'yesterday';
  return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM y').format(d);
}

String fmtTime(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat.jm().format(d);
  return '${DateFormat('d MMM').format(d)}, ${DateFormat.jm().format(d)}';
}

void showWorkSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? AppColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Warm-gradient page with a transparent app bar -- the same frame every
/// main screen in the app uses.
class WorkPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final Widget? bottomBar;
  final Widget? fab;

  const WorkPage({super.key, required this.title, required this.body, this.actions, this.leading, this.bottom, this.bottomBar, this.fab});

  @override
  Widget build(BuildContext context) {
    return WorkBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.dmText),
          titleTextStyle: appHeadlineFont(color: AppColors.dmText, fontSize: 19),
          leading: leading,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: actions,
          bottom: bottom,
        ),
        body: body,
        bottomNavigationBar: bottomBar,
        floatingActionButton: fab,
      ),
    );
  }
}

class WorkCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? edge;

  const WorkCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.edge});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Frosted(onTap: onTap, padding: padding, accent: edge, child: child),
      );
}

/// Bottom padding for a scrolling list: room for the floating Work bar
/// (the shell reports it as bottom padding) plus normal breathing space.
double listEnd(BuildContext context, [double extra = 24]) => MediaQuery.paddingOf(context).bottom + extra;

class SectionTitle extends StatelessWidget {
  final String text;
  final int? count;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(children: [
        Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dmText)),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: AppColors.dmAccent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dmAccentDark)),
          ),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

const statusLabel = {
  'requested': 'Requested',
  'detected': 'To confirm',
  'open': 'Open',
  'overdue': 'Overdue',
  'done': 'Done',
  'dropped': 'Dropped',
  'declined': 'Declined',
};

Color statusColor(String? s) => switch (s) {
      'overdue' => AppColors.danger,
      'detected' || 'requested' => const Color(0xFF8E6BD9),
      'done' => const Color(0xFF2E9D6A),
      'dropped' || 'declined' => AppColors.dmTextSoft,
      _ => AppColors.dmAccent,
    };

class StatusChip extends StatelessWidget {
  final String? status;
  final bool atRisk;
  const StatusChip(this.status, {super.key, this.atRisk = false});

  Widget _chip(String text, Color c) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      );

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Status: ${statusLabel[status] ?? status ?? ''}${atRisk ? ', at risk' : ''}',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _chip(statusLabel[status] ?? (status ?? ''), statusColor(status)),
          if (atRisk) _chip('At risk', AppColors.danger),
        ]),
      );
}

class Muted extends StatelessWidget {
  final String text;
  final double size;
  final int? maxLines;
  const Muted(this.text, {super.key, this.size = 12.5, this.maxLines});

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: TextStyle(fontSize: size, color: workSoftText, height: 1.35));
}

class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  const EmptyNote({super.key, required this.icon, required this.title, this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icon, size: 40, color: AppColors.dmTextSoft),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dmText)),
          if (text != null) ...[const SizedBox(height: 6), Muted(text!, size: 13.5)],
        ]),
      );
}

/// Cache-first loading for a screen: paints the saved copy instantly, then
/// refreshes from the server; pull down to refresh. Shows an error only
/// when there's nothing saved to show.
class CachedLoad extends StatefulWidget {
  final String? cacheKey;
  final Future<dynamic> Function() fetch;
  final Widget Function(BuildContext context, dynamic data, Future<void> Function() reload) builder;

  const CachedLoad({super.key, required this.cacheKey, required this.fetch, required this.builder});

  @override
  State<CachedLoad> createState() => CachedLoadState();
}

class CachedLoadState extends State<CachedLoad> {
  dynamic _data;
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (widget.cacheKey != null) {
      final c = await WorkApi.instance.cached(widget.cacheKey!);
      if (c != null && mounted && _data == null) setState(() => _data = c);
    }
    await reload();
  }

  Future<void> reload() async {
    try {
      final d = await widget.fetch();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
          _offline = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = workError(e);
          _offline = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null && _error == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_data == null) {
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [EmptyNote(icon: Icons.cloud_off_outlined, title: "Couldn't load this", text: _error)]),
      );
    }
    return Column(children: [
      if (_offline)
        Container(
          width: double.infinity,
          color: AppColors.dmAccent.withValues(alpha: 0.15),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text('Showing saved copy. ${_error ?? ''}', style: TextStyle(fontSize: 12, color: AppColors.dmText)),
        ),
      Expanded(child: RefreshIndicator(onRefresh: reload, child: widget.builder(context, _data, reload))),
    ]);
  }
}

/// A one-line text prompt in a dialog (decline reason, drop reason, update).
Future<String?> askText(BuildContext context, {required String title, String? hint, String action = 'Save', int maxLines = 3}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: maxLines,
        minLines: 1,
        maxLength: 1000,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final t = c.text.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
          child: Text(action),
        ),
      ],
    ),
  );
}
