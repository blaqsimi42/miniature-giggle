import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'qubool_loading_dots.dart';
import 'qubool_pulsing_logo.dart';

/// A full-screen loader and an Overlay helper to show/hide it.
class BeautifulLoader extends StatefulWidget {
  final String message;
  final bool showCloseButton;

  const BeautifulLoader({
    super.key,
    this.message = 'Loading...',
    this.showCloseButton = false,
  });

  @override
  State<BeautifulLoader> createState() => _BeautifulLoaderState();

  /// Convenience: returns the loader widget for use inside an OverlayEntry.
  static Widget overlay({
    String message = 'Loading...',
    bool showCloseButton = false,
  }) {
    return BeautifulLoader(
      message: message,
      showCloseButton: showCloseButton,
    );
  }
}

class _BeautifulLoaderState extends State<BeautifulLoader> {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/loader.png',
                fit: BoxFit.cover,
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenW = MediaQuery.of(context).size.width;
                      final logoWidth = (screenW * 0.52).clamp(0.0, 260.0);
                      return QuboolPulsingLogo(
                        assetPath: 'assets/icons/logo.png',
                        width: logoWidth,
                        minScale: 0.95,
                        maxScale: 1.045,
                        duration: const Duration(milliseconds: 1450),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  const QuboolLoadingDots(),
                  const SizedBox(height: 20),
                  Builder(
                    builder: (context) {
                      final screenW = MediaQuery.of(context).size.width;
                      final fontSize = (screenW * 0.05).clamp(18.0, 22.0);
                      return Text(
                        widget.message,
                        style: TextStyle(
                          color: const Color(0xFF555555),
                          fontSize: fontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (widget.showCloseButton)
              Positioned(
                top: 24,
                right: 16,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: LoadingScreen.hide,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Helper for showing a full-screen loader using an OverlayEntry.
class LoadingScreen {
  static OverlayEntry? _entry;

  /// Show the loader overlay. Safe to call multiple times.
  static void show(
    BuildContext context, {
    String message = 'Loading...',
    bool showCloseButton = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (_entry != null) return;
    final entry = OverlayEntry(
      builder: (_) => BeautifulLoader.overlay(
        message: message,
        showCloseButton: showCloseButton,
      ),
    );
    try {
      final overlayState = Overlay.of(context);
      overlayState.insert(entry);
      _entry = entry;
      // ignore: avoid_print
      print('[DEBUG LoadingScreen] show: overlay inserted');
    } catch (e) {
      // ignore: avoid_print
      print('[DEBUG LoadingScreen] show: failed to insert overlay: $e');
    }
  }

  /// Hide the loader overlay if shown.
  static void hide() {
    try {
      _entry?.remove();
      // ignore: avoid_print
      print('[DEBUG LoadingScreen] hide: overlay removed');
    } catch (_) {}
    _entry = null;
  }

  /// Convenience wrapper to show the loading overlay while running an async task.
  /// Ensures the overlay is visible for at least [minDuration]. If an overlay
  /// was already visible before calling this method, it will not be removed
  /// by the wrapper.
  static Future<T> whileLoading<T>(
    BuildContext context,
    Future<T> Function() task, {
    Duration minDuration = const Duration(milliseconds: 300),
    String message = 'Loading...',
    bool showCloseButton = false,
  }) async {
    final alreadyShown = _entry != null;
    // ignore: avoid_print
    print('[DEBUG LoadingScreen] whileLoading: alreadyShown=$alreadyShown');
    show(
      context,
      message: message,
      showCloseButton: showCloseButton,
    );
    final minDelay = Future.delayed(minDuration);
    try {
      final result = await task();
      await minDelay;
      // ignore: avoid_print
      print('[DEBUG LoadingScreen] whileLoading: task completed');
      return result;
    } finally {
      if (!alreadyShown) {
        hide();
      } else {
        // ignore: avoid_print
        print(
          '[DEBUG LoadingScreen] whileLoading: not hiding because alreadyShown=true',
        );
      }
    }
  }
}
