class User {
  final String id;
  final String email;
  final String name;
  final String role;
  String? pushToken;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.pushToken,
  });

  bool get hasProfile => name.isNotEmpty && role.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'push_token': pushToken, // Sertakan pushToken
    };
  }
}
