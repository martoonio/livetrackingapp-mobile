import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class EditValidationRadiusDialog extends StatefulWidget {
  final String clusterId;
  final String clusterName;
  final double currentRadius;
  final VoidCallback onSuccess;

  const EditValidationRadiusDialog({
    super.key,
    required this.clusterId,
    required this.clusterName,
    required this.currentRadius,
    required this.onSuccess,
  });

  @override
  State<EditValidationRadiusDialog> createState() =>
      _EditValidationRadiusDialogState();
}

class _EditValidationRadiusDialogState
    extends State<EditValidationRadiusDialog> {
  final TextEditingController _radiusController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Preset radius options
  final List<double> _presetRadiuses = [10, 20, 30, 50, 75, 100, 150, 200];

  @override
  void initState() {
    super.initState();
    _radiusController.text = widget.currentRadius.toInt().toString();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _updateValidationRadius() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final double newRadius = double.parse(_radiusController.text);

      // Update radius di Firebase
      await FirebaseDatabase.instance.ref('users/${widget.clusterId}').update({
        'checkpoint_validation_radius': newRadius,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Update semua task aktif dari cluster ini dengan radius baru
      await _updateActiveTasksRadius(newRadius);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui radius: $e'),
            backgroundColor: dangerR500,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateActiveTasksRadius(double newRadius) async {
    try {
      // Ambil semua task aktif dari cluster ini
      final tasksSnapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .orderByChild('clusterId')
          .equalTo(widget.clusterId)
          .get();

      if (tasksSnapshot.exists) {
        final tasksData = tasksSnapshot.value as Map<dynamic, dynamic>;
        final Map<String, dynamic> updates = {};

        // Update radius untuk task yang statusnya 'active' atau 'ongoing'
        tasksData.forEach((taskId, taskData) {
          if (taskData is Map) {
            final status = taskData['status']?.toString().toLowerCase();
            if (status == 'active' ||
                status == 'ongoing' ||
                status == 'assigned') {
              updates['tasks/$taskId/checkpointValidationRadius'] = newRadius;
            }
          }
        });

        if (updates.isNotEmpty) {
          await FirebaseDatabase.instance.ref().update(updates);
          print(
              'Updated ${updates.length} active tasks with new radius: $newRadius');
        }
      }
    } catch (e) {
      print('Error updating active tasks radius: $e');
    }
  }

  String? _validateRadius(String? value) {
    if (value == null || value.isEmpty) {
      return 'Radius tidak boleh kosong';
    }

    final double? radius = double.tryParse(value);
    if (radius == null) {
      return 'Masukkan angka yang valid';
    }

    if (radius < 5) {
      return 'Radius minimal 5 meter';
    }

    if (radius > 500) {
      return 'Radius maksimal 500 meter';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit Radius Validasi',
            style: boldTextStyle(size: 18),
          ),
          const SizedBox(height: 4),
          Text(
            widget.clusterName,
            style: mediumTextStyle(size: 14, color: neutral600),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tentukan radius validasi checkpoint untuk semua titik patroli di tatar ini.',
              style: regularTextStyle(size: 14, color: neutral700),
            ),
            const SizedBox(height: 16),

            // Current radius info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kbpBlue50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kbpBlue200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: kbpBlue700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Radius saat ini: ${widget.currentRadius.toInt()} meter',
                          style: semiBoldTextStyle(size: 14, color: kbpBlue900),
                        ),
                        Text(
                          'Petugas harus berada dalam radius ini dari checkpoint',
                          style: regularTextStyle(size: 12, color: kbpBlue700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Preset radius buttons
            Text(
              'Pilih Cepat:',
              style: mediumTextStyle(size: 14, color: neutral800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetRadiuses.map((radius) {
                final isSelected =
                    _radiusController.text == radius.toInt().toString();
                return GestureDetector(
                  onTap: () {
                    _radiusController.text = radius.toInt().toString();
                    setState(() {});
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? kbpBlue700 : neutral300,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? kbpBlue700 : neutral300,
                      ),
                    ),
                    child: Text(
                      '${radius.toInt()}m',
                      style: mediumTextStyle(
                        size: 12,
                        color: isSelected ? Colors.white : neutral700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Custom radius input
            Text(
              'Atau masukkan manual:',
              style: mediumTextStyle(size: 14, color: neutral800),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _radiusController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: InputDecoration(
                labelText: 'Radius (meter)',
                hintText: 'Contoh: 50',
                suffixText: 'meter',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: neutral300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: kbpBlue700, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              validator: _validateRadius,
              onChanged: (value) {
                setState(() {}); // Refresh untuk update preset selection
              },
            ),

            const SizedBox(height: 16),

            // Info about impact
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: warningY50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: warningY200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber, color: warningY300, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perhatian',
                          style:
                              semiBoldTextStyle(size: 14, color: warningY300),
                        ),
                        Text(
                          'Perubahan ini akan mempengaruhi:\n• Validasi checkpoint untuk patroli yang sedang berjalan\n• Laporan checkpoint yang terlewat',
                          style: regularTextStyle(size: 12, color: warningY300),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Batal',
            style: mediumTextStyle(color: neutral600),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateValidationRadius,
          style: ElevatedButton.styleFrom(
            backgroundColor: kbpBlue700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Simpan',
                  style: semiBoldTextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}
