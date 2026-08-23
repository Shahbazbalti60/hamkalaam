import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/admin_service.dart';

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  State<AdminUserManagementScreen> createState() =>
      _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState
    extends State<AdminUserManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AdminService _adminService = AdminService();

  String _searchQuery = '';
  String _filterRole = 'All';

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    // Fetch after first frame so we can safely use context (Provider).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final token = _token;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Not logged in';
      });
      return;
    }

    final result = await _adminService.getUsers(token);

    if (!mounted) return;

    if (result['success'] == true) {
      final List<dynamic> raw = result['users'];
      setState(() {
        _users = raw
            .map((u) => {
                  'id': u['id'],
                  'name': u['name'] ?? '',
                  'email': u['email'] ?? '',
                  'role': u['role'] ?? 'User',
                  'isActive': u['is_active'] ?? true,
                  'joinedDate': _formatDate(u['created_at']),
                })
            .toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result['message'] ?? 'Failed to load users';
      });
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((user) {
      final matchesSearch =
          user['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
              user['email'].toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesRole =
          _filterRole == 'All' || user['role'] == _filterRole;
      return matchesSearch && matchesRole;
    }).toList();
  }

  Future<void> _toggleUserStatus(int index) async {
    final user = _filteredUsers[index];
    final token = _token;
    if (token == null) return;

    final newStatus = !(user['isActive'] as bool);

    final result = await _adminService.updateStatus(
      token: token,
      userId: user['id'],
      isActive: newStatus,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final actualIndex = _users.indexWhere((u) => u['id'] == user['id']);
      setState(() => _users[actualIndex]['isActive'] = newStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus
              ? '${user['name']} activated'
              : '${user['name']} deactivated'),
          backgroundColor: newStatus ? Colors.green : Colors.red,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to update status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _changeRole(int index) {
    final user = _filteredUsers[index];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Role — ${user['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['User', 'Admin'].map((role) {
            return RadioListTile<String>(
              title: Text(role),
              value: role,
              groupValue: user['role'],
              onChanged: (value) async {
                Navigator.pop(context);
                if (value == null || value == user['role']) return;

                final token = _token;
                if (token == null) return;

                final result = await _adminService.updateRole(
                  token: token,
                  userId: user['id'],
                  newRole: value,
                );

                if (!mounted) return;

                if (result['success'] == true) {
                  final actualIndex =
                      _users.indexWhere((u) => u['id'] == user['id']);
                  setState(() => _users[actualIndex]['role'] = value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('${user['name']} role changed to $value'),
                      backgroundColor: const Color(0xFF1F3864),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(result['message'] ?? 'Failed to change role'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalUsers = _users.length;
    final activeUsers = _users.where((u) => u['isActive'] == true).length;
    final adminUsers = _users.where((u) => u['role'] == 'Admin').length;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('User Management',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 50, color: Colors.red[300]),
                      const SizedBox(height: 12),
                      Text(_errorMessage!,
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadUsers,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Stats
                    Container(
                      color: const Color(0xFF1F3864).withOpacity(0.04),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _StatChip(
                              label: 'Total',
                              value: '$totalUsers',
                              color: Colors.blue),
                          const SizedBox(width: 8),
                          _StatChip(
                              label: 'Active',
                              value: '$activeUsers',
                              color: Colors.green),
                          const SizedBox(width: 8),
                          _StatChip(
                              label: 'Admins',
                              value: '$adminUsers',
                              color: Colors.purple),
                        ],
                      ),
                    ),

                    // Search + Filter
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              decoration: InputDecoration(
                                hintText: 'Search users...',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.grey[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _filterRole,
                                items: ['All', 'User', 'Admin']
                                    .map((r) => DropdownMenuItem(
                                        value: r, child: Text(r)))
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => _filterRole = val!),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // User List
                    Expanded(
                      child: _filteredUsers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_search,
                                      size: 60, color: Colors.grey[300]),
                                  const SizedBox(height: 12),
                                  Text('No users found',
                                      style:
                                          TextStyle(color: Colors.grey[400])),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadUsers,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _filteredUsers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final user = _filteredUsers[index];
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border:
                                          Border.all(color: Colors.grey[200]!),
                                    ),
                                    child: Row(
                                      children: [
                                        // Avatar
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: user['role'] == 'Admin'
                                                ? Colors.purple[50]
                                                : const Color(0xFF1F3864)
                                                    .withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              (user['name'] as String)
                                                      .isNotEmpty
                                                  ? (user['name'] as String)
                                                      .substring(0, 1)
                                                      .toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: user['role'] == 'Admin'
                                                    ? Colors.purple[700]
                                                    : const Color(0xFF1F3864),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    user['name'],
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                      color: Color(0xFF1F3864),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  if (user['isActive'] !=
                                                      true)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 6,
                                                              vertical: 1),
                                                      decoration:
                                                          BoxDecoration(
                                                        color: Colors.red[50],
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                      ),
                                                      child: Text(
                                                        'Inactive',
                                                        style: TextStyle(
                                                            color: Colors
                                                                .red[700],
                                                            fontSize: 10),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                user['email'],
                                                style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 12),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: user['role'] ==
                                                              'Admin'
                                                          ? Colors.purple[50]
                                                          : Colors.blue[50],
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(6),
                                                    ),
                                                    child: Text(
                                                      user['role'],
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: user['role'] ==
                                                                'Admin'
                                                            ? Colors
                                                                .purple[700]
                                                            : Colors
                                                                .blue[700],
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Joined ${user['joinedDate']}',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.grey[400],
                                                        fontSize: 10),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Actions
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert,
                                              color: Colors.grey),
                                          onSelected: (value) {
                                            if (value == 'toggle') {
                                              _toggleUserStatus(index);
                                            } else if (value == 'role') {
                                              _changeRole(index);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'toggle',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    user['isActive'] == true
                                                        ? Icons.block
                                                        : Icons
                                                            .check_circle_outline,
                                                    size: 18,
                                                    color:
                                                        user['isActive'] ==
                                                                true
                                                            ? Colors.red
                                                            : Colors.green,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                      user['isActive'] == true
                                                          ? 'Deactivate'
                                                          : 'Activate'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'role',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .admin_panel_settings_outlined,
                                                      size: 18,
                                                      color: Colors.purple),
                                                  SizedBox(width: 8),
                                                  Text('Change Role'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}