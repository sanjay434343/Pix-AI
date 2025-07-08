import 'package:flutter/material.dart';
import 'dart:ui'; // Import for ImageFilter
import 'full_screen_prompt_input_page.dart'; // Import the new full-screen page

class PromptInputCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onGenerate;
  final bool isLoading;
  final ValueNotifier<bool>? overlayOpen;
  final Future<String> Function(String prompt, {int width, int height})? onGenerateImage;
  final Future<void> Function(String prompt, String imageUrl)? onSaveImage;

  const PromptInputCard({
    Key? key,
    required this.controller,
    required this.onGenerate,
    required this.isLoading,
    this.overlayOpen,
    this.onGenerateImage,
    this.onSaveImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final showSquareCard = value.text.length > 3;
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            if (showSquareCard)
              Positioned(
                top: -120,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Card(
                    elevation: 8,
                    color: Colors.transparent,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide.none,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(32),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                                  child: TextField(
                                    controller: controller,
                                    readOnly: true,
                                    autofocus: false,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    decoration: InputDecoration(
                                      // labelText: 'Enter your prompt', // Remove label
                                      hintText: 'e.g. A futuristic city at sunset',
                                      hintStyle: const TextStyle(color: Colors.white70, fontSize: 16),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(32),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(32),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(32),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                      fillColor: Colors.transparent,
                                      filled: true,
                                    ),
                                    onSubmitted: (_) => onGenerate(),
                                    onTap: () async {
                                      overlayOpen?.value = true;
                                      final result = await FullScreenPromptInputPage.show(
                                        context,
                                        controller: controller,
                                        onGenerateImage: onGenerateImage!,
                                        isLoading: isLoading,
                                      );
                                      if (result != null &&
                                          result is Map &&
                                          result['prompt'] != null &&
                                          result['imageUrl'] != null &&
                                          onSaveImage != null) {
                                        await onSaveImage!(result['prompt'], result['imageUrl']);
                                      }
                                      overlayOpen?.value = false;
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        color: Colors.white,
                                        size: 28,
                                        shadows: [
                                          Shadow(
                                            color: Colors.white,
                                            blurRadius: 12,
                                            offset: Offset(0, 0),
                                          ),
                                          Shadow(
                                            color: Colors.white70,
                                            blurRadius: 24,
                                            offset: Offset(0, 0),
                                          ),
                                        ],
                                      ),
                                      onPressed: isLoading ? null : onGenerate,
                                      tooltip: 'Generate',
                                      padding: EdgeInsets.zero,
                                      splashRadius: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
