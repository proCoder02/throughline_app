import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/heart_rate.dart';
import '../../services/heart_rate_service.dart';
import '../../theme.dart';

/// Watch heart-rate preview -- reads GET /health/heart-rate (raw synced
/// sessions) and GET /health/heart-rate/correlate (sessions matched against
/// this user's conversations/tasks/mood_logs by time proximity). Settings ->
/// Experimental sandbox, same convention as the other preview screens.
class HeartRatePreviewScreen extends StatefulWidget {
  const HeartRatePreviewScreen({super.key});

  @override
  State<HeartRatePreviewScreen> createState() => _HeartRatePreviewScreenState();
}

class _HeartRatePreviewScreenState extends State<HeartRatePreviewScreen> {
  final _service = HeartRateService();
  List<HeartRateSession>? _sessions;
  List<HeartRateCorrelation>? _correlations;
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
        _sessions = results[0] as List<HeartRateSession>;
        _correlations = results[1] as List<HeartRateCorrelation>;
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
          title: const Text('Watch Heart Rate'),
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
              Text('Could not load heart-rate data.', style: TextStyle(color: AppColors.dmTextSoft)),
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
            'No heart-rate sessions synced from the watch yet.',
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
              child: Text('No overlap yet -- nothing matched within 15 minutes of a synced reading.',
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
  final HeartRateCorrelation correlation;

  IconData get _icon => switch (correlation.type) {
        'conversation' => Icons.mic_none_rounded,
        'task' => Icons.check_circle_outline_rounded,
        'mood' => Icons.mood_rounded,
        _ => Icons.favorite_outline_rounded,
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
                    '${DateFormat.MMMd().add_jm().format(correlation.at)} · ${correlation.sampleCount} reading${correlation.sampleCount == 1 ? '' : 's'}',
                    style: TextStyle(color: AppColors.dmTextSoft, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            Text('${correlation.avgBpm.round()} bpm',
                style: TextStyle(color: AppColors.dmText, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final HeartRateSession session;

  @override
  Widget build(BuildContext context) {
    final avg = session.samples.isEmpty
        ? null
        : session.samples.map((s) => s.bpm).reduce((a, b) => a + b) / session.samples.length;
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
            child: Text(
              DateFormat.MMMd().add_jm().format(session.startedAt),
              style: TextStyle(color: AppColors.dmText, fontSize: 12.5),
            ),
          ),
          Text(
            avg == null ? '–' : '${avg.round()} bpm avg · ${session.samples.length}',
            style: TextStyle(color: AppColors.dmTextSoft, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
