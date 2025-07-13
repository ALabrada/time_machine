import 'package:time_machine_db/time_machine_db.dart';

abstract class GallerySection {
  int get length;
}

final class GroupedSection implements GallerySection {
  const GroupedSection({
    required this.date,
    required this.elements,
  });

  final DateTime date;
  final List<Record> elements;

  @override
  int get length => elements.length;
}

final class RecentSection implements GallerySection {
  const RecentSection({
    required this.elements,
  });

  final List<Picture> elements;

  @override
  int get length => elements.length;
}