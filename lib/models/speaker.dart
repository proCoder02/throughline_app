class Speaker {
  final int id;
  final String name;

  Speaker({required this.id, required this.name});

  factory Speaker.fromJson(Map<String, dynamic> json) => Speaker(id: json['id'], name: json['name']);
}
