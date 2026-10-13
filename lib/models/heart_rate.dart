/// One sample within a synced watch session -- see GET /health/heart-rate.
class HeartRateSample {
  final double bpm;
  final DateTime measuredAt;

  HeartRateSample({required this.bpm, required this.measuredAt});

  factory HeartRateSample.fromJson(Map<String, dynamic> json) => HeartRateSample(
        bpm: (json['bpm'] as num).toDouble(),
        measuredAt: DateTime.parse(json['measured_at']).toLocal(),
      );
}

class HeartRateSession {
  final int id;
  final String source;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<HeartRateSample> samples;

  HeartRateSession({
    required this.id,
    required this.source,
    required this.startedAt,
    this.endedAt,
    required this.samples,
  });

  factory HeartRateSession.fromJson(Map<String, dynamic> json) => HeartRateSession(
        id: json['id'],
        source: json['source'] ?? 'unknown',
        startedAt: DateTime.parse(json['started_at']).toLocal(),
        endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']).toLocal() : null,
        samples: (json['samples'] as List? ?? [])
            .map((s) => HeartRateSample.fromJson(s))
            .toList(),
      );
}

/// One correlated moment -- see GET /health/heart-rate/correlate.
class HeartRateCorrelation {
  final String type; // 'conversation' | 'task' | 'mood'
  final int id;
  final String label;
  final DateTime at;
  final double avgBpm;
  final double minBpm;
  final double maxBpm;
  final int sampleCount;

  HeartRateCorrelation({
    required this.type,
    required this.id,
    required this.label,
    required this.at,
    required this.avgBpm,
    required this.minBpm,
    required this.maxBpm,
    required this.sampleCount,
  });

  factory HeartRateCorrelation.fromJson(Map<String, dynamic> json) => HeartRateCorrelation(
        type: json['type'],
        id: json['id'],
        label: json['label'] ?? '',
        at: DateTime.parse(json['at']).toLocal(),
        avgBpm: (json['avg_bpm'] as num).toDouble(),
        minBpm: (json['min_bpm'] as num).toDouble(),
        maxBpm: (json['max_bpm'] as num).toDouble(),
        sampleCount: json['sample_count'],
      );
}
