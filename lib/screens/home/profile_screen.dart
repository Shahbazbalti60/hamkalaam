import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isEditing = false;
  bool _isSaving = false;

  // --- FR-07: photo + Urdu dialect ---
  static const int _maxPhotoBytes = 2 * 1024 * 1024; // 2 MB
  final ProfileService _profileService = ProfileService();
  final ImagePicker _picker = ImagePicker();
  Uint8List? _photoBytes;
  bool _photoBusy = false;
  String _dialect = 'Standard'; // saved value
  String _dialectEdit = 'Standard'; // value shown while editing

  static const Map<String, String> _dialectLabels = {
    'Standard': 'Standard Urdu',
    'Punjabi': 'Punjabi-accented Urdu',
  };

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _nameController = TextEditingController(text: authService.userName ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExtras());
  }

  String? get _token =>
      Provider.of<AuthService>(context, listen: false).accessToken;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _loadExtras() async {
    final token = _token;
    if (token == null) return;
    final extras = await _profileService.getExtras(token);
    if (!mounted || extras['success'] != true) return;
    setState(() {
      _dialect = extras['urdu_dialect'] as String;
      _dialectEdit = _dialect;
    });
    if (extras['has_photo'] == true) {
      final bytes = await _profileService.getPhoto(token);
      if (mounted && bytes != null) setState(() => _photoBytes = bytes);
    }
  }

  Future<void> _pickPhoto() async {
    final token = _token;
    if (token == null) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (file == null) return; // cancelled
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      if (!(name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png'))) {
        _toast('Please choose a JPEG or PNG photo.', error: true);
        return;
      }
      if (bytes.length > _maxPhotoBytes) {
        _toast('Photo must be 2 MB or smaller.', error: true);
        return;
      }
      setState(() => _photoBusy = true);
      final result = await _profileService.uploadPhoto(
        token: token,
        bytes: bytes,
        filename: name,
      );
      if (!mounted) return;
      setState(() => _photoBusy = false);
      if (result['success'] == true) {
        setState(() => _photoBytes = bytes);
        _toast('Photo updated.');
      } else {
        _toast(result['message'] as String? ?? 'Could not save the photo', error: true);
      }
    } catch (_) {
      if (mounted) setState(() => _photoBusy = false);
      _toast('Could not open the photo picker.', error: true);
    }
  }

  Future<void> _removePhoto() async {
    final token = _token;
    if (token == null) return;
    setState(() => _photoBusy = true);
    final result = await _profileService.deletePhoto(token);
    if (!mounted) return;
    setState(() => _photoBusy = false);
    if (result['success'] == true) {
      setState(() => _photoBytes = null);
      _toast('Photo removed.');
    } else {
      _toast(result['message'] as String? ?? 'Could not remove the photo', error: true);
    }
  }

  void _showPhotoSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo (JPEG or PNG, max 2 MB)'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto();
              },
            ),
            if (_photoBytes != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              final authService =
                  Provider.of<AuthService>(context, listen: false);
              await authService.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Logout',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F3864),
        foregroundColor: Colors.white,
        title: const Text('My Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                _dialectEdit = _dialect;
              });
            },
            child: Text(
              _isEditing ? 'Cancel' : 'Edit',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F3864),
                      shape: BoxShape.circle,
                      image: _photoBytes == null
                          ? null
                          : DecorationImage(
                              image: MemoryImage(_photoBytes!),
                              fit: BoxFit.cover,
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1F3864).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _photoBytes != null
                        ? null
                        : Center(
                            child: Text(
                              (authService.userName ?? 'U')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                  if (_photoBusy)
                    const Positioned.fill(
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  if (_isEditing)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _photoBusy ? null : _showPhotoSheet,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 16, color: Color(0xFF1F3864)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              authService.userName ?? 'User',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F3864),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: authService.isAdmin
                    ? Colors.purple[50]
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                authService.isAdmin ? 'Administrator' : 'User',
                style: TextStyle(
                  color: authService.isAdmin
                      ? Colors.purple[700]
                      : Colors.blue[700],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Profile Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F3864),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name field
                    _isEditing
                        ? TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon:
                                  const Icon(Icons.person_outline),
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Name cannot be empty';
                              }
                              return null;
                            },
                          )
                        : _InfoRow(
                            icon: Icons.person_outline,
                            label: 'Full Name',
                            value: authService.userName ?? 'Not set',
                          ),

                    const SizedBox(height: 16),

                    // Email (always read-only)
                    _InfoRow(
                      icon: Icons.email_outlined,
                      label: 'Email Address',
                      value: authService.userEmail ?? 'Not set',
                    ),

                    const SizedBox(height: 16),

                    // Role (always read-only)
                    _InfoRow(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Role',
                      value: authService.isAdmin
                          ? 'Administrator'
                          : 'User (Deaf Individual)',
                    ),

                    const SizedBox(height: 16),

                    // Urdu voice dialect (FR-07)
                    _isEditing
                        ? DropdownButtonFormField<String>(
                            initialValue: _dialectEdit,
                            decoration: InputDecoration(
                              labelText: 'Urdu dialect',
                              helperText:
                                  'Saved with your profile. Dialect voices are not available yet.',
                              helperMaxLines: 2,
                              prefixIcon: const Icon(Icons.record_voice_over_outlined),
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: _dialectLabels.entries
                                .map((e) => DropdownMenuItem(
                                    value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _dialectEdit = v ?? _dialectEdit),
                          )
                        : _InfoRow(
                            icon: Icons.record_voice_over_outlined,
                            label: 'Urdu dialect',
                            value: _dialectLabels[_dialect] ?? _dialect,
                          ),

                    if (_isEditing) ...[
                      const SizedBox(height: 20),
                      _isSaving
                          ? const Center(
                              child: CircularProgressIndicator())
                          : ElevatedButton(
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  setState(() => _isSaving = true);

                                  final result = await authService
                                      .updateProfile(
                                          _nameController.text.trim());

                                  if (!mounted) return;

                                  // Dialect (FR-07): saved only when it changed.
                                  if (result['success'] == true &&
                                      _dialectEdit != _dialect) {
                                    final token = authService.accessToken;
                                    final d = token == null
                                        ? {'success': false}
                                        : await _profileService.setDialect(
                                            token, _dialectEdit);
                                    if (!mounted) return;
                                    if (d['success'] == true) {
                                      _dialect = _dialectEdit;
                                    } else {
                                      result['success'] = false;
                                      result['message'] =
                                          d['message'] ?? 'Could not save the dialect';
                                    }
                                  }

                                  setState(() => _isSaving = false);

                                  if (result['success'] == true) {
                                    setState(() => _isEditing = false);
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Profile updated successfully!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(result['message'] ??
                                            'Failed to update profile'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text('Save Changes'),
                            ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // App Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About HamKalaam',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F3864),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.info_outline,
                    label: 'Version',
                    value: '1.0.0 (Beta)',
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.school_outlined,
                    label: 'Institution',
                    value: 'COMSATS University Islamabad, Wah',
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.people_outline,
                    label: 'Developed By',
                    value: 'Shahbaz Hussain & Talha Ahmad',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Logout button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text(
                  'Logout',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[600],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF1F3864).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF1F3864), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F3864),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}