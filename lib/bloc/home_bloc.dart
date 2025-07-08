import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/generated_image.dart';
import '../services/generated_image_db_service.dart';

abstract class HomeEvent {}

class LoadImagesEvent extends HomeEvent {}

class SaveImageEvent extends HomeEvent {
  final String prompt;
  final String imageUrl;
  SaveImageEvent(this.prompt, this.imageUrl);
}

class HomeState {
  final List<GeneratedImage> images;
  final bool isLoading;
  final bool imagesLoaded;
  final bool showSkeleton;

  HomeState({
    required this.images,
    required this.isLoading,
    required this.imagesLoaded,
    required this.showSkeleton,
  });

  HomeState copyWith({
    List<GeneratedImage>? images,
    bool? isLoading,
    bool? imagesLoaded,
    bool? showSkeleton,
  }) {
    return HomeState(
      images: images ?? this.images,
      isLoading: isLoading ?? this.isLoading,
      imagesLoaded: imagesLoaded ?? this.imagesLoaded,
      showSkeleton: showSkeleton ?? this.showSkeleton,
    );
  }
}

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final GeneratedImageDbService dbService;

  HomeBloc(this.dbService)
      : super(HomeState(
          images: [],
          isLoading: true,
          imagesLoaded: false,
          showSkeleton: true,
        )) {
    on<LoadImagesEvent>(_onLoadImages);
    on<SaveImageEvent>(_onSaveImage);
  }

  Future<void> _onLoadImages(LoadImagesEvent event, Emitter<HomeState> emit) async {
    emit(state.copyWith(isLoading: true, showSkeleton: true));
    await Future.delayed(const Duration(seconds: 3));
    final images = await dbService.getImages();
    emit(state.copyWith(
      images: images,
      isLoading: false,
      imagesLoaded: true,
      showSkeleton: false,
    ));
  }

  Future<void> _onSaveImage(SaveImageEvent event, Emitter<HomeState> emit) async {
    await dbService.insertImage(GeneratedImage(prompt: event.prompt, imageUrl: event.imageUrl));
    add(LoadImagesEvent());
  }
}
