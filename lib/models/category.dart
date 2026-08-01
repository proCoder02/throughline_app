class Categories {
  final List<String> builtin;
  final List<String> custom;

  Categories({required this.builtin, required this.custom});

  factory Categories.fromJson(Map<String, dynamic> json) => Categories(
        builtin: (json['builtin'] as List).cast<String>(),
        custom: (json['custom'] as List).cast<String>(),
      );

  List<String> get all => [...builtin, ...custom];
}
