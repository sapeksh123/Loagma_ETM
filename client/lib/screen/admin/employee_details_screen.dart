import 'package:flutter/material.dart';

class EmployeeDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> employee;

  const EmployeeDetailsScreen({
    super.key,
    required this.employee,
  });

  @override
  Widget build(BuildContext context) {
    final name = (employee['name'] ?? 'Unknown').toString();
    final email = (employee['email'] ?? '').toString();
    final phone = (employee['contactNumber'] ?? '').toString();
    final altPhone = (employee['alternativeNumber'] ?? '').toString();
    final employeeCode = (employee['employeeCode'] ?? '').toString();
    final roleId = (employee['roleId'] ?? '').toString();
    final roles = (employee['roles'] ?? '').toString();
    final departmentId = (employee['departmentId'] ?? '').toString();
    final isActiveValue = employee['isActive'];
    final bool isActive = isActiveValue == 1 || isActiveValue == true;
    final address = (employee['address'] ?? '').toString();
    final city = (employee['city'] ?? '').toString();
    final state = (employee['state'] ?? '').toString();
    final country = (employee['country'] ?? '').toString();

    String primaryRoleLabel;
    if (roleId == 'R001') {
      primaryRoleLabel = 'Admin';
    } else {
      primaryRoleLabel = 'Employee';
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Employee Details'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor:
                          const Color(0xFFceb56e).withValues(alpha: 0.2),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFceb56e),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (employeeCode.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ID: $employeeCode',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isActive ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isActive ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.badge_outlined,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      primaryRoleLabel,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _detailSection(
              title: 'Contact',
              items: [
                if (phone.isNotEmpty)
                  _DetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: phone,
                  ),
                if (altPhone.isNotEmpty)
                  _DetailRow(
                    icon: Icons.phone_iphone_outlined,
                    label: 'Alternate',
                    value: altPhone,
                  ),
                if (email.isNotEmpty)
                  _DetailRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: email,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _detailSection(
              title: 'Organization',
              items: [
                if (roleId.isNotEmpty)
                  _DetailRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Role ID',
                    value: roleId,
                  ),
                if (roles.isNotEmpty)
                  _DetailRow(
                    icon: Icons.list_alt_outlined,
                    label: 'Roles',
                    value: roles,
                  ),
                if (departmentId.isNotEmpty)
                  _DetailRow(
                    icon: Icons.apartment_outlined,
                    label: 'Department ID',
                    value: departmentId,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _detailSection(
              title: 'Address',
              items: [
                if (address.isNotEmpty)
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: address,
                  ),
                if (city.isNotEmpty || state.isNotEmpty || country.isNotEmpty)
                  _DetailRow(
                    icon: Icons.public_outlined,
                    label: 'Location',
                    value: [
                      city,
                      state,
                      country,
                    ].where((e) => e.isNotEmpty).join(', '),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection({
    required String title,
    required List<Widget> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...items,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

