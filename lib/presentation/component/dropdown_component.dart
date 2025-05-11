import 'package:flutter/material.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class CustomDropdown extends StatelessWidget {
  final String hintText;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final Function(String?) onChanged;
  final String? Function(String?)? validator;
  final Color borderColor; // Tambahkan parameter untuk warna border

  const CustomDropdown({
    super.key,
    required this.hintText,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.borderColor = kbpBlue900, // Default warna border
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 2), // Gunakan borderColor
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<String>(
        hint: Text(
          hintText,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black54,
            fontWeight: FontWeight.w400,
          ),
        ),
        decoration: const InputDecoration(
          hintStyle: TextStyle(
            fontSize: 16,
            color: Colors.black54,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        value: value,
        items: items,
        validator: validator,
        onChanged: onChanged,
      ),
    );
  }
}
