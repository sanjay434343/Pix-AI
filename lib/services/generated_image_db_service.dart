import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/generated_image.dart';

class GeneratedImageDbService {
  static final GeneratedImageDbService _instance = GeneratedImageDbService._internal();
  factory GeneratedImageDbService() => _instance;
  GeneratedImageDbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'generated_images.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE images(id INTEGER PRIMARY KEY AUTOINCREMENT, prompt TEXT, imageUrl TEXT, liked INTEGER DEFAULT 0)',
        );
      },
      version: 1,
    );
  }

  Future<List<GeneratedImage>> getImages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('images', orderBy: 'id DESC');
    return List.generate(maps.length, (i) => GeneratedImage.fromMap(maps[i]));
  }

  Future<void> insertImage(GeneratedImage image) async {
    final db = await database;
    await db.insert(
      'images',
      image.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setLikedStatus(String imageUrl, bool liked) async {
    final db = await database;
    await db.update(
      'images',
      {'liked': liked ? 1 : 0},
      where: 'imageUrl = ?',
      whereArgs: [imageUrl],
    );
  }

  Future<bool> isImageLiked(String imageUrl) async {
    final db = await database;
    final result = await db.query(
      'images',
      columns: ['liked'],
      where: 'imageUrl = ?',
      whereArgs: [imageUrl],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return (result.first['liked'] ?? 0) == 1;
    }
    return false;
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
