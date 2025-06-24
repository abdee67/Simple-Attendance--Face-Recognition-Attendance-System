class User {
  final int id;
  final String userId;
  final String username;
  final String password;
  // other fields...

  User({
    required this.id,
    required this.userId,
    required this.username,
    required this.password,
    // ...
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      userId: json['userId'],
      username: json['username'],
      password: json['password'],
      // ...
    );
  }
}