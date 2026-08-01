class CallJoinInfo {
  final int callId;
  final String roomName;
  final String token;
  final String livekitUrl;

  CallJoinInfo({required this.callId, required this.roomName, required this.token, required this.livekitUrl});

  factory CallJoinInfo.fromJson(Map<String, dynamic> json) => CallJoinInfo(
        callId: json['call_id'],
        roomName: json['room_name'],
        token: json['token'],
        livekitUrl: json['livekit_url'],
      );
}

class IncomingCall {
  final int callId;
  final String roomName;
  final int callerId;
  final String callerName;

  IncomingCall({required this.callId, required this.roomName, required this.callerId, required this.callerName});
}
