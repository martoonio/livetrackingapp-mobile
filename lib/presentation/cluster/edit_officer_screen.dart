import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

class EditOfficerScreen extends StatefulWidget {
  final String clusterId;
  final Officer? officer; // null jika membuat officer baru

  const EditOfficerScreen({
    Key? key,
    required this.clusterId,
    this.officer,
  }) : super(key: key);

  @override
  State<EditOfficerScreen> createState() => _EditOfficerScreenState();
}

class _EditOfficerScreenState extends State<EditOfficerScreen> {
  late final TextEditingController _nameController;
  late final GlobalKey<FormState> _formKey;
  String _selectedShift = 'Pagi';
  File? _selectedImage;
  String? _currentPhotoUrl;
  bool _isUploading = false;
  bool _isLoading = false;

  final List<String> _shiftOptions = ['Pagi', 'Siang', 'Malam'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.officer?.name ?? '');
    _formKey = GlobalKey<FormState>();
    _selectedShift = widget.officer?.shift ?? 'Pagi';
    _currentPhotoUrl = widget.officer?.photoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Metode untuk memilih gambar dari galeri
  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal memilih gambar: $e',
        type: SnackbarType.danger,
      );
    }
  }

  // Metode untuk mengupload gambar ke Firebase Storage
  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return _currentPhotoUrl;

    setState(() {
      _isUploading = true;
    });

    try {
      final fileName = 'officer_${DateTime.now().millisecondsSinceEpoch}_${path.basename(_selectedImage!.path)}';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('officer_photos')
          .child(widget.clusterId)
          .child(fileName);

      final uploadTask = storageRef.putFile(_selectedImage!);
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        _isUploading = false;
      });

      return downloadUrl;
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      print('Error uploading image: $e');
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal mengupload gambar: $e',
        type: SnackbarType.danger,
      );
      return null;
    }
  }

  // Metode untuk menyimpan data petugas
  Future<void> _saveOfficer() async {
    if (!_formKey.currentState!.validate()) return;

    // Tampilkan loading
    setState(() {
      _isLoading = true;
    });

    try {
      // Upload gambar jika ada
      String? photoUrl = await _uploadImage();

      // Buat objek Officer baru
      final officer = Officer(
        id: widget.officer?.id ?? '', // ID akan digenerate di repository jika kosong
        name: _nameController.text,
        shift: _selectedShift,
        clusterId: widget.clusterId,
        photoUrl: photoUrl,
      );

      // Tambah atau update officer berdasarkan mode
      if (widget.officer == null) {
        // Mode tambah officer baru
        context.read<AdminBloc>().add(
          AddOfficerToClusterEvent(
            clusterId: widget.clusterId,
            officer: officer,
          ),
        );
      } else {
        // Mode edit officer yang sudah ada
        context.read<AdminBloc>().add(
          UpdateOfficerInClusterEvent(
            clusterId: widget.clusterId,
            officer: officer,
          ),
        );
      }

      // Tunggu state berubah
      await Future.delayed(const Duration(milliseconds: 500));

      // Sembunyikan loading dan kembali ke halaman sebelumnya
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        showCustomSnackbar(
          context: context,
          title: 'Berhasil',
          subtitle: widget.officer == null
              ? 'Petugas berhasil ditambahkan'
              : 'Data petugas berhasil diperbarui',
          type: SnackbarType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      // Handle error
      setState(() {
        _isLoading = false;
      });
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal ${widget.officer == null ? 'menambahkan' : 'memperbarui'} petugas: $e',
        type: SnackbarType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.officer == null ? 'Tambah Petugas' : 'Edit Petugas'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: BlocListener<AdminBloc, AdminState>(
        listener: (context, state) {
          if (state is ClusterDetailsError || state is ClustersError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state is ClusterDetailsError
                      ? state.message
                      : (state as ClustersError).message,
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Foto Petugas
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: kbpBlue100,
                        child: _selectedImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(60),
                                child: Image.file(
                                  _selectedImage!,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(60),
                                    child: Image.network(
                                      _currentPhotoUrl!,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, _) => const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: kbpBlue900,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: kbpBlue900,
                                  )),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: kbpBlue900,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt),
                            color: Colors.white,
                            iconSize: 20,
                            onPressed: _pickImage,
                          ),
                        ),
                      ),
                      if (_isUploading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Nama Petugas
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nama Petugas',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: kbpBlue900, width: 2),
                    ),
                    prefixIcon: const Icon(Icons.person, color: kbpBlue900),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nama petugas tidak boleh kosong';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Shift
                const Text(
                  'Shift',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: neutral900,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: neutral400),
                  ),
                  child: Column(
                    children: _shiftOptions.map((shift) {
                      return RadioListTile<String>(
                        title: Text(shift),
                        value: shift,
                        groupValue: _selectedShift,
                        activeColor: kbpBlue900,
                        onChanged: (value) {
                          setState(() {
                            _selectedShift = value!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 32),

                // Tombol Simpan
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveOfficer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kbpBlue900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    disabledBackgroundColor: neutral300,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Text(
                          widget.officer == null ? 'Tambah Petugas' : 'Simpan Perubahan',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}