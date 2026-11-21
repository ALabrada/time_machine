import 'package:sembast/sembast.dart';
import 'package:time_machine_core/domain/date_time_converter.dart';
import 'package:time_machine_core/domain/picture.dart';
import 'package:time_machine_db/services/repository.dart';

extension PictureRepository on Repository<Picture> {
  Future<Picture?> findPictureByIdAndProvider(String id, String provider) async {
    final finder = Finder(filter: Filter.and([
      Filter.equals('id', id),
      Filter.equals('provider', provider),
    ]));
    final result = await findFirst(finder);
    return result;
  }

  Future<List<Picture>> findUpdatedPictures({
    DateTime? since,
  }) async {
    final finder = Finder(
      filter: since == null
          ? Filter.notNull('visitedAt')
          : Filter.and([
              Filter.notNull('visitedAt'),
              Filter.greaterThan('visitedAt', DateTimeConverter().toJson(since)),
            ]),
      sortOrders: [
        SortOrder('visitedAt', false),
      ],
    );
    final result = await find(finder);
    return result;
  }

  Future<List<Picture>> findPicturesWithText(List<String> keywords, {
    int limit = 20,
    List<String> providers = const[],
  }) async {
    final finder = Finder(
      filter: Filter.and([
        for (final word in keywords)
          Filter.matches('description', word),
        if (providers.isNotEmpty)
          Filter.inList('provider', providers),
      ]),
      sortOrders: [
        SortOrder('visitedAt', false, true),
      ],
      limit: limit,
    );
    final result = await find(finder);
    return result;
  }

  Future<List<Picture>> findVisitedPictures({
    int limit = 20,
    List<String> providers = const[],
  }) async {
    final finder = Finder(
      filter: providers.isEmpty ? Filter.notNull('visitedAt') : Filter.and([
        Filter.notNull('visitedAt'),
        Filter.inList('provider', providers),
      ]),
      sortOrders: [
        SortOrder('visitedAt', false),
      ],
      limit: limit,
    );
    final result = await find(finder);
    return result;
  }
}