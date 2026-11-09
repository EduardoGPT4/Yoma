/// Filtro de progreso de lectura en biblioteca offline.
enum ReadingStatusFilter { all, inProgress, notStarted, completed }

extension ReadingStatusFilterX on ReadingStatusFilter {
  String get label {
    switch (this) {
      case ReadingStatusFilter.all:
        return 'Todos';
      case ReadingStatusFilter.inProgress:
        return 'En progreso';
      case ReadingStatusFilter.notStarted:
        return 'Sin empezar';
      case ReadingStatusFilter.completed:
        return 'Completados';
    }
  }
}
