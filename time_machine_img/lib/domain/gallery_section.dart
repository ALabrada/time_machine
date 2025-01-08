import 'package:time_machine_db/time_machine_db.dart';

class GallerySection {
  const GallerySection({
    required this.title,
    required this.elements,
  });

  final String title;
  final List<Record> elements;
}