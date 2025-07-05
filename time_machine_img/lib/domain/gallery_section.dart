import 'package:time_machine_db/time_machine_db.dart';

class GallerySection {
  const GallerySection({
    required this.date,
    required this.elements,
  });

  final DateTime date;
  final List<Record> elements;
}