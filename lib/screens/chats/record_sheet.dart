import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../services/conversation_service.dart';
import '../../theme.dart';

/// Record-then-upload flow (spec Â§8, path B): record locally, then
/// transcribe -> save -> analyze once the user stops. Returns the new
/// conversation id on success, or null if cancelled/failed.
Future<int?> showRecordSheet(BuildContext context) {
  return showModalBottomSheet<int?>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _RecordSheet(),
  );
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet();

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _recorder = AudioRecorder();
  final _conversationService = ConversationService();
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  bool _processing = false;
  String? _error;
  String? _path;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission denied');
      return;
    }
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/throughline_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: _path!);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
    setState(() => _recording = true);
  }

  Future<void> _stopAndProcess() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _processing = true;
    });
    try {
      final file = File(path ?? _path!);
      final transcript = await _conversationService.transcribe(file);
      final conversationId = await _conversationService.save(transcript: transcript);
      await _conversationService.analyze(conversationId: conversationId);
      if (mounted) Navigator.of(context).pop(conversationId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _processing = false;
          _error = 'Could not process the recording. Try again.';
        });
      }
    }
  }

  void _cancel() {
    _timer?.cancel();
    _recorder.stop();
    Navigator.of(context).pop(null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_processing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Transcribing and analyzing...'),
            ] else if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Close')),
            ] else ...[
              const Icon(Icons.mic, size: 48, color: AppColors.accent),
              const SizedBox(height: 8),
              Text(_format(_seconds), style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: _cancel, child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _recording ? _stopAndProcess : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
