import 'dart:async';

class PixService {
  // Simulate image generation from a prompt
  Future<String> generateImage(String prompt, {int width = 512, int height = 512, int seed = 42}) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    // Merge "AI prompt:" with the prompt
    final mergedPrompt = 'AI prompt: $prompt';
    // Build Pollinations API image URL with query parameters
    final url = 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(mergedPrompt)}'
        '?width=$width&height=$height&seed=$seed&nologo=true';
    return url;
  }
}