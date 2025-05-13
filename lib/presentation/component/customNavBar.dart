import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CustomNavBar extends StatefulWidget {
  final List<NavBarItem> items;
  final int initialIndex;
  final Function(int) onItemSelected;

  const CustomNavBar({
    Key? key,
    required this.items,
    this.initialIndex = 0,
    required this.onItemSelected,
  }) : super(key: key);

  @override
  _CustomNavBarState createState() => _CustomNavBarState();
}

class _CustomNavBarState extends State<CustomNavBar> {
  int _selectedIndex = 0;
  double? _posX = -1;
  bool _isShow = true;
  int _minusWidth = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _posX = (-1 + (_selectedIndex * (2 / (widget.items.length - 1)))).toDouble();
  }

  void _movePage(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _isShow = false;
        _minusWidth = 0;
        _selectedIndex = index;
        _posX = (-1 + (index * (2 / (widget.items.length - 1)))).toDouble();
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        setState(() {
          _isShow = true;
          _minusWidth = 10;
        });
      });

      widget.onItemSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      width: double.infinity,
      height: 60,
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0xFFDBDBDB),
            blurRadius: 2.0,
            spreadRadius: 2.0,
          ),
        ],
        color: Colors.white,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedAlign(
            alignment: Alignment(_posX!, -1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.linear,
            child: Column(
              children: [
                AnimatedContainer(
                  width: MediaQuery.of(context).size.width / widget.items.length -
                      _minusWidth,
                  alignment: Alignment(_posX!, -1),
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                    color: Colors.teal, // Warna sesuai identitas aplikasi
                  ),
                ),
                Visibility(
                  visible: _isShow,
                  child: Container(
                    width: MediaQuery.of(context).size.width / widget.items.length -
                        _minusWidth,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.teal.withOpacity(0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: widget.items
                .asMap()
                .entries
                .map((entry) => _buildNavBarItem(entry.key, entry.value))
                .toList(),
          ),
        ],
      ),
    );
  }

  Expanded _buildNavBarItem(int index, NavBarItem item) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _movePage(index);
        },
        child: Container(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _selectedIndex == index ? item.activeIcon : item.inactiveIcon,
                color: _selectedIndex == index ? Colors.teal : Colors.grey,
                size: 24,
              ),
              const SizedBox(height: 5),
              Text(
                item.label,
                style: TextStyle(
                  color: _selectedIndex == index ? Colors.teal : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NavBarItem {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;

  const NavBarItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
  });
}