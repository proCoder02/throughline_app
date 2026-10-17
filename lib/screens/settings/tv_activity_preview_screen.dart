import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/tv_activity.dart';
import '../../services/tv_activity_service.dart';
import '../../theme.dart';

/// TV activity preview -- reads GET /tv/activity (raw sessions synced by the
/// Smart TV companion app) and GET /tv/activity/correlate (sessions matched
/// against this user's conversations/tasks/mood_logs by time proximity).
/// Settings -> Experimental sandbox, same convention as
/// heart_rate_preview_screen.dart. This app has no TV of its own to grant
/// permission on -- see throughline_smart_tv's own copy of this screen for
/// the permission-banner variant.
class TvActivityPreviewScreen extends StatefulWidget {
  const TvActivityPreviewScreen({super.key});

  @override
  State<TvActivityPreviewScreen> createState() => _TvActivityPreviewScreenState();
}

class _TvActivityPreviewScreenState extends State<TvActivityPreviewScreen> {
  final _service = TvActivityService();
  List<TvActivitySession>? _sessions;
  List<TvActivityCorrelation>? _correlations;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([_service.sessions(), _service.correlate()]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<TvActivitySession>;
        _correlations = results[1] as List<TvActivityCorrelation>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.dmGradient,
      )),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.dmText),
          titleTextStyle: appHeadlineFont(color: AppColors.dmText, fontSize: 18),
          title: const Text('TV Activity'),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: AppColors.dmTextSoft, size: 32),
              const SizedBox(height: 10),
              Text('Could not load TV activity data.', style: TextStyle(color: AppColors.dmTextSoft)),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_sessions == null || _correlations == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No TV activity synced yet -- set up the Smart TV companion app and grant it notification access.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.dmTextSoft),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text('CORRELATED WITH YOUR DAY', style: TextStyle(
            fontSize: 10.5, letterSpacing: 2, color: AppColors.dmAccent, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 8),
          if (_correlations!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No overlap yet -- nothing matched within 15 minutes of something you watched.',
                  style: TextStyle(color: AppColors.dmTextSoft, fontSize: 12.5)),
            )
          else
            ..._correlations!.map((c) => _CorrelationCard(correlation: c)),
          const SizedBox(height: 20),
          const Text('SYNCED SESSIONS', style: TextStyle(
            fontSize: 10.5, letterSpacing: 2, color: AppColors.dmAccent, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 8),
          ..._sessions!.map((s) => _SessionTile(session: s)),
        ],
      ),
    );
  }
}

class _CorrelationCard extends StatelessWidget {
  const _CorrelationCard({required this.correlation});
  final TvActivityCorrelation correlation;

  IconData get _icon => switch (correlation.type) {
        'conversation' => Icons.mic_none_rounded,
        'task' => Icons.check_circle_outline_rounded,
        'mood' => Icons.mood_rounded,
        _ => Icons.tv_outlined,
      };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.dmBubbleIn,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 18, color: AppColors.dmAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(correlation.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.dmText, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    DateFormat.MMMd().add_jm().format(correlation.at),
                    style: TextStyle(color: AppColors.dmTextSoft, fontSize: 10.5),
                  ),
                  if (correlation.watching.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Watching: ${correlation.watching.join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.dmText, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final TvActivitySession session;

  @override
  Widget build(BuildContext context) {
    final titles = session.events
        .where((e) => e.type == 'media_session' && e.mediaTitle != null)
        .map((e) => e.mediaTitle!)
        .toSet()
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dmPillFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.MMMd().add_jm().format(session.startedAt),
                  style: TextStyle(color: AppColors.dmText, fontSize: 12.5),
                ),
                if (titles.isNotEmpty)
                  Text(
                    titles.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.dmTextSoft, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            '${titles.length} title${titles.length == 1 ? '' : 's'}',
            style: TextStyle(color: AppColors.dmTextSoft, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
