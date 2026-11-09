// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ReadingProgressRowsTable extends ReadingProgressRows
    with TableInfo<$ReadingProgressRowsTable, ReadingProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mangaPathMeta = const VerificationMeta(
    'mangaPath',
  );
  @override
  late final GeneratedColumn<String> mangaPath = GeneratedColumn<String>(
    'manga_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mangaTitleMeta = const VerificationMeta(
    'mangaTitle',
  );
  @override
  late final GeneratedColumn<String> mangaTitle = GeneratedColumn<String>(
    'manga_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterPathMeta = const VerificationMeta(
    'chapterPath',
  );
  @override
  late final GeneratedColumn<String> chapterPath = GeneratedColumn<String>(
    'chapter_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageIndexMeta = const VerificationMeta(
    'pageIndex',
  );
  @override
  late final GeneratedColumn<int> pageIndex = GeneratedColumn<int>(
    'page_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mangaPath,
    mangaTitle,
    coverPath,
    chapterPath,
    chapterTitle,
    pageIndex,
    updatedAt,
    sourceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('manga_path')) {
      context.handle(
        _mangaPathMeta,
        mangaPath.isAcceptableOrUnknown(data['manga_path']!, _mangaPathMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaPathMeta);
    }
    if (data.containsKey('manga_title')) {
      context.handle(
        _mangaTitleMeta,
        mangaTitle.isAcceptableOrUnknown(data['manga_title']!, _mangaTitleMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaTitleMeta);
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('chapter_path')) {
      context.handle(
        _chapterPathMeta,
        chapterPath.isAcceptableOrUnknown(
          data['chapter_path']!,
          _chapterPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterPathMeta);
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterTitleMeta);
    }
    if (data.containsKey('page_index')) {
      context.handle(
        _pageIndexMeta,
        pageIndex.isAcceptableOrUnknown(data['page_index']!, _pageIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIndexMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mangaPath};
  @override
  ReadingProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressRow(
      mangaPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_path'],
      )!,
      mangaTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_title'],
      )!,
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      chapterPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_path'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      )!,
      pageIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_index'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
    );
  }

  @override
  $ReadingProgressRowsTable createAlias(String alias) {
    return $ReadingProgressRowsTable(attachedDatabase, alias);
  }
}

class ReadingProgressRow extends DataClass
    implements Insertable<ReadingProgressRow> {
  final String mangaPath;
  final String mangaTitle;
  final String? coverPath;
  final String chapterPath;
  final String chapterTitle;
  final int pageIndex;
  final int updatedAt;
  final String? sourceId;
  const ReadingProgressRow({
    required this.mangaPath,
    required this.mangaTitle,
    this.coverPath,
    required this.chapterPath,
    required this.chapterTitle,
    required this.pageIndex,
    required this.updatedAt,
    this.sourceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['manga_path'] = Variable<String>(mangaPath);
    map['manga_title'] = Variable<String>(mangaTitle);
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['chapter_path'] = Variable<String>(chapterPath);
    map['chapter_title'] = Variable<String>(chapterTitle);
    map['page_index'] = Variable<int>(pageIndex);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    return map;
  }

  ReadingProgressRowsCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressRowsCompanion(
      mangaPath: Value(mangaPath),
      mangaTitle: Value(mangaTitle),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      chapterPath: Value(chapterPath),
      chapterTitle: Value(chapterTitle),
      pageIndex: Value(pageIndex),
      updatedAt: Value(updatedAt),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
    );
  }

  factory ReadingProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressRow(
      mangaPath: serializer.fromJson<String>(json['mangaPath']),
      mangaTitle: serializer.fromJson<String>(json['mangaTitle']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      chapterPath: serializer.fromJson<String>(json['chapterPath']),
      chapterTitle: serializer.fromJson<String>(json['chapterTitle']),
      pageIndex: serializer.fromJson<int>(json['pageIndex']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mangaPath': serializer.toJson<String>(mangaPath),
      'mangaTitle': serializer.toJson<String>(mangaTitle),
      'coverPath': serializer.toJson<String?>(coverPath),
      'chapterPath': serializer.toJson<String>(chapterPath),
      'chapterTitle': serializer.toJson<String>(chapterTitle),
      'pageIndex': serializer.toJson<int>(pageIndex),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'sourceId': serializer.toJson<String?>(sourceId),
    };
  }

  ReadingProgressRow copyWith({
    String? mangaPath,
    String? mangaTitle,
    Value<String?> coverPath = const Value.absent(),
    String? chapterPath,
    String? chapterTitle,
    int? pageIndex,
    int? updatedAt,
    Value<String?> sourceId = const Value.absent(),
  }) => ReadingProgressRow(
    mangaPath: mangaPath ?? this.mangaPath,
    mangaTitle: mangaTitle ?? this.mangaTitle,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    chapterPath: chapterPath ?? this.chapterPath,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    pageIndex: pageIndex ?? this.pageIndex,
    updatedAt: updatedAt ?? this.updatedAt,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
  );
  ReadingProgressRow copyWithCompanion(ReadingProgressRowsCompanion data) {
    return ReadingProgressRow(
      mangaPath: data.mangaPath.present ? data.mangaPath.value : this.mangaPath,
      mangaTitle: data.mangaTitle.present
          ? data.mangaTitle.value
          : this.mangaTitle,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      chapterPath: data.chapterPath.present
          ? data.chapterPath.value
          : this.chapterPath,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      pageIndex: data.pageIndex.present ? data.pageIndex.value : this.pageIndex,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRow(')
          ..write('mangaPath: $mangaPath, ')
          ..write('mangaTitle: $mangaTitle, ')
          ..write('coverPath: $coverPath, ')
          ..write('chapterPath: $chapterPath, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourceId: $sourceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mangaPath,
    mangaTitle,
    coverPath,
    chapterPath,
    chapterTitle,
    pageIndex,
    updatedAt,
    sourceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressRow &&
          other.mangaPath == this.mangaPath &&
          other.mangaTitle == this.mangaTitle &&
          other.coverPath == this.coverPath &&
          other.chapterPath == this.chapterPath &&
          other.chapterTitle == this.chapterTitle &&
          other.pageIndex == this.pageIndex &&
          other.updatedAt == this.updatedAt &&
          other.sourceId == this.sourceId);
}

class ReadingProgressRowsCompanion extends UpdateCompanion<ReadingProgressRow> {
  final Value<String> mangaPath;
  final Value<String> mangaTitle;
  final Value<String?> coverPath;
  final Value<String> chapterPath;
  final Value<String> chapterTitle;
  final Value<int> pageIndex;
  final Value<int> updatedAt;
  final Value<String?> sourceId;
  final Value<int> rowid;
  const ReadingProgressRowsCompanion({
    this.mangaPath = const Value.absent(),
    this.mangaTitle = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.chapterPath = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressRowsCompanion.insert({
    required String mangaPath,
    required String mangaTitle,
    this.coverPath = const Value.absent(),
    required String chapterPath,
    required String chapterTitle,
    required int pageIndex,
    required int updatedAt,
    this.sourceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mangaPath = Value(mangaPath),
       mangaTitle = Value(mangaTitle),
       chapterPath = Value(chapterPath),
       chapterTitle = Value(chapterTitle),
       pageIndex = Value(pageIndex),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingProgressRow> custom({
    Expression<String>? mangaPath,
    Expression<String>? mangaTitle,
    Expression<String>? coverPath,
    Expression<String>? chapterPath,
    Expression<String>? chapterTitle,
    Expression<int>? pageIndex,
    Expression<int>? updatedAt,
    Expression<String>? sourceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mangaPath != null) 'manga_path': mangaPath,
      if (mangaTitle != null) 'manga_title': mangaTitle,
      if (coverPath != null) 'cover_path': coverPath,
      if (chapterPath != null) 'chapter_path': chapterPath,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (pageIndex != null) 'page_index': pageIndex,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sourceId != null) 'source_id': sourceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressRowsCompanion copyWith({
    Value<String>? mangaPath,
    Value<String>? mangaTitle,
    Value<String?>? coverPath,
    Value<String>? chapterPath,
    Value<String>? chapterTitle,
    Value<int>? pageIndex,
    Value<int>? updatedAt,
    Value<String?>? sourceId,
    Value<int>? rowid,
  }) {
    return ReadingProgressRowsCompanion(
      mangaPath: mangaPath ?? this.mangaPath,
      mangaTitle: mangaTitle ?? this.mangaTitle,
      coverPath: coverPath ?? this.coverPath,
      chapterPath: chapterPath ?? this.chapterPath,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      pageIndex: pageIndex ?? this.pageIndex,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceId: sourceId ?? this.sourceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mangaPath.present) {
      map['manga_path'] = Variable<String>(mangaPath.value);
    }
    if (mangaTitle.present) {
      map['manga_title'] = Variable<String>(mangaTitle.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (chapterPath.present) {
      map['chapter_path'] = Variable<String>(chapterPath.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (pageIndex.present) {
      map['page_index'] = Variable<int>(pageIndex.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRowsCompanion(')
          ..write('mangaPath: $mangaPath, ')
          ..write('mangaTitle: $mangaTitle, ')
          ..write('coverPath: $coverPath, ')
          ..write('chapterPath: $chapterPath, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourceId: $sourceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadChapterRowsTable extends ReadChapterRows
    with TableInfo<$ReadChapterRowsTable, ReadChapterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadChapterRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chapterPathMeta = const VerificationMeta(
    'chapterPath',
  );
  @override
  late final GeneratedColumn<String> chapterPath = GeneratedColumn<String>(
    'chapter_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [chapterPath];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'read_chapter_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadChapterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chapter_path')) {
      context.handle(
        _chapterPathMeta,
        chapterPath.isAcceptableOrUnknown(
          data['chapter_path']!,
          _chapterPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterPathMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chapterPath};
  @override
  ReadChapterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadChapterRow(
      chapterPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_path'],
      )!,
    );
  }

  @override
  $ReadChapterRowsTable createAlias(String alias) {
    return $ReadChapterRowsTable(attachedDatabase, alias);
  }
}

class ReadChapterRow extends DataClass implements Insertable<ReadChapterRow> {
  final String chapterPath;
  const ReadChapterRow({required this.chapterPath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chapter_path'] = Variable<String>(chapterPath);
    return map;
  }

  ReadChapterRowsCompanion toCompanion(bool nullToAbsent) {
    return ReadChapterRowsCompanion(chapterPath: Value(chapterPath));
  }

  factory ReadChapterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadChapterRow(
      chapterPath: serializer.fromJson<String>(json['chapterPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chapterPath': serializer.toJson<String>(chapterPath),
    };
  }

  ReadChapterRow copyWith({String? chapterPath}) =>
      ReadChapterRow(chapterPath: chapterPath ?? this.chapterPath);
  ReadChapterRow copyWithCompanion(ReadChapterRowsCompanion data) {
    return ReadChapterRow(
      chapterPath: data.chapterPath.present
          ? data.chapterPath.value
          : this.chapterPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadChapterRow(')
          ..write('chapterPath: $chapterPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => chapterPath.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadChapterRow && other.chapterPath == this.chapterPath);
}

class ReadChapterRowsCompanion extends UpdateCompanion<ReadChapterRow> {
  final Value<String> chapterPath;
  final Value<int> rowid;
  const ReadChapterRowsCompanion({
    this.chapterPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadChapterRowsCompanion.insert({
    required String chapterPath,
    this.rowid = const Value.absent(),
  }) : chapterPath = Value(chapterPath);
  static Insertable<ReadChapterRow> custom({
    Expression<String>? chapterPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (chapterPath != null) 'chapter_path': chapterPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadChapterRowsCompanion copyWith({
    Value<String>? chapterPath,
    Value<int>? rowid,
  }) {
    return ReadChapterRowsCompanion(
      chapterPath: chapterPath ?? this.chapterPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chapterPath.present) {
      map['chapter_path'] = Variable<String>(chapterPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadChapterRowsCompanion(')
          ..write('chapterPath: $chapterPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteRowsTable extends FavoriteRows
    with TableInfo<$FavoriteRowsTable, FavoriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mangaKeyMeta = const VerificationMeta(
    'mangaKey',
  );
  @override
  late final GeneratedColumn<String> mangaKey = GeneratedColumn<String>(
    'manga_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [mangaKey, title, coverPath];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('manga_key')) {
      context.handle(
        _mangaKeyMeta,
        mangaKey.isAcceptableOrUnknown(data['manga_key']!, _mangaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mangaKey};
  @override
  FavoriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteRow(
      mangaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_key'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
    );
  }

  @override
  $FavoriteRowsTable createAlias(String alias) {
    return $FavoriteRowsTable(attachedDatabase, alias);
  }
}

class FavoriteRow extends DataClass implements Insertable<FavoriteRow> {
  final String mangaKey;
  final String title;
  final String? coverPath;
  const FavoriteRow({
    required this.mangaKey,
    required this.title,
    this.coverPath,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['manga_key'] = Variable<String>(mangaKey);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    return map;
  }

  FavoriteRowsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteRowsCompanion(
      mangaKey: Value(mangaKey),
      title: Value(title),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
    );
  }

  factory FavoriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteRow(
      mangaKey: serializer.fromJson<String>(json['mangaKey']),
      title: serializer.fromJson<String>(json['title']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mangaKey': serializer.toJson<String>(mangaKey),
      'title': serializer.toJson<String>(title),
      'coverPath': serializer.toJson<String?>(coverPath),
    };
  }

  FavoriteRow copyWith({
    String? mangaKey,
    String? title,
    Value<String?> coverPath = const Value.absent(),
  }) => FavoriteRow(
    mangaKey: mangaKey ?? this.mangaKey,
    title: title ?? this.title,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
  );
  FavoriteRow copyWithCompanion(FavoriteRowsCompanion data) {
    return FavoriteRow(
      mangaKey: data.mangaKey.present ? data.mangaKey.value : this.mangaKey,
      title: data.title.present ? data.title.value : this.title,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRow(')
          ..write('mangaKey: $mangaKey, ')
          ..write('title: $title, ')
          ..write('coverPath: $coverPath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mangaKey, title, coverPath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteRow &&
          other.mangaKey == this.mangaKey &&
          other.title == this.title &&
          other.coverPath == this.coverPath);
}

class FavoriteRowsCompanion extends UpdateCompanion<FavoriteRow> {
  final Value<String> mangaKey;
  final Value<String> title;
  final Value<String?> coverPath;
  final Value<int> rowid;
  const FavoriteRowsCompanion({
    this.mangaKey = const Value.absent(),
    this.title = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteRowsCompanion.insert({
    required String mangaKey,
    required String title,
    this.coverPath = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mangaKey = Value(mangaKey),
       title = Value(title);
  static Insertable<FavoriteRow> custom({
    Expression<String>? mangaKey,
    Expression<String>? title,
    Expression<String>? coverPath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mangaKey != null) 'manga_key': mangaKey,
      if (title != null) 'title': title,
      if (coverPath != null) 'cover_path': coverPath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteRowsCompanion copyWith({
    Value<String>? mangaKey,
    Value<String>? title,
    Value<String?>? coverPath,
    Value<int>? rowid,
  }) {
    return FavoriteRowsCompanion(
      mangaKey: mangaKey ?? this.mangaKey,
      title: title ?? this.title,
      coverPath: coverPath ?? this.coverPath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mangaKey.present) {
      map['manga_key'] = Variable<String>(mangaKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteRowsCompanion(')
          ..write('mangaKey: $mangaKey, ')
          ..write('title: $title, ')
          ..write('coverPath: $coverPath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ReadingProgressRowsTable readingProgressRows =
      $ReadingProgressRowsTable(this);
  late final $ReadChapterRowsTable readChapterRows = $ReadChapterRowsTable(
    this,
  );
  late final $FavoriteRowsTable favoriteRows = $FavoriteRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    readingProgressRows,
    readChapterRows,
    favoriteRows,
  ];
}

typedef $$ReadingProgressRowsTableCreateCompanionBuilder =
    ReadingProgressRowsCompanion Function({
      required String mangaPath,
      required String mangaTitle,
      Value<String?> coverPath,
      required String chapterPath,
      required String chapterTitle,
      required int pageIndex,
      required int updatedAt,
      Value<String?> sourceId,
      Value<int> rowid,
    });
typedef $$ReadingProgressRowsTableUpdateCompanionBuilder =
    ReadingProgressRowsCompanion Function({
      Value<String> mangaPath,
      Value<String> mangaTitle,
      Value<String?> coverPath,
      Value<String> chapterPath,
      Value<String> chapterTitle,
      Value<int> pageIndex,
      Value<int> updatedAt,
      Value<String?> sourceId,
      Value<int> rowid,
    });

class $$ReadingProgressRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressRowsTable> {
  $$ReadingProgressRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mangaPath => $composableBuilder(
    column: $table.mangaPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mangaTitle => $composableBuilder(
    column: $table.mangaTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageIndex => $composableBuilder(
    column: $table.pageIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingProgressRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressRowsTable> {
  $$ReadingProgressRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mangaPath => $composableBuilder(
    column: $table.mangaPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mangaTitle => $composableBuilder(
    column: $table.mangaTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageIndex => $composableBuilder(
    column: $table.pageIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingProgressRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressRowsTable> {
  $$ReadingProgressRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mangaPath =>
      $composableBuilder(column: $table.mangaPath, builder: (column) => column);

  GeneratedColumn<String> get mangaTitle => $composableBuilder(
    column: $table.mangaTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);
}

class $$ReadingProgressRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressRowsTable,
          ReadingProgressRow,
          $$ReadingProgressRowsTableFilterComposer,
          $$ReadingProgressRowsTableOrderingComposer,
          $$ReadingProgressRowsTableAnnotationComposer,
          $$ReadingProgressRowsTableCreateCompanionBuilder,
          $$ReadingProgressRowsTableUpdateCompanionBuilder,
          (
            ReadingProgressRow,
            BaseReferences<
              _$AppDatabase,
              $ReadingProgressRowsTable,
              ReadingProgressRow
            >,
          ),
          ReadingProgressRow,
          PrefetchHooks Function()
        > {
  $$ReadingProgressRowsTableTableManager(
    _$AppDatabase db,
    $ReadingProgressRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingProgressRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mangaPath = const Value.absent(),
                Value<String> mangaTitle = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> chapterPath = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<int> pageIndex = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressRowsCompanion(
                mangaPath: mangaPath,
                mangaTitle: mangaTitle,
                coverPath: coverPath,
                chapterPath: chapterPath,
                chapterTitle: chapterTitle,
                pageIndex: pageIndex,
                updatedAt: updatedAt,
                sourceId: sourceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mangaPath,
                required String mangaTitle,
                Value<String?> coverPath = const Value.absent(),
                required String chapterPath,
                required String chapterTitle,
                required int pageIndex,
                required int updatedAt,
                Value<String?> sourceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressRowsCompanion.insert(
                mangaPath: mangaPath,
                mangaTitle: mangaTitle,
                coverPath: coverPath,
                chapterPath: chapterPath,
                chapterTitle: chapterTitle,
                pageIndex: pageIndex,
                updatedAt: updatedAt,
                sourceId: sourceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingProgressRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressRowsTable,
      ReadingProgressRow,
      $$ReadingProgressRowsTableFilterComposer,
      $$ReadingProgressRowsTableOrderingComposer,
      $$ReadingProgressRowsTableAnnotationComposer,
      $$ReadingProgressRowsTableCreateCompanionBuilder,
      $$ReadingProgressRowsTableUpdateCompanionBuilder,
      (
        ReadingProgressRow,
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressRowsTable,
          ReadingProgressRow
        >,
      ),
      ReadingProgressRow,
      PrefetchHooks Function()
    >;
typedef $$ReadChapterRowsTableCreateCompanionBuilder =
    ReadChapterRowsCompanion Function({
      required String chapterPath,
      Value<int> rowid,
    });
typedef $$ReadChapterRowsTableUpdateCompanionBuilder =
    ReadChapterRowsCompanion Function({
      Value<String> chapterPath,
      Value<int> rowid,
    });

class $$ReadChapterRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadChapterRowsTable> {
  $$ReadChapterRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadChapterRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadChapterRowsTable> {
  $$ReadChapterRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadChapterRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadChapterRowsTable> {
  $$ReadChapterRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get chapterPath => $composableBuilder(
    column: $table.chapterPath,
    builder: (column) => column,
  );
}

class $$ReadChapterRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadChapterRowsTable,
          ReadChapterRow,
          $$ReadChapterRowsTableFilterComposer,
          $$ReadChapterRowsTableOrderingComposer,
          $$ReadChapterRowsTableAnnotationComposer,
          $$ReadChapterRowsTableCreateCompanionBuilder,
          $$ReadChapterRowsTableUpdateCompanionBuilder,
          (
            ReadChapterRow,
            BaseReferences<
              _$AppDatabase,
              $ReadChapterRowsTable,
              ReadChapterRow
            >,
          ),
          ReadChapterRow,
          PrefetchHooks Function()
        > {
  $$ReadChapterRowsTableTableManager(
    _$AppDatabase db,
    $ReadChapterRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadChapterRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadChapterRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadChapterRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> chapterPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadChapterRowsCompanion(
                chapterPath: chapterPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String chapterPath,
                Value<int> rowid = const Value.absent(),
              }) => ReadChapterRowsCompanion.insert(
                chapterPath: chapterPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadChapterRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadChapterRowsTable,
      ReadChapterRow,
      $$ReadChapterRowsTableFilterComposer,
      $$ReadChapterRowsTableOrderingComposer,
      $$ReadChapterRowsTableAnnotationComposer,
      $$ReadChapterRowsTableCreateCompanionBuilder,
      $$ReadChapterRowsTableUpdateCompanionBuilder,
      (
        ReadChapterRow,
        BaseReferences<_$AppDatabase, $ReadChapterRowsTable, ReadChapterRow>,
      ),
      ReadChapterRow,
      PrefetchHooks Function()
    >;
typedef $$FavoriteRowsTableCreateCompanionBuilder =
    FavoriteRowsCompanion Function({
      required String mangaKey,
      required String title,
      Value<String?> coverPath,
      Value<int> rowid,
    });
typedef $$FavoriteRowsTableUpdateCompanionBuilder =
    FavoriteRowsCompanion Function({
      Value<String> mangaKey,
      Value<String> title,
      Value<String?> coverPath,
      Value<int> rowid,
    });

class $$FavoriteRowsTableFilterComposer
    extends Composer<_$AppDatabase, $FavoriteRowsTable> {
  $$FavoriteRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoriteRowsTable> {
  $$FavoriteRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoriteRowsTable> {
  $$FavoriteRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mangaKey =>
      $composableBuilder(column: $table.mangaKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);
}

class $$FavoriteRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoriteRowsTable,
          FavoriteRow,
          $$FavoriteRowsTableFilterComposer,
          $$FavoriteRowsTableOrderingComposer,
          $$FavoriteRowsTableAnnotationComposer,
          $$FavoriteRowsTableCreateCompanionBuilder,
          $$FavoriteRowsTableUpdateCompanionBuilder,
          (
            FavoriteRow,
            BaseReferences<_$AppDatabase, $FavoriteRowsTable, FavoriteRow>,
          ),
          FavoriteRow,
          PrefetchHooks Function()
        > {
  $$FavoriteRowsTableTableManager(_$AppDatabase db, $FavoriteRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mangaKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteRowsCompanion(
                mangaKey: mangaKey,
                title: title,
                coverPath: coverPath,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mangaKey,
                required String title,
                Value<String?> coverPath = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteRowsCompanion.insert(
                mangaKey: mangaKey,
                title: title,
                coverPath: coverPath,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoriteRowsTable,
      FavoriteRow,
      $$FavoriteRowsTableFilterComposer,
      $$FavoriteRowsTableOrderingComposer,
      $$FavoriteRowsTableAnnotationComposer,
      $$FavoriteRowsTableCreateCompanionBuilder,
      $$FavoriteRowsTableUpdateCompanionBuilder,
      (
        FavoriteRow,
        BaseReferences<_$AppDatabase, $FavoriteRowsTable, FavoriteRow>,
      ),
      FavoriteRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ReadingProgressRowsTableTableManager get readingProgressRows =>
      $$ReadingProgressRowsTableTableManager(_db, _db.readingProgressRows);
  $$ReadChapterRowsTableTableManager get readChapterRows =>
      $$ReadChapterRowsTableTableManager(_db, _db.readChapterRows);
  $$FavoriteRowsTableTableManager get favoriteRows =>
      $$FavoriteRowsTableTableManager(_db, _db.favoriteRows);
}
