class AuthUser {
  const AuthUser({required this.id, required this.username});

  final String id;
  final String username;

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      AuthUser(id: json['id'] as String, username: json['username'] as String);
}
