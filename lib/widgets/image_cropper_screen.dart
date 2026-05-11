import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

class ImageCropperScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const ImageCropperScreen({super.key, required this.imageBytes});

  @override
  State<ImageCropperScreen> createState() => _ImageCropperScreenState();
}

class _ImageCropperScreenState extends State<ImageCropperScreen> {
  final _controller = CropController();
  bool _processing = false;

  void _onCropped(Uint8List cropped) {
    Navigator.of(context).pop(cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop photo'),
        actions: [
          TextButton(
            onPressed: _processing
                ? null
                : () {
                    setState(() => _processing = true);
                    _controller.crop();
                  },
            child: _processing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator())
                : const Text('Done'),
          )
        ],
      ),
      body: Center(
        child: Crop(
          controller: _controller,
          image: widget.imageBytes,
          onCropped: _onCropped,
          withCircleUi: false,
          baseColor: Theme.of(context).scaffoldBackgroundColor,
          maskColor: const Color.fromRGBO(0, 0, 0, 0.5),
          cornerDotBuilder: (size, edgeAlignment) => const DotControl(),
        ),
      ),
    );
  }
}

class DotControl extends StatelessWidget {
  const DotControl({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    );
  }
}
