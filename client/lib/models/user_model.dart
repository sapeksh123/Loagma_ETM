class User {
  final String id;
  final String name;
  final String phone;
  final String role; // 'admin' or 'employee'
  final String? email;

  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      role: json['role'] ?? 'employee',
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'role': role,
      'email': email,
    };
  }
}
