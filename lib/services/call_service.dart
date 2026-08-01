import 'dart:io';

import 'package:dio/dio.dart';

import '../models/call.dart';
import 'api_client.dart';

class CallService {
  final _api = ApiClient.instance;

  Future<CallJoinInfo> start(List<int> friendIds) async {
    final r = await _api.dio.post('/calls', data: {'friend_ids': friendIds});
    return CallJoinInfo.fromJson(r.data);
  }

  Future<CallJoinInfo> join(int callId) async {
    final r = await _api.dio.post('/calls/$callId/join');
    return CallJoinInfo.fromJson(r.data);
  }

  Future<void> decline(int callId) => _api.dio.post('/calls/$callId/decline');

  Future<bool> leave(int callId) async {
    final r = await _api.dio.post('/calls/$callId/leave');
    return r.data['call_ended'] == true;
  }

  /// Own-mic-only recording upload (`scope=own`), independent of every
  /// other participant's own upload -- see the backend's additive branch
  /// in `/calls/<id>/recording`. Best-effort; caller should swallow errors.
  Future<void> uploadRecording(int callId, File audioFile) async {
    final form = FormData.fromMap({
      'scope': 'own',
      'audio': await MultipartFile.fromFile(audioFile.path, filename: 'call.m4a'),
    });
    await _api.dio.post('/calls/$callId/recording', data: form);
  }
}
