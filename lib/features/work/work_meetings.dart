import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/formatted_text.dart';
import 'work_api.dart';
import 'work_commitments.dart';
import 'work_context.dart';
import 'work_ui.dart';

/// Meetings I can see (my teams', and private ones I was in, including my
/// own work calls), read-only: summary, decisions, commitments, blockers.
class MeetingsTab extends StatelessWidget {
  final WorkContext work;
  const MeetingsTab({super.key, required this.work});

  @override
  Widget build(BuildContext context) {
    final org = work.orgId;
    return WorkPage(
      title: 'Meetings',
      leading: work.leading(context),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DecisionsScreen(work: work))),
          icon: const Icon(Icons.gavel_rounded, size: 18),
          label: const Text('Decisions'),
        ),
      ],
      body: CachedLoad(
        cacheKey: 'meetings:$org',
        fetch: () => WorkApi.instance.meetings(org),
        builder: (context, data, reload) {
          final items = List<Map>.from((data as Map)['meetings'] ?? []);
          if (items.isEmpty) {
            return ListView(children: const [
              EmptyNote(
                icon: Icons.mic_none_rounded,
                title: 'No meetings yet',
                text: 'Meetings your teams record, and your own work calls, show up here with their decisions and commitments.',
              ),
            ]);
          }
          return ListView(padding: EdgeInsets.fromLTRB(14, 6, 14, listEnd(context)), children: [
            for (final m in items)
              WorkCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MeetingScreen(work: work, id: m['id'] as int, title: m['title'] as String? ?? 'Meeting'),
                )),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(m['source'] == 'call' ? Icons.call_outlined : Icons.groups_2_outlined, size: 16, color: AppColors.dmAccentDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(m['title'] as String? ?? 'Meeting',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dmText)),
                    ),
                    if (m['status'] != 'ready') StatusPill(m['status'] == 'failed' ? "Couldn't process" : 'Processing…'),
                  ]),
                  const SizedBox(height: 4),
                  Muted([
                    fmtDay(m['created_at'] as String?),
                    m['unit_name'] ?? 'Private',
                    if (m['created_by_name'] != null) 'by ${m['created_by_name']}',
                  ].join(' · ')),
                  if ((m['summary'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(m['summary'] as String,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: AppColors.dmText, height: 1.35)),
                  ],
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  const StatusPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.dmTextSoft.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft, fontWeight: FontWeight.w600)),
      );
}

class MeetingScreen extends StatelessWidget {
  final WorkContext work;
  final int id;
  final String title;
  const MeetingScreen({super.key, required this.work, required this.id, required this.title});

  @override
  Widget build(BuildContext context) {
    return WorkPage(
      title: title,
      body: CachedLoad(
        cacheKey: 'meeting:${work.orgId}:$id',
        fetch: () => WorkApi.instance.meeting(work.orgId, id),
        builder: (context, data, reload) {
          final m = data as Map;
          final decisions = List<Map>.from(m['decisions'] ?? []);
          final commitments = List<Map>.from(m['commitments'] ?? []);
          final blockers = List<Map>.from(m['blockers'] ?? []);
          final people = List<Map>.from(m['participants'] ?? []);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            Muted([fmtTime(m['created_at'] as String?), m['unit_name'] ?? 'Private'].join(' · ')),
            if (people.isNotEmpty) ...[
              const SizedBox(height: 4),
              Muted('With ${people.map((p) => p['username']).join(', ')}'),
            ],
            if ((m['summary'] as String?)?.isNotEmpty == true) ...[
              const SectionTitle('Summary'),
              FormattedText(m['summary'] as String, style: TextStyle(fontSize: 14.5, color: AppColors.dmText, height: 1.45)),
            ],
            if (decisions.isNotEmpty) ...[
              SectionTitle('Decisions', count: decisions.length),
              for (final d in decisions)
                WorkCard(
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DecisionScreen(work: work, id: d['id'] as int))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['title'] as String? ?? '', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
                    if (d['text'] != null && d['text'] != d['title']) ...[const SizedBox(height: 3), Muted(d['text'] as String, size: 13)],
                  ]),
                ),
            ],
            if (commitments.isNotEmpty) ...[
              SectionTitle('Commitments', count: commitments.length),
              for (final c in commitments)
                CommitmentTile(
                    c: c,
                    onTap: () async {
                      await openCommitment(context, work, c['id'] as int);
                      reload();
                    }),
            ],
            if (blockers.isNotEmpty) ...[
              SectionTitle('Blockers raised', count: blockers.length),
              for (final b in blockers)
                WorkCard(
                  edge: b['status'] == 'open' ? AppColors.danger : AppColors.dmTextSoft,
                  child: Text(b['text'] as String? ?? '', style: TextStyle(color: AppColors.dmText)),
                ),
            ],
            if ((m['transcript'] as String?)?.isNotEmpty == true)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Transcript', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.dmText)),
                  children: [
                    SelectableText(m['transcript'] as String, style: TextStyle(fontSize: 13, color: AppColors.dmText, height: 1.45))
                  ],
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class DecisionsScreen extends StatelessWidget {
  final WorkContext work;
  const DecisionsScreen({super.key, required this.work});

  @override
  Widget build(BuildContext context) {
    return WorkPage(
      title: 'Decisions',
      body: CachedLoad(
        cacheKey: 'decisions:${work.orgId}',
        fetch: () => WorkApi.instance.decisions(work.orgId),
        builder: (context, data, _) {
          final items = List<Map>.from((data as Map)['decisions'] ?? []);
          if (items.isEmpty) {
            return ListView(children: const [
              EmptyNote(
                  icon: Icons.gavel_rounded,
                  title: 'No decisions yet',
                  text: 'Decisions made in meetings and chat are kept here, with every earlier version.'),
            ]);
          }
          return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 24), children: [
            for (final d in items)
              WorkCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DecisionScreen(work: work, id: d['id'] as int))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d['title'] as String? ?? '', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.dmText)),
                  const SizedBox(height: 4),
                  Muted([
                    if (d['unit_name'] != null) d['unit_name'],
                    'v${d['version']}',
                    fmtDay(d['updated_at'] as String?),
                  ].join(' · ')),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class DecisionScreen extends StatelessWidget {
  final WorkContext work;
  final int id;
  const DecisionScreen({super.key, required this.work, required this.id});

  @override
  Widget build(BuildContext context) {
    return WorkPage(
      title: 'Decision',
      body: CachedLoad(
        cacheKey: null,
        fetch: () => WorkApi.instance.decision(work.orgId, id),
        builder: (context, data, _) {
          final d = (data as Map)['decision'] as Map;
          final versions = List<Map>.from(data['versions'] ?? []);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            Text(d['title'] as String? ?? '',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.dmText, height: 1.3)),
            const SizedBox(height: 4),
            const Muted('Changing a decision is done in a meeting, in chat or on the website. Earlier versions are always kept.'),
            SectionTitle('Versions', count: versions.length),
            for (final (i, v) in versions.indexed)
              WorkCard(
                edge: i == 0 ? AppColors.dmAccent : AppColors.dmTextSoft.withValues(alpha: 0.4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Version ${v['version']}', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.dmText)),
                    if (i == 0) ...[const SizedBox(width: 8), const StatusPill('Current')],
                  ]),
                  const SizedBox(height: 6),
                  Text(v['text'] as String? ?? '', style: TextStyle(fontSize: 14, color: AppColors.dmText, height: 1.4)),
                  if ((v['quote'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text('“${v['quote']}”', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: AppColors.dmTextSoft)),
                  ],
                  const SizedBox(height: 6),
                  Muted(
                      [
                        if (v['made_by'] != null) 'Decided by ${v['made_by']}',
                        if (v['source_type'] != null) 'from ${v['source_type'] == 'thread' ? 'chat' : v['source_type']}',
                        fmtDay(v['created_at'] as String?),
                      ].join(' · '),
                      size: 12),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}
