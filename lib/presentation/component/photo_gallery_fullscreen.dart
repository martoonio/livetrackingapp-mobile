import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'utils.dart';

class PhotoGalleryScreen extends StatefulWidget {
  final String title;
  final List<String> photoUrls;
  final int initialIndex;

  const PhotoGalleryScreen({
    Key? key,
    required this.title,
    required this.photoUrls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late int currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.title} (${currentIndex + 1}/${widget.photoUrls.length})',
          style: semiBoldTextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Photo viewer
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photoUrls.length,
              onPageChanged: (index) {
                setState(() {
                  currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Hero(
                      tag: 'report_photo_${widget.photoUrls[index]}',
                      child: Image.network(
                        widget.photoUrls[index].trim(),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image,
                                    size: 64,
                                    color: Colors.white.withOpacity(0.7)),
                                const SizedBox(height: 16),
                                Text(
                                  'Gagal memuat gambar',
                                  style: mediumTextStyle(
                                      color: Colors.white.withOpacity(0.7)),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {});
                                  },
                                  child: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Thumbnail gallery
          if (widget.photoUrls.length > 1)
            Container(
              height: 80,
              width: double.infinity,
              color: Colors.black.withOpacity(0.5),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.photoUrls.length,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      width: 64,
                      height: 64,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: currentIndex == index
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(widget.photoUrls[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: currentIndex == index
                          ? Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: Colors.black.withOpacity(0.1),
                              ),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
