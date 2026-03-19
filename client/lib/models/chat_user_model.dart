class ChatUser {
  final String id;
  final String name;
  final String? roleId;
  final String appRole;
  final String? contactNumber;

  ChatUser({
    required this.id,
    required this.name,
    required this.roleId,
    required this.appRole,
    this.contactNumber,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    final roleId = json['roleId']?.toString();
    return ChatUser(
      id: json['id']?.toString() ?? '',
      name: (json['name']?.toString().trim().isNotEmpty == true)
          ? json['name'].toString().trim()
          : 'Unknown User',
      roleId: roleId,
      appRole: _mapRole(roleId),
      contactNumber: json['contactNumber']?.toString(),
    );
  }

  static String _mapRole(String? roleId) {
    switch (roleId) {
      case 'R001':
        return 'admin';
      case 'R006':
        return 'subadmin';
      case 'R007':
        return 'techincharge';
      default:
        return 'employee';
    }
  }

  String get displayRole {
    switch (appRole) {
      case 'admin':
        return 'Admin';
      case 'subadmin':
        return 'Subadmin';
      case 'techincharge':
        return 'Technical Incharge';
      default:
        return 'Employee';
    }
  }
}
