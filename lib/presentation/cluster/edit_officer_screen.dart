import 'package:flutter/material.dart';
import '../../domain/entities/user.dart';
import '../component/utils.dart';

class EditOfficerScreen extends StatefulWidget {
  final Officer officer;
  final Function(Officer) onOfficerUpdated;

  const EditOfficerScreen({
    Key? key,
    required this.officer,
    required this.onOfficerUpdated,
  }) : super(key: key);

  @override
  _EditOfficerScreenState createState() => _EditOfficerScreenState();
}

class _EditOfficerScreenState extends State<EditOfficerScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late OfficerType _selectedType;
  late ShiftType _selectedShift;

  // Lista shift berdasarkan tipe officer
  Map<OfficerType, List<ShiftType>> _typeShifts = {
    OfficerType.organik: [
      ShiftType.pagi, // 07:00-15:00
      ShiftType.sore, // 15:00-23:00
      ShiftType.malam, // 23:00-07:00
    ],
    OfficerType.outsource: [
      ShiftType.siang, // 07:00-19:00
      ShiftType.malamPanjang, // 19:00-07:00
    ],
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.officer.name);
    _selectedType = widget.officer.type;
    _selectedShift = widget.officer.shift;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _getShiftDisplayText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07:00 - 15:00)';
      case ShiftType.sore:
        return 'Sore (15:00 - 23:00)';
      case ShiftType.malam:
        return 'Malam (23:00 - 07:00)';
      case ShiftType.siang:
        return 'Siang (07:00 - 19:00)';
      case ShiftType.malamPanjang:
        return 'Malam (19:00 - 07:00)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Edit Petugas',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nama Petugas
              Text(
                'Nama Petugas',
                style: mediumTextStyle(size: 16, color: kbpBlue900),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Masukkan nama petugas',
                  hintStyle: regularTextStyle(size: 14, color: neutral500),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: neutral300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: kbpBlue700, width: 1.5),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Nama petugas tidak boleh kosong';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Tipe Petugas
              Text(
                'Tipe Petugas',
                style: mediumTextStyle(size: 16, color: kbpBlue900),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: neutral300),
                ),
                child: DropdownButtonFormField<OfficerType>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                  ),
                  style: mediumTextStyle(size: 14, color: neutral700),
                  onChanged: (OfficerType? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedType = newValue;

                        // Jika tipe berubah, sesuaikan shift
                        if (!_typeShifts[newValue]!.contains(_selectedShift)) {
                          _selectedShift = _typeShifts[newValue]!.first;
                        }
                      });
                    }
                  },
                  items: OfficerType.values.map((type) {
                    String displayText =
                        type == OfficerType.organik ? 'Organik' : 'Outsource';

                    return DropdownMenuItem<OfficerType>(
                      value: type,
                      child: Text(displayText),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Shift Petugas
              Text(
                'Shift Petugas',
                style: mediumTextStyle(size: 16, color: kbpBlue900),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: neutral300),
                ),
                child: DropdownButtonFormField<ShiftType>(
                  value: _typeShifts[_selectedType]!.contains(_selectedShift)
                      ? _selectedShift
                      : _typeShifts[_selectedType]!.first,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                  ),
                  style: mediumTextStyle(size: 14, color: neutral700),
                  onChanged: (ShiftType? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedShift = newValue;
                      });
                    }
                  },
                  items: _typeShifts[_selectedType]!.map((shift) {
                    return DropdownMenuItem<ShiftType>(
                      value: shift,
                      child: Text(_getShiftDisplayText(shift)),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // Tombol Simpan
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final updatedOfficer = Officer(
                        id: widget.officer.id,
                        name: _nameController.text.trim(),
                        type: _selectedType,
                        shift: _selectedShift,
                        clusterId: widget.officer.clusterId,
                        photoUrl: widget.officer.photoUrl,
                      );

                      widget.onOfficerUpdated(updatedOfficer);
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kbpBlue900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Simpan Perubahan',
                    style: semiBoldTextStyle(size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
