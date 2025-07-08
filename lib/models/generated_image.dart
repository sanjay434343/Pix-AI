class GeneratedImage {
  final int? id;
  final String prompt;
  final String imageUrl;

  GeneratedImage({this.id, required this.prompt, required this.imageUrl});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prompt': prompt,
      'imageUrl': imageUrl,
    };
  }

  factory GeneratedImage.fromMap(Map<String, dynamic> map) {
    return GeneratedImage(
      id: map['id'],
      prompt: map['prompt'],
      imageUrl: map['imageUrl'],
    );
  }

  // Optional: Helper for hero tags
  String heroTag(String prefix) => '$prefix-image-$imageUrl';
}
