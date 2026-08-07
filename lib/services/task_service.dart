import '../models/task.dart';
import 'api_client.dart';
import 'local_cache.dart';

class TaskService {
  final _api = ApiClient.instance;
  final _cache = LocalCache.instance;

  List<Task>? listCached(String status) => _cache.getTasks(status);

  Future<List<Task>> list({String status = 'all'}) async {
    final r = await _api.dio.get('/tasks', queryParameters: {'status': status});
    final items = (r.data as List).map((j) => Task.fromJson(j)).toList();
    await _cache.setTasks(status, items);
    return items;
  }

  Future<void> complete(int id) => _api.dio.post('/tasks/$id/complete');
  Future<void> reopen(int id) => _api.dio.post('/tasks/$id/reopen');
  Future<void> delete(int id) => _api.dio.delete('/tasks/$id');

  /// At least one of description/dueDate must be provided.
  Future<void> edit(int id, {String? description, String? dueDate}) => _api.dio.post('/tasks/$id/edit', data: {
        if (description != null) 'description': description,
        if (dueDate != null) 'due_date': dueDate,
      });
}
