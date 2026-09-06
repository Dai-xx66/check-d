// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalTasksTable extends LocalTasks
    with TableInfo<$LocalTasksTable, LocalTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskTypeMeta = const VerificationMeta(
    'taskType',
  );
  @override
  late final GeneratedColumn<String> taskType = GeneratedColumn<String>(
    'task_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconNameMeta = const VerificationMeta(
    'iconName',
  );
  @override
  late final GeneratedColumn<String> iconName = GeneratedColumn<String>(
    'icon_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('target'),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncVersionMeta = const VerificationMeta(
    'syncVersion',
  );
  @override
  late final GeneratedColumn<int> syncVersion = GeneratedColumn<int>(
    'sync_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    taskType,
    colorValue,
    iconName,
    tagId,
    notes,
    status,
    createdAt,
    updatedAt,
    syncVersion,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('task_type')) {
      context.handle(
        _taskTypeMeta,
        taskType.isAcceptableOrUnknown(data['task_type']!, _taskTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_taskTypeMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('icon_name')) {
      context.handle(
        _iconNameMeta,
        iconName.isAcceptableOrUnknown(data['icon_name']!, _iconNameMeta),
      );
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sync_version')) {
      context.handle(
        _syncVersionMeta,
        syncVersion.isAcceptableOrUnknown(
          data['sync_version']!,
          _syncVersionMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      taskType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_type'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      iconName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_name'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      syncVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_version'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LocalTasksTable createAlias(String alias) {
    return $LocalTasksTable(attachedDatabase, alias);
  }
}

class LocalTask extends DataClass implements Insertable<LocalTask> {
  final String id;
  final String? userId;
  final String name;
  final String taskType;
  final int colorValue;
  final String iconName;
  final String? tagId;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncVersion;
  final DateTime? deletedAt;
  const LocalTask({
    required this.id,
    this.userId,
    required this.name,
    required this.taskType,
    required this.colorValue,
    required this.iconName,
    this.tagId,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.syncVersion,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['name'] = Variable<String>(name);
    map['task_type'] = Variable<String>(taskType);
    map['color_value'] = Variable<int>(colorValue);
    map['icon_name'] = Variable<String>(iconName);
    if (!nullToAbsent || tagId != null) {
      map['tag_id'] = Variable<String>(tagId);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sync_version'] = Variable<int>(syncVersion);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LocalTasksCompanion toCompanion(bool nullToAbsent) {
    return LocalTasksCompanion(
      id: Value(id),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      name: Value(name),
      taskType: Value(taskType),
      colorValue: Value(colorValue),
      iconName: Value(iconName),
      tagId: tagId == null && nullToAbsent
          ? const Value.absent()
          : Value(tagId),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      syncVersion: Value(syncVersion),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory LocalTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTask(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String?>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      taskType: serializer.fromJson<String>(json['taskType']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      iconName: serializer.fromJson<String>(json['iconName']),
      tagId: serializer.fromJson<String?>(json['tagId']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      syncVersion: serializer.fromJson<int>(json['syncVersion']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String?>(userId),
      'name': serializer.toJson<String>(name),
      'taskType': serializer.toJson<String>(taskType),
      'colorValue': serializer.toJson<int>(colorValue),
      'iconName': serializer.toJson<String>(iconName),
      'tagId': serializer.toJson<String?>(tagId),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'syncVersion': serializer.toJson<int>(syncVersion),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LocalTask copyWith({
    String? id,
    Value<String?> userId = const Value.absent(),
    String? name,
    String? taskType,
    int? colorValue,
    String? iconName,
    Value<String?> tagId = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncVersion,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LocalTask(
    id: id ?? this.id,
    userId: userId.present ? userId.value : this.userId,
    name: name ?? this.name,
    taskType: taskType ?? this.taskType,
    colorValue: colorValue ?? this.colorValue,
    iconName: iconName ?? this.iconName,
    tagId: tagId.present ? tagId.value : this.tagId,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncVersion: syncVersion ?? this.syncVersion,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LocalTask copyWithCompanion(LocalTasksCompanion data) {
    return LocalTask(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      iconName: data.iconName.present ? data.iconName.value : this.iconName,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      syncVersion: data.syncVersion.present
          ? data.syncVersion.value
          : this.syncVersion,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTask(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('taskType: $taskType, ')
          ..write('colorValue: $colorValue, ')
          ..write('iconName: $iconName, ')
          ..write('tagId: $tagId, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    taskType,
    colorValue,
    iconName,
    tagId,
    notes,
    status,
    createdAt,
    updatedAt,
    syncVersion,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTask &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.taskType == this.taskType &&
          other.colorValue == this.colorValue &&
          other.iconName == this.iconName &&
          other.tagId == this.tagId &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.syncVersion == this.syncVersion &&
          other.deletedAt == this.deletedAt);
}

class LocalTasksCompanion extends UpdateCompanion<LocalTask> {
  final Value<String> id;
  final Value<String?> userId;
  final Value<String> name;
  final Value<String> taskType;
  final Value<int> colorValue;
  final Value<String> iconName;
  final Value<String?> tagId;
  final Value<String?> notes;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> syncVersion;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const LocalTasksCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.taskType = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.iconName = const Value.absent(),
    this.tagId = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTasksCompanion.insert({
    required String id,
    this.userId = const Value.absent(),
    required String name,
    required String taskType,
    required int colorValue,
    this.iconName = const Value.absent(),
    this.tagId = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.syncVersion = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       taskType = Value(taskType),
       colorValue = Value(colorValue),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalTask> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? taskType,
    Expression<int>? colorValue,
    Expression<String>? iconName,
    Expression<String>? tagId,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? syncVersion,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (taskType != null) 'task_type': taskType,
      if (colorValue != null) 'color_value': colorValue,
      if (iconName != null) 'icon_name': iconName,
      if (tagId != null) 'tag_id': tagId,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (syncVersion != null) 'sync_version': syncVersion,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTasksCompanion copyWith({
    Value<String>? id,
    Value<String?>? userId,
    Value<String>? name,
    Value<String>? taskType,
    Value<int>? colorValue,
    Value<String>? iconName,
    Value<String?>? tagId,
    Value<String?>? notes,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? syncVersion,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return LocalTasksCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      taskType: taskType ?? this.taskType,
      colorValue: colorValue ?? this.colorValue,
      iconName: iconName ?? this.iconName,
      tagId: tagId ?? this.tagId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncVersion: syncVersion ?? this.syncVersion,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (taskType.present) {
      map['task_type'] = Variable<String>(taskType.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (iconName.present) {
      map['icon_name'] = Variable<String>(iconName.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (syncVersion.present) {
      map['sync_version'] = Variable<int>(syncVersion.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTasksCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('taskType: $taskType, ')
          ..write('colorValue: $colorValue, ')
          ..write('iconName: $iconName, ')
          ..write('tagId: $tagId, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LongTermTaskRecordsTable extends LongTermTaskRecords
    with TableInfo<$LongTermTaskRecordsTable, LongTermTaskRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LongTermTaskRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkModeMeta = const VerificationMeta(
    'checkMode',
  );
  @override
  late final GeneratedColumn<String> checkMode = GeneratedColumn<String>(
    'check_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetDurationSecondsMeta =
      const VerificationMeta('targetDurationSeconds');
  @override
  late final GeneratedColumn<int> targetDurationSeconds = GeneratedColumn<int>(
    'target_duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetDaysMeta = const VerificationMeta(
    'targetDays',
  );
  @override
  late final GeneratedColumn<int> targetDays = GeneratedColumn<int>(
    'target_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _holidayPauseMeta = const VerificationMeta(
    'holidayPause',
  );
  @override
  late final GeneratedColumn<bool> holidayPause = GeneratedColumn<bool>(
    'holiday_pause',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("holiday_pause" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _scheduledMinuteOfDayMeta =
      const VerificationMeta('scheduledMinuteOfDay');
  @override
  late final GeneratedColumn<int> scheduledMinuteOfDay = GeneratedColumn<int>(
    'scheduled_minute_of_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reminderMinuteOfDayMeta =
      const VerificationMeta('reminderMinuteOfDay');
  @override
  late final GeneratedColumn<int> reminderMinuteOfDay = GeneratedColumn<int>(
    'reminder_minute_of_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    userId,
    checkMode,
    targetDurationSeconds,
    targetDays,
    holidayPause,
    scheduledMinuteOfDay,
    reminderMinuteOfDay,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'long_term_task_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<LongTermTaskRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('check_mode')) {
      context.handle(
        _checkModeMeta,
        checkMode.isAcceptableOrUnknown(data['check_mode']!, _checkModeMeta),
      );
    } else if (isInserting) {
      context.missing(_checkModeMeta);
    }
    if (data.containsKey('target_duration_seconds')) {
      context.handle(
        _targetDurationSecondsMeta,
        targetDurationSeconds.isAcceptableOrUnknown(
          data['target_duration_seconds']!,
          _targetDurationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('target_days')) {
      context.handle(
        _targetDaysMeta,
        targetDays.isAcceptableOrUnknown(data['target_days']!, _targetDaysMeta),
      );
    }
    if (data.containsKey('holiday_pause')) {
      context.handle(
        _holidayPauseMeta,
        holidayPause.isAcceptableOrUnknown(
          data['holiday_pause']!,
          _holidayPauseMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_minute_of_day')) {
      context.handle(
        _scheduledMinuteOfDayMeta,
        scheduledMinuteOfDay.isAcceptableOrUnknown(
          data['scheduled_minute_of_day']!,
          _scheduledMinuteOfDayMeta,
        ),
      );
    }
    if (data.containsKey('reminder_minute_of_day')) {
      context.handle(
        _reminderMinuteOfDayMeta,
        reminderMinuteOfDay.isAcceptableOrUnknown(
          data['reminder_minute_of_day']!,
          _reminderMinuteOfDayMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  LongTermTaskRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LongTermTaskRecord(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      checkMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}check_mode'],
      )!,
      targetDurationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_duration_seconds'],
      ),
      targetDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_days'],
      ),
      holidayPause: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}holiday_pause'],
      )!,
      scheduledMinuteOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_minute_of_day'],
      ),
      reminderMinuteOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_minute_of_day'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LongTermTaskRecordsTable createAlias(String alias) {
    return $LongTermTaskRecordsTable(attachedDatabase, alias);
  }
}

class LongTermTaskRecord extends DataClass
    implements Insertable<LongTermTaskRecord> {
  final String taskId;
  final String userId;
  final String checkMode;
  final int? targetDurationSeconds;
  final int? targetDays;
  final bool holidayPause;
  final int? scheduledMinuteOfDay;
  final int? reminderMinuteOfDay;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LongTermTaskRecord({
    required this.taskId,
    required this.userId,
    required this.checkMode,
    this.targetDurationSeconds,
    this.targetDays,
    required this.holidayPause,
    this.scheduledMinuteOfDay,
    this.reminderMinuteOfDay,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    map['check_mode'] = Variable<String>(checkMode);
    if (!nullToAbsent || targetDurationSeconds != null) {
      map['target_duration_seconds'] = Variable<int>(targetDurationSeconds);
    }
    if (!nullToAbsent || targetDays != null) {
      map['target_days'] = Variable<int>(targetDays);
    }
    map['holiday_pause'] = Variable<bool>(holidayPause);
    if (!nullToAbsent || scheduledMinuteOfDay != null) {
      map['scheduled_minute_of_day'] = Variable<int>(scheduledMinuteOfDay);
    }
    if (!nullToAbsent || reminderMinuteOfDay != null) {
      map['reminder_minute_of_day'] = Variable<int>(reminderMinuteOfDay);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LongTermTaskRecordsCompanion toCompanion(bool nullToAbsent) {
    return LongTermTaskRecordsCompanion(
      taskId: Value(taskId),
      userId: Value(userId),
      checkMode: Value(checkMode),
      targetDurationSeconds: targetDurationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDurationSeconds),
      targetDays: targetDays == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDays),
      holidayPause: Value(holidayPause),
      scheduledMinuteOfDay: scheduledMinuteOfDay == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledMinuteOfDay),
      reminderMinuteOfDay: reminderMinuteOfDay == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderMinuteOfDay),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LongTermTaskRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LongTermTaskRecord(
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      checkMode: serializer.fromJson<String>(json['checkMode']),
      targetDurationSeconds: serializer.fromJson<int?>(
        json['targetDurationSeconds'],
      ),
      targetDays: serializer.fromJson<int?>(json['targetDays']),
      holidayPause: serializer.fromJson<bool>(json['holidayPause']),
      scheduledMinuteOfDay: serializer.fromJson<int?>(
        json['scheduledMinuteOfDay'],
      ),
      reminderMinuteOfDay: serializer.fromJson<int?>(
        json['reminderMinuteOfDay'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'checkMode': serializer.toJson<String>(checkMode),
      'targetDurationSeconds': serializer.toJson<int?>(targetDurationSeconds),
      'targetDays': serializer.toJson<int?>(targetDays),
      'holidayPause': serializer.toJson<bool>(holidayPause),
      'scheduledMinuteOfDay': serializer.toJson<int?>(scheduledMinuteOfDay),
      'reminderMinuteOfDay': serializer.toJson<int?>(reminderMinuteOfDay),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LongTermTaskRecord copyWith({
    String? taskId,
    String? userId,
    String? checkMode,
    Value<int?> targetDurationSeconds = const Value.absent(),
    Value<int?> targetDays = const Value.absent(),
    bool? holidayPause,
    Value<int?> scheduledMinuteOfDay = const Value.absent(),
    Value<int?> reminderMinuteOfDay = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LongTermTaskRecord(
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    checkMode: checkMode ?? this.checkMode,
    targetDurationSeconds: targetDurationSeconds.present
        ? targetDurationSeconds.value
        : this.targetDurationSeconds,
    targetDays: targetDays.present ? targetDays.value : this.targetDays,
    holidayPause: holidayPause ?? this.holidayPause,
    scheduledMinuteOfDay: scheduledMinuteOfDay.present
        ? scheduledMinuteOfDay.value
        : this.scheduledMinuteOfDay,
    reminderMinuteOfDay: reminderMinuteOfDay.present
        ? reminderMinuteOfDay.value
        : this.reminderMinuteOfDay,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LongTermTaskRecord copyWithCompanion(LongTermTaskRecordsCompanion data) {
    return LongTermTaskRecord(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      checkMode: data.checkMode.present ? data.checkMode.value : this.checkMode,
      targetDurationSeconds: data.targetDurationSeconds.present
          ? data.targetDurationSeconds.value
          : this.targetDurationSeconds,
      targetDays: data.targetDays.present
          ? data.targetDays.value
          : this.targetDays,
      holidayPause: data.holidayPause.present
          ? data.holidayPause.value
          : this.holidayPause,
      scheduledMinuteOfDay: data.scheduledMinuteOfDay.present
          ? data.scheduledMinuteOfDay.value
          : this.scheduledMinuteOfDay,
      reminderMinuteOfDay: data.reminderMinuteOfDay.present
          ? data.reminderMinuteOfDay.value
          : this.reminderMinuteOfDay,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LongTermTaskRecord(')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('checkMode: $checkMode, ')
          ..write('targetDurationSeconds: $targetDurationSeconds, ')
          ..write('targetDays: $targetDays, ')
          ..write('holidayPause: $holidayPause, ')
          ..write('scheduledMinuteOfDay: $scheduledMinuteOfDay, ')
          ..write('reminderMinuteOfDay: $reminderMinuteOfDay, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    userId,
    checkMode,
    targetDurationSeconds,
    targetDays,
    holidayPause,
    scheduledMinuteOfDay,
    reminderMinuteOfDay,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LongTermTaskRecord &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.checkMode == this.checkMode &&
          other.targetDurationSeconds == this.targetDurationSeconds &&
          other.targetDays == this.targetDays &&
          other.holidayPause == this.holidayPause &&
          other.scheduledMinuteOfDay == this.scheduledMinuteOfDay &&
          other.reminderMinuteOfDay == this.reminderMinuteOfDay &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LongTermTaskRecordsCompanion extends UpdateCompanion<LongTermTaskRecord> {
  final Value<String> taskId;
  final Value<String> userId;
  final Value<String> checkMode;
  final Value<int?> targetDurationSeconds;
  final Value<int?> targetDays;
  final Value<bool> holidayPause;
  final Value<int?> scheduledMinuteOfDay;
  final Value<int?> reminderMinuteOfDay;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LongTermTaskRecordsCompanion({
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.checkMode = const Value.absent(),
    this.targetDurationSeconds = const Value.absent(),
    this.targetDays = const Value.absent(),
    this.holidayPause = const Value.absent(),
    this.scheduledMinuteOfDay = const Value.absent(),
    this.reminderMinuteOfDay = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LongTermTaskRecordsCompanion.insert({
    required String taskId,
    required String userId,
    required String checkMode,
    this.targetDurationSeconds = const Value.absent(),
    this.targetDays = const Value.absent(),
    this.holidayPause = const Value.absent(),
    this.scheduledMinuteOfDay = const Value.absent(),
    this.reminderMinuteOfDay = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       userId = Value(userId),
       checkMode = Value(checkMode),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LongTermTaskRecord> custom({
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<String>? checkMode,
    Expression<int>? targetDurationSeconds,
    Expression<int>? targetDays,
    Expression<bool>? holidayPause,
    Expression<int>? scheduledMinuteOfDay,
    Expression<int>? reminderMinuteOfDay,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (checkMode != null) 'check_mode': checkMode,
      if (targetDurationSeconds != null)
        'target_duration_seconds': targetDurationSeconds,
      if (targetDays != null) 'target_days': targetDays,
      if (holidayPause != null) 'holiday_pause': holidayPause,
      if (scheduledMinuteOfDay != null)
        'scheduled_minute_of_day': scheduledMinuteOfDay,
      if (reminderMinuteOfDay != null)
        'reminder_minute_of_day': reminderMinuteOfDay,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LongTermTaskRecordsCompanion copyWith({
    Value<String>? taskId,
    Value<String>? userId,
    Value<String>? checkMode,
    Value<int?>? targetDurationSeconds,
    Value<int?>? targetDays,
    Value<bool>? holidayPause,
    Value<int?>? scheduledMinuteOfDay,
    Value<int?>? reminderMinuteOfDay,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LongTermTaskRecordsCompanion(
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      checkMode: checkMode ?? this.checkMode,
      targetDurationSeconds:
          targetDurationSeconds ?? this.targetDurationSeconds,
      targetDays: targetDays ?? this.targetDays,
      holidayPause: holidayPause ?? this.holidayPause,
      scheduledMinuteOfDay: scheduledMinuteOfDay ?? this.scheduledMinuteOfDay,
      reminderMinuteOfDay: reminderMinuteOfDay ?? this.reminderMinuteOfDay,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (checkMode.present) {
      map['check_mode'] = Variable<String>(checkMode.value);
    }
    if (targetDurationSeconds.present) {
      map['target_duration_seconds'] = Variable<int>(
        targetDurationSeconds.value,
      );
    }
    if (targetDays.present) {
      map['target_days'] = Variable<int>(targetDays.value);
    }
    if (holidayPause.present) {
      map['holiday_pause'] = Variable<bool>(holidayPause.value);
    }
    if (scheduledMinuteOfDay.present) {
      map['scheduled_minute_of_day'] = Variable<int>(
        scheduledMinuteOfDay.value,
      );
    }
    if (reminderMinuteOfDay.present) {
      map['reminder_minute_of_day'] = Variable<int>(reminderMinuteOfDay.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LongTermTaskRecordsCompanion(')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('checkMode: $checkMode, ')
          ..write('targetDurationSeconds: $targetDurationSeconds, ')
          ..write('targetDays: $targetDays, ')
          ..write('holidayPause: $holidayPause, ')
          ..write('scheduledMinuteOfDay: $scheduledMinuteOfDay, ')
          ..write('reminderMinuteOfDay: $reminderMinuteOfDay, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskScheduleRecordsTable extends TaskScheduleRecords
    with TableInfo<$TaskScheduleRecordsTable, TaskScheduleRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskScheduleRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleTypeMeta = const VerificationMeta(
    'scheduleType',
  );
  @override
  late final GeneratedColumn<String> scheduleType = GeneratedColumn<String>(
    'schedule_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekdaysMaskMeta = const VerificationMeta(
    'weekdaysMask',
  );
  @override
  late final GeneratedColumn<int> weekdaysMask = GeneratedColumn<int>(
    'weekdays_mask',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsOnMeta = const VerificationMeta(
    'startsOn',
  );
  @override
  late final GeneratedColumn<String> startsOn = GeneratedColumn<String>(
    'starts_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsOnMeta = const VerificationMeta('endsOn');
  @override
  late final GeneratedColumn<String> endsOn = GeneratedColumn<String>(
    'ends_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    userId,
    scheduleType,
    weekdaysMask,
    startsOn,
    endsOn,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_schedule_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskScheduleRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('schedule_type')) {
      context.handle(
        _scheduleTypeMeta,
        scheduleType.isAcceptableOrUnknown(
          data['schedule_type']!,
          _scheduleTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduleTypeMeta);
    }
    if (data.containsKey('weekdays_mask')) {
      context.handle(
        _weekdaysMaskMeta,
        weekdaysMask.isAcceptableOrUnknown(
          data['weekdays_mask']!,
          _weekdaysMaskMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekdaysMaskMeta);
    }
    if (data.containsKey('starts_on')) {
      context.handle(
        _startsOnMeta,
        startsOn.isAcceptableOrUnknown(data['starts_on']!, _startsOnMeta),
      );
    } else if (isInserting) {
      context.missing(_startsOnMeta);
    }
    if (data.containsKey('ends_on')) {
      context.handle(
        _endsOnMeta,
        endsOn.isAcceptableOrUnknown(data['ends_on']!, _endsOnMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskScheduleRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskScheduleRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      scheduleType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_type'],
      )!,
      weekdaysMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekdays_mask'],
      )!,
      startsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}starts_on'],
      )!,
      endsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ends_on'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TaskScheduleRecordsTable createAlias(String alias) {
    return $TaskScheduleRecordsTable(attachedDatabase, alias);
  }
}

class TaskScheduleRecord extends DataClass
    implements Insertable<TaskScheduleRecord> {
  final String id;
  final String taskId;
  final String userId;
  final String scheduleType;
  final int weekdaysMask;
  final String startsOn;
  final String? endsOn;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TaskScheduleRecord({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.scheduleType,
    required this.weekdaysMask,
    required this.startsOn,
    this.endsOn,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    map['schedule_type'] = Variable<String>(scheduleType);
    map['weekdays_mask'] = Variable<int>(weekdaysMask);
    map['starts_on'] = Variable<String>(startsOn);
    if (!nullToAbsent || endsOn != null) {
      map['ends_on'] = Variable<String>(endsOn);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TaskScheduleRecordsCompanion toCompanion(bool nullToAbsent) {
    return TaskScheduleRecordsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      userId: Value(userId),
      scheduleType: Value(scheduleType),
      weekdaysMask: Value(weekdaysMask),
      startsOn: Value(startsOn),
      endsOn: endsOn == null && nullToAbsent
          ? const Value.absent()
          : Value(endsOn),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TaskScheduleRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskScheduleRecord(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      scheduleType: serializer.fromJson<String>(json['scheduleType']),
      weekdaysMask: serializer.fromJson<int>(json['weekdaysMask']),
      startsOn: serializer.fromJson<String>(json['startsOn']),
      endsOn: serializer.fromJson<String?>(json['endsOn']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'scheduleType': serializer.toJson<String>(scheduleType),
      'weekdaysMask': serializer.toJson<int>(weekdaysMask),
      'startsOn': serializer.toJson<String>(startsOn),
      'endsOn': serializer.toJson<String?>(endsOn),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TaskScheduleRecord copyWith({
    String? id,
    String? taskId,
    String? userId,
    String? scheduleType,
    int? weekdaysMask,
    String? startsOn,
    Value<String?> endsOn = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TaskScheduleRecord(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    scheduleType: scheduleType ?? this.scheduleType,
    weekdaysMask: weekdaysMask ?? this.weekdaysMask,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn.present ? endsOn.value : this.endsOn,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TaskScheduleRecord copyWithCompanion(TaskScheduleRecordsCompanion data) {
    return TaskScheduleRecord(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      scheduleType: data.scheduleType.present
          ? data.scheduleType.value
          : this.scheduleType,
      weekdaysMask: data.weekdaysMask.present
          ? data.weekdaysMask.value
          : this.weekdaysMask,
      startsOn: data.startsOn.present ? data.startsOn.value : this.startsOn,
      endsOn: data.endsOn.present ? data.endsOn.value : this.endsOn,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskScheduleRecord(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('scheduleType: $scheduleType, ')
          ..write('weekdaysMask: $weekdaysMask, ')
          ..write('startsOn: $startsOn, ')
          ..write('endsOn: $endsOn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    userId,
    scheduleType,
    weekdaysMask,
    startsOn,
    endsOn,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskScheduleRecord &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.scheduleType == this.scheduleType &&
          other.weekdaysMask == this.weekdaysMask &&
          other.startsOn == this.startsOn &&
          other.endsOn == this.endsOn &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TaskScheduleRecordsCompanion extends UpdateCompanion<TaskScheduleRecord> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> userId;
  final Value<String> scheduleType;
  final Value<int> weekdaysMask;
  final Value<String> startsOn;
  final Value<String?> endsOn;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TaskScheduleRecordsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.scheduleType = const Value.absent(),
    this.weekdaysMask = const Value.absent(),
    this.startsOn = const Value.absent(),
    this.endsOn = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskScheduleRecordsCompanion.insert({
    required String id,
    required String taskId,
    required String userId,
    required String scheduleType,
    required int weekdaysMask,
    required String startsOn,
    this.endsOn = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       userId = Value(userId),
       scheduleType = Value(scheduleType),
       weekdaysMask = Value(weekdaysMask),
       startsOn = Value(startsOn),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskScheduleRecord> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<String>? scheduleType,
    Expression<int>? weekdaysMask,
    Expression<String>? startsOn,
    Expression<String>? endsOn,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (scheduleType != null) 'schedule_type': scheduleType,
      if (weekdaysMask != null) 'weekdays_mask': weekdaysMask,
      if (startsOn != null) 'starts_on': startsOn,
      if (endsOn != null) 'ends_on': endsOn,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskScheduleRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? userId,
    Value<String>? scheduleType,
    Value<int>? weekdaysMask,
    Value<String>? startsOn,
    Value<String?>? endsOn,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TaskScheduleRecordsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      scheduleType: scheduleType ?? this.scheduleType,
      weekdaysMask: weekdaysMask ?? this.weekdaysMask,
      startsOn: startsOn ?? this.startsOn,
      endsOn: endsOn ?? this.endsOn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (scheduleType.present) {
      map['schedule_type'] = Variable<String>(scheduleType.value);
    }
    if (weekdaysMask.present) {
      map['weekdays_mask'] = Variable<int>(weekdaysMask.value);
    }
    if (startsOn.present) {
      map['starts_on'] = Variable<String>(startsOn.value);
    }
    if (endsOn.present) {
      map['ends_on'] = Variable<String>(endsOn.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskScheduleRecordsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('scheduleType: $scheduleType, ')
          ..write('weekdaysMask: $weekdaysMask, ')
          ..write('startsOn: $startsOn, ')
          ..write('endsOn: $endsOn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OneTimeReminderRecordsTable extends OneTimeReminderRecords
    with TableInfo<$OneTimeReminderRecordsTable, OneTimeReminderRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OneTimeReminderRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasScheduledDateMeta = const VerificationMeta(
    'hasScheduledDate',
  );
  @override
  late final GeneratedColumn<bool> hasScheduledDate = GeneratedColumn<bool>(
    'has_scheduled_date',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_scheduled_date" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _remindBeforeMinutesMeta =
      const VerificationMeta('remindBeforeMinutes');
  @override
  late final GeneratedColumn<int> remindBeforeMinutes = GeneratedColumn<int>(
    'remind_before_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isTimedMeta = const VerificationMeta(
    'isTimed',
  );
  @override
  late final GeneratedColumn<bool> isTimed = GeneratedColumn<bool>(
    'is_timed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_timed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    userId,
    scheduledAt,
    hasScheduledDate,
    remindBeforeMinutes,
    isTimed,
    completedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'one_time_reminder_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<OneTimeReminderRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('has_scheduled_date')) {
      context.handle(
        _hasScheduledDateMeta,
        hasScheduledDate.isAcceptableOrUnknown(
          data['has_scheduled_date']!,
          _hasScheduledDateMeta,
        ),
      );
    }
    if (data.containsKey('remind_before_minutes')) {
      context.handle(
        _remindBeforeMinutesMeta,
        remindBeforeMinutes.isAcceptableOrUnknown(
          data['remind_before_minutes']!,
          _remindBeforeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('is_timed')) {
      context.handle(
        _isTimedMeta,
        isTimed.isAcceptableOrUnknown(data['is_timed']!, _isTimedMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  OneTimeReminderRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OneTimeReminderRecord(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
      hasScheduledDate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_scheduled_date'],
      )!,
      remindBeforeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_before_minutes'],
      ),
      isTimed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_timed'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OneTimeReminderRecordsTable createAlias(String alias) {
    return $OneTimeReminderRecordsTable(attachedDatabase, alias);
  }
}

class OneTimeReminderRecord extends DataClass
    implements Insertable<OneTimeReminderRecord> {
  final String taskId;
  final String userId;
  final DateTime scheduledAt;
  final bool hasScheduledDate;
  final int? remindBeforeMinutes;
  final bool isTimed;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const OneTimeReminderRecord({
    required this.taskId,
    required this.userId,
    required this.scheduledAt,
    required this.hasScheduledDate,
    this.remindBeforeMinutes,
    required this.isTimed,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    map['has_scheduled_date'] = Variable<bool>(hasScheduledDate);
    if (!nullToAbsent || remindBeforeMinutes != null) {
      map['remind_before_minutes'] = Variable<int>(remindBeforeMinutes);
    }
    map['is_timed'] = Variable<bool>(isTimed);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OneTimeReminderRecordsCompanion toCompanion(bool nullToAbsent) {
    return OneTimeReminderRecordsCompanion(
      taskId: Value(taskId),
      userId: Value(userId),
      scheduledAt: Value(scheduledAt),
      hasScheduledDate: Value(hasScheduledDate),
      remindBeforeMinutes: remindBeforeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(remindBeforeMinutes),
      isTimed: Value(isTimed),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OneTimeReminderRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OneTimeReminderRecord(
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      hasScheduledDate: serializer.fromJson<bool>(json['hasScheduledDate']),
      remindBeforeMinutes: serializer.fromJson<int?>(
        json['remindBeforeMinutes'],
      ),
      isTimed: serializer.fromJson<bool>(json['isTimed']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'hasScheduledDate': serializer.toJson<bool>(hasScheduledDate),
      'remindBeforeMinutes': serializer.toJson<int?>(remindBeforeMinutes),
      'isTimed': serializer.toJson<bool>(isTimed),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OneTimeReminderRecord copyWith({
    String? taskId,
    String? userId,
    DateTime? scheduledAt,
    bool? hasScheduledDate,
    Value<int?> remindBeforeMinutes = const Value.absent(),
    bool? isTimed,
    Value<DateTime?> completedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => OneTimeReminderRecord(
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    hasScheduledDate: hasScheduledDate ?? this.hasScheduledDate,
    remindBeforeMinutes: remindBeforeMinutes.present
        ? remindBeforeMinutes.value
        : this.remindBeforeMinutes,
    isTimed: isTimed ?? this.isTimed,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OneTimeReminderRecord copyWithCompanion(
    OneTimeReminderRecordsCompanion data,
  ) {
    return OneTimeReminderRecord(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      hasScheduledDate: data.hasScheduledDate.present
          ? data.hasScheduledDate.value
          : this.hasScheduledDate,
      remindBeforeMinutes: data.remindBeforeMinutes.present
          ? data.remindBeforeMinutes.value
          : this.remindBeforeMinutes,
      isTimed: data.isTimed.present ? data.isTimed.value : this.isTimed,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OneTimeReminderRecord(')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('hasScheduledDate: $hasScheduledDate, ')
          ..write('remindBeforeMinutes: $remindBeforeMinutes, ')
          ..write('isTimed: $isTimed, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    userId,
    scheduledAt,
    hasScheduledDate,
    remindBeforeMinutes,
    isTimed,
    completedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OneTimeReminderRecord &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.scheduledAt == this.scheduledAt &&
          other.hasScheduledDate == this.hasScheduledDate &&
          other.remindBeforeMinutes == this.remindBeforeMinutes &&
          other.isTimed == this.isTimed &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OneTimeReminderRecordsCompanion
    extends UpdateCompanion<OneTimeReminderRecord> {
  final Value<String> taskId;
  final Value<String> userId;
  final Value<DateTime> scheduledAt;
  final Value<bool> hasScheduledDate;
  final Value<int?> remindBeforeMinutes;
  final Value<bool> isTimed;
  final Value<DateTime?> completedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const OneTimeReminderRecordsCompanion({
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.hasScheduledDate = const Value.absent(),
    this.remindBeforeMinutes = const Value.absent(),
    this.isTimed = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OneTimeReminderRecordsCompanion.insert({
    required String taskId,
    required String userId,
    required DateTime scheduledAt,
    this.hasScheduledDate = const Value.absent(),
    this.remindBeforeMinutes = const Value.absent(),
    this.isTimed = const Value.absent(),
    this.completedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       userId = Value(userId),
       scheduledAt = Value(scheduledAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<OneTimeReminderRecord> custom({
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<DateTime>? scheduledAt,
    Expression<bool>? hasScheduledDate,
    Expression<int>? remindBeforeMinutes,
    Expression<bool>? isTimed,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (hasScheduledDate != null) 'has_scheduled_date': hasScheduledDate,
      if (remindBeforeMinutes != null)
        'remind_before_minutes': remindBeforeMinutes,
      if (isTimed != null) 'is_timed': isTimed,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OneTimeReminderRecordsCompanion copyWith({
    Value<String>? taskId,
    Value<String>? userId,
    Value<DateTime>? scheduledAt,
    Value<bool>? hasScheduledDate,
    Value<int?>? remindBeforeMinutes,
    Value<bool>? isTimed,
    Value<DateTime?>? completedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return OneTimeReminderRecordsCompanion(
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      hasScheduledDate: hasScheduledDate ?? this.hasScheduledDate,
      remindBeforeMinutes: remindBeforeMinutes ?? this.remindBeforeMinutes,
      isTimed: isTimed ?? this.isTimed,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (hasScheduledDate.present) {
      map['has_scheduled_date'] = Variable<bool>(hasScheduledDate.value);
    }
    if (remindBeforeMinutes.present) {
      map['remind_before_minutes'] = Variable<int>(remindBeforeMinutes.value);
    }
    if (isTimed.present) {
      map['is_timed'] = Variable<bool>(isTimed.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OneTimeReminderRecordsCompanion(')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('hasScheduledDate: $hasScheduledDate, ')
          ..write('remindBeforeMinutes: $remindBeforeMinutes, ')
          ..write('isTimed: $isTimed, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskCompletionRecordsTable extends TaskCompletionRecords
    with TableInfo<$TaskCompletionRecordsTable, TaskCompletionRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskCompletionRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualDurationSecondsMeta =
      const VerificationMeta('actualDurationSeconds');
  @override
  late final GeneratedColumn<int> actualDurationSeconds = GeneratedColumn<int>(
    'actual_duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _progressPercentMeta = const VerificationMeta(
    'progressPercent',
  );
  @override
  late final GeneratedColumn<double> progressPercent = GeneratedColumn<double>(
    'progress_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _targetReachedMeta = const VerificationMeta(
    'targetReached',
  );
  @override
  late final GeneratedColumn<bool> targetReached = GeneratedColumn<bool>(
    'target_reached',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("target_reached" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isSuccessMeta = const VerificationMeta(
    'isSuccess',
  );
  @override
  late final GeneratedColumn<bool> isSuccess = GeneratedColumn<bool>(
    'is_success',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_success" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _exclusionReasonMeta = const VerificationMeta(
    'exclusionReason',
  );
  @override
  late final GeneratedColumn<String> exclusionReason = GeneratedColumn<String>(
    'exclusion_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    userId,
    localDate,
    actualDurationSeconds,
    progressPercent,
    targetReached,
    isSuccess,
    exclusionReason,
    completedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_completion_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskCompletionRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('actual_duration_seconds')) {
      context.handle(
        _actualDurationSecondsMeta,
        actualDurationSeconds.isAcceptableOrUnknown(
          data['actual_duration_seconds']!,
          _actualDurationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('progress_percent')) {
      context.handle(
        _progressPercentMeta,
        progressPercent.isAcceptableOrUnknown(
          data['progress_percent']!,
          _progressPercentMeta,
        ),
      );
    }
    if (data.containsKey('target_reached')) {
      context.handle(
        _targetReachedMeta,
        targetReached.isAcceptableOrUnknown(
          data['target_reached']!,
          _targetReachedMeta,
        ),
      );
    }
    if (data.containsKey('is_success')) {
      context.handle(
        _isSuccessMeta,
        isSuccess.isAcceptableOrUnknown(data['is_success']!, _isSuccessMeta),
      );
    }
    if (data.containsKey('exclusion_reason')) {
      context.handle(
        _exclusionReasonMeta,
        exclusionReason.isAcceptableOrUnknown(
          data['exclusion_reason']!,
          _exclusionReasonMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {taskId, localDate},
  ];
  @override
  TaskCompletionRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskCompletionRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      actualDurationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}actual_duration_seconds'],
      )!,
      progressPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress_percent'],
      )!,
      targetReached: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}target_reached'],
      )!,
      isSuccess: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_success'],
      )!,
      exclusionReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exclusion_reason'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TaskCompletionRecordsTable createAlias(String alias) {
    return $TaskCompletionRecordsTable(attachedDatabase, alias);
  }
}

class TaskCompletionRecord extends DataClass
    implements Insertable<TaskCompletionRecord> {
  final String id;
  final String taskId;
  final String userId;
  final String localDate;
  final int actualDurationSeconds;
  final double progressPercent;
  final bool targetReached;
  final bool isSuccess;
  final String? exclusionReason;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TaskCompletionRecord({
    required this.id,
    required this.taskId,
    required this.userId,
    required this.localDate,
    required this.actualDurationSeconds,
    required this.progressPercent,
    required this.targetReached,
    required this.isSuccess,
    this.exclusionReason,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    map['local_date'] = Variable<String>(localDate);
    map['actual_duration_seconds'] = Variable<int>(actualDurationSeconds);
    map['progress_percent'] = Variable<double>(progressPercent);
    map['target_reached'] = Variable<bool>(targetReached);
    map['is_success'] = Variable<bool>(isSuccess);
    if (!nullToAbsent || exclusionReason != null) {
      map['exclusion_reason'] = Variable<String>(exclusionReason);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TaskCompletionRecordsCompanion toCompanion(bool nullToAbsent) {
    return TaskCompletionRecordsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      userId: Value(userId),
      localDate: Value(localDate),
      actualDurationSeconds: Value(actualDurationSeconds),
      progressPercent: Value(progressPercent),
      targetReached: Value(targetReached),
      isSuccess: Value(isSuccess),
      exclusionReason: exclusionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(exclusionReason),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TaskCompletionRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskCompletionRecord(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      localDate: serializer.fromJson<String>(json['localDate']),
      actualDurationSeconds: serializer.fromJson<int>(
        json['actualDurationSeconds'],
      ),
      progressPercent: serializer.fromJson<double>(json['progressPercent']),
      targetReached: serializer.fromJson<bool>(json['targetReached']),
      isSuccess: serializer.fromJson<bool>(json['isSuccess']),
      exclusionReason: serializer.fromJson<String?>(json['exclusionReason']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'localDate': serializer.toJson<String>(localDate),
      'actualDurationSeconds': serializer.toJson<int>(actualDurationSeconds),
      'progressPercent': serializer.toJson<double>(progressPercent),
      'targetReached': serializer.toJson<bool>(targetReached),
      'isSuccess': serializer.toJson<bool>(isSuccess),
      'exclusionReason': serializer.toJson<String?>(exclusionReason),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TaskCompletionRecord copyWith({
    String? id,
    String? taskId,
    String? userId,
    String? localDate,
    int? actualDurationSeconds,
    double? progressPercent,
    bool? targetReached,
    bool? isSuccess,
    Value<String?> exclusionReason = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TaskCompletionRecord(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    localDate: localDate ?? this.localDate,
    actualDurationSeconds: actualDurationSeconds ?? this.actualDurationSeconds,
    progressPercent: progressPercent ?? this.progressPercent,
    targetReached: targetReached ?? this.targetReached,
    isSuccess: isSuccess ?? this.isSuccess,
    exclusionReason: exclusionReason.present
        ? exclusionReason.value
        : this.exclusionReason,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TaskCompletionRecord copyWithCompanion(TaskCompletionRecordsCompanion data) {
    return TaskCompletionRecord(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      actualDurationSeconds: data.actualDurationSeconds.present
          ? data.actualDurationSeconds.value
          : this.actualDurationSeconds,
      progressPercent: data.progressPercent.present
          ? data.progressPercent.value
          : this.progressPercent,
      targetReached: data.targetReached.present
          ? data.targetReached.value
          : this.targetReached,
      isSuccess: data.isSuccess.present ? data.isSuccess.value : this.isSuccess,
      exclusionReason: data.exclusionReason.present
          ? data.exclusionReason.value
          : this.exclusionReason,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskCompletionRecord(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('localDate: $localDate, ')
          ..write('actualDurationSeconds: $actualDurationSeconds, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('targetReached: $targetReached, ')
          ..write('isSuccess: $isSuccess, ')
          ..write('exclusionReason: $exclusionReason, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    userId,
    localDate,
    actualDurationSeconds,
    progressPercent,
    targetReached,
    isSuccess,
    exclusionReason,
    completedAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskCompletionRecord &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.localDate == this.localDate &&
          other.actualDurationSeconds == this.actualDurationSeconds &&
          other.progressPercent == this.progressPercent &&
          other.targetReached == this.targetReached &&
          other.isSuccess == this.isSuccess &&
          other.exclusionReason == this.exclusionReason &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TaskCompletionRecordsCompanion
    extends UpdateCompanion<TaskCompletionRecord> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> userId;
  final Value<String> localDate;
  final Value<int> actualDurationSeconds;
  final Value<double> progressPercent;
  final Value<bool> targetReached;
  final Value<bool> isSuccess;
  final Value<String?> exclusionReason;
  final Value<DateTime?> completedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TaskCompletionRecordsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.actualDurationSeconds = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.targetReached = const Value.absent(),
    this.isSuccess = const Value.absent(),
    this.exclusionReason = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskCompletionRecordsCompanion.insert({
    required String id,
    required String taskId,
    required String userId,
    required String localDate,
    this.actualDurationSeconds = const Value.absent(),
    this.progressPercent = const Value.absent(),
    this.targetReached = const Value.absent(),
    this.isSuccess = const Value.absent(),
    this.exclusionReason = const Value.absent(),
    this.completedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       userId = Value(userId),
       localDate = Value(localDate),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TaskCompletionRecord> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<String>? localDate,
    Expression<int>? actualDurationSeconds,
    Expression<double>? progressPercent,
    Expression<bool>? targetReached,
    Expression<bool>? isSuccess,
    Expression<String>? exclusionReason,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (localDate != null) 'local_date': localDate,
      if (actualDurationSeconds != null)
        'actual_duration_seconds': actualDurationSeconds,
      if (progressPercent != null) 'progress_percent': progressPercent,
      if (targetReached != null) 'target_reached': targetReached,
      if (isSuccess != null) 'is_success': isSuccess,
      if (exclusionReason != null) 'exclusion_reason': exclusionReason,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskCompletionRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? userId,
    Value<String>? localDate,
    Value<int>? actualDurationSeconds,
    Value<double>? progressPercent,
    Value<bool>? targetReached,
    Value<bool>? isSuccess,
    Value<String?>? exclusionReason,
    Value<DateTime?>? completedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TaskCompletionRecordsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      localDate: localDate ?? this.localDate,
      actualDurationSeconds:
          actualDurationSeconds ?? this.actualDurationSeconds,
      progressPercent: progressPercent ?? this.progressPercent,
      targetReached: targetReached ?? this.targetReached,
      isSuccess: isSuccess ?? this.isSuccess,
      exclusionReason: exclusionReason ?? this.exclusionReason,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (actualDurationSeconds.present) {
      map['actual_duration_seconds'] = Variable<int>(
        actualDurationSeconds.value,
      );
    }
    if (progressPercent.present) {
      map['progress_percent'] = Variable<double>(progressPercent.value);
    }
    if (targetReached.present) {
      map['target_reached'] = Variable<bool>(targetReached.value);
    }
    if (isSuccess.present) {
      map['is_success'] = Variable<bool>(isSuccess.value);
    }
    if (exclusionReason.present) {
      map['exclusion_reason'] = Variable<String>(exclusionReason.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskCompletionRecordsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('localDate: $localDate, ')
          ..write('actualDurationSeconds: $actualDurationSeconds, ')
          ..write('progressPercent: $progressPercent, ')
          ..write('targetReached: $targetReached, ')
          ..write('isSuccess: $isSuccess, ')
          ..write('exclusionReason: $exclusionReason, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimerSessionRecordsTable extends TimerSessionRecords
    with TableInfo<$TimerSessionRecordsTable, TimerSessionRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimerSessionRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _logicalDateMeta = const VerificationMeta(
    'logicalDate',
  );
  @override
  late final GeneratedColumn<String> logicalDate = GeneratedColumn<String>(
    'logical_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    userId,
    tagId,
    startedAt,
    logicalDate,
    endedAt,
    durationSeconds,
    state,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'timer_session_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TimerSessionRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('logical_date')) {
      context.handle(
        _logicalDateMeta,
        logicalDate.isAcceptableOrUnknown(
          data['logical_date']!,
          _logicalDateMeta,
        ),
      );
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimerSessionRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimerSessionRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      logicalDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logical_date'],
      ),
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TimerSessionRecordsTable createAlias(String alias) {
    return $TimerSessionRecordsTable(attachedDatabase, alias);
  }
}

class TimerSessionRecord extends DataClass
    implements Insertable<TimerSessionRecord> {
  final String id;
  final String taskId;
  final String userId;
  final String? tagId;
  final DateTime startedAt;
  final String? logicalDate;
  final DateTime? endedAt;
  final int durationSeconds;
  final String state;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TimerSessionRecord({
    required this.id,
    required this.taskId,
    required this.userId,
    this.tagId,
    required this.startedAt,
    this.logicalDate,
    this.endedAt,
    required this.durationSeconds,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || tagId != null) {
      map['tag_id'] = Variable<String>(tagId);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || logicalDate != null) {
      map['logical_date'] = Variable<String>(logicalDate);
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TimerSessionRecordsCompanion toCompanion(bool nullToAbsent) {
    return TimerSessionRecordsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      userId: Value(userId),
      tagId: tagId == null && nullToAbsent
          ? const Value.absent()
          : Value(tagId),
      startedAt: Value(startedAt),
      logicalDate: logicalDate == null && nullToAbsent
          ? const Value.absent()
          : Value(logicalDate),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      durationSeconds: Value(durationSeconds),
      state: Value(state),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TimerSessionRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimerSessionRecord(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      tagId: serializer.fromJson<String?>(json['tagId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      logicalDate: serializer.fromJson<String?>(json['logicalDate']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'tagId': serializer.toJson<String?>(tagId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'logicalDate': serializer.toJson<String?>(logicalDate),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'state': serializer.toJson<String>(state),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TimerSessionRecord copyWith({
    String? id,
    String? taskId,
    String? userId,
    Value<String?> tagId = const Value.absent(),
    DateTime? startedAt,
    Value<String?> logicalDate = const Value.absent(),
    Value<DateTime?> endedAt = const Value.absent(),
    int? durationSeconds,
    String? state,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TimerSessionRecord(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    tagId: tagId.present ? tagId.value : this.tagId,
    startedAt: startedAt ?? this.startedAt,
    logicalDate: logicalDate.present ? logicalDate.value : this.logicalDate,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TimerSessionRecord copyWithCompanion(TimerSessionRecordsCompanion data) {
    return TimerSessionRecord(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      logicalDate: data.logicalDate.present
          ? data.logicalDate.value
          : this.logicalDate,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimerSessionRecord(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('tagId: $tagId, ')
          ..write('startedAt: $startedAt, ')
          ..write('logicalDate: $logicalDate, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskId,
    userId,
    tagId,
    startedAt,
    logicalDate,
    endedAt,
    durationSeconds,
    state,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimerSessionRecord &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.tagId == this.tagId &&
          other.startedAt == this.startedAt &&
          other.logicalDate == this.logicalDate &&
          other.endedAt == this.endedAt &&
          other.durationSeconds == this.durationSeconds &&
          other.state == this.state &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TimerSessionRecordsCompanion extends UpdateCompanion<TimerSessionRecord> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> userId;
  final Value<String?> tagId;
  final Value<DateTime> startedAt;
  final Value<String?> logicalDate;
  final Value<DateTime?> endedAt;
  final Value<int> durationSeconds;
  final Value<String> state;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TimerSessionRecordsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.logicalDate = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimerSessionRecordsCompanion.insert({
    required String id,
    required String taskId,
    required String userId,
    this.tagId = const Value.absent(),
    required DateTime startedAt,
    this.logicalDate = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    required String state,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       userId = Value(userId),
       startedAt = Value(startedAt),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TimerSessionRecord> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<String>? tagId,
    Expression<DateTime>? startedAt,
    Expression<String>? logicalDate,
    Expression<DateTime>? endedAt,
    Expression<int>? durationSeconds,
    Expression<String>? state,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (tagId != null) 'tag_id': tagId,
      if (startedAt != null) 'started_at': startedAt,
      if (logicalDate != null) 'logical_date': logicalDate,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimerSessionRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? userId,
    Value<String?>? tagId,
    Value<DateTime>? startedAt,
    Value<String?>? logicalDate,
    Value<DateTime?>? endedAt,
    Value<int>? durationSeconds,
    Value<String>? state,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TimerSessionRecordsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      tagId: tagId ?? this.tagId,
      startedAt: startedAt ?? this.startedAt,
      logicalDate: logicalDate ?? this.logicalDate,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (logicalDate.present) {
      map['logical_date'] = Variable<String>(logicalDate.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimerSessionRecordsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('tagId: $tagId, ')
          ..write('startedAt: $startedAt, ')
          ..write('logicalDate: $logicalDate, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskRevisionRecordsTable extends TaskRevisionRecords
    with TableInfo<$TaskRevisionRecordsTable, TaskRevisionRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskRevisionRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _beforeJsonMeta = const VerificationMeta(
    'beforeJson',
  );
  @override
  late final GeneratedColumn<String> beforeJson = GeneratedColumn<String>(
    'before_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _afterJsonMeta = const VerificationMeta(
    'afterJson',
  );
  @override
  late final GeneratedColumn<String> afterJson = GeneratedColumn<String>(
    'after_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskId,
    userId,
    beforeJson,
    afterJson,
    changedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_revision_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRevisionRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('before_json')) {
      context.handle(
        _beforeJsonMeta,
        beforeJson.isAcceptableOrUnknown(data['before_json']!, _beforeJsonMeta),
      );
    }
    if (data.containsKey('after_json')) {
      context.handle(
        _afterJsonMeta,
        afterJson.isAcceptableOrUnknown(data['after_json']!, _afterJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_afterJsonMeta);
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_changedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRevisionRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRevisionRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      beforeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_json'],
      ),
      afterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_json'],
      )!,
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
    );
  }

  @override
  $TaskRevisionRecordsTable createAlias(String alias) {
    return $TaskRevisionRecordsTable(attachedDatabase, alias);
  }
}

class TaskRevisionRecord extends DataClass
    implements Insertable<TaskRevisionRecord> {
  final String id;
  final String taskId;
  final String userId;
  final String? beforeJson;
  final String afterJson;
  final DateTime changedAt;
  const TaskRevisionRecord({
    required this.id,
    required this.taskId,
    required this.userId,
    this.beforeJson,
    required this.afterJson,
    required this.changedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || beforeJson != null) {
      map['before_json'] = Variable<String>(beforeJson);
    }
    map['after_json'] = Variable<String>(afterJson);
    map['changed_at'] = Variable<DateTime>(changedAt);
    return map;
  }

  TaskRevisionRecordsCompanion toCompanion(bool nullToAbsent) {
    return TaskRevisionRecordsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      userId: Value(userId),
      beforeJson: beforeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeJson),
      afterJson: Value(afterJson),
      changedAt: Value(changedAt),
    );
  }

  factory TaskRevisionRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRevisionRecord(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      beforeJson: serializer.fromJson<String?>(json['beforeJson']),
      afterJson: serializer.fromJson<String>(json['afterJson']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'beforeJson': serializer.toJson<String?>(beforeJson),
      'afterJson': serializer.toJson<String>(afterJson),
      'changedAt': serializer.toJson<DateTime>(changedAt),
    };
  }

  TaskRevisionRecord copyWith({
    String? id,
    String? taskId,
    String? userId,
    Value<String?> beforeJson = const Value.absent(),
    String? afterJson,
    DateTime? changedAt,
  }) => TaskRevisionRecord(
    id: id ?? this.id,
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    beforeJson: beforeJson.present ? beforeJson.value : this.beforeJson,
    afterJson: afterJson ?? this.afterJson,
    changedAt: changedAt ?? this.changedAt,
  );
  TaskRevisionRecord copyWithCompanion(TaskRevisionRecordsCompanion data) {
    return TaskRevisionRecord(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      beforeJson: data.beforeJson.present
          ? data.beforeJson.value
          : this.beforeJson,
      afterJson: data.afterJson.present ? data.afterJson.value : this.afterJson,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRevisionRecord(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('changedAt: $changedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, taskId, userId, beforeJson, afterJson, changedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRevisionRecord &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.beforeJson == this.beforeJson &&
          other.afterJson == this.afterJson &&
          other.changedAt == this.changedAt);
}

class TaskRevisionRecordsCompanion extends UpdateCompanion<TaskRevisionRecord> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<String> userId;
  final Value<String?> beforeJson;
  final Value<String> afterJson;
  final Value<DateTime> changedAt;
  final Value<int> rowid;
  const TaskRevisionRecordsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.beforeJson = const Value.absent(),
    this.afterJson = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskRevisionRecordsCompanion.insert({
    required String id,
    required String taskId,
    required String userId,
    this.beforeJson = const Value.absent(),
    required String afterJson,
    required DateTime changedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskId = Value(taskId),
       userId = Value(userId),
       afterJson = Value(afterJson),
       changedAt = Value(changedAt);
  static Insertable<TaskRevisionRecord> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<String>? beforeJson,
    Expression<String>? afterJson,
    Expression<DateTime>? changedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (beforeJson != null) 'before_json': beforeJson,
      if (afterJson != null) 'after_json': afterJson,
      if (changedAt != null) 'changed_at': changedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskRevisionRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? taskId,
    Value<String>? userId,
    Value<String?>? beforeJson,
    Value<String>? afterJson,
    Value<DateTime>? changedAt,
    Value<int>? rowid,
  }) {
    return TaskRevisionRecordsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      beforeJson: beforeJson ?? this.beforeJson,
      afterJson: afterJson ?? this.afterJson,
      changedAt: changedAt ?? this.changedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (beforeJson.present) {
      map['before_json'] = Variable<String>(beforeJson.value);
    }
    if (afterJson.present) {
      map['after_json'] = Variable<String>(afterJson.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskRevisionRecordsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('beforeJson: $beforeJson, ')
          ..write('afterJson: $afterJson, ')
          ..write('changedAt: $changedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsTable extends SyncOperations
    with TableInfo<$SyncOperationsTable, SyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    entityType,
    entityId,
    operation,
    payloadJson,
    status,
    retryCount,
    lastError,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncOperationsTable createAlias(String alias) {
    return $SyncOperationsTable(attachedDatabase, alias);
  }
}

class SyncOperation extends DataClass implements Insertable<SyncOperation> {
  final String id;
  final String? userId;
  final String entityType;
  final String entityId;
  final String operation;
  final String payloadJson;
  final String status;
  final int retryCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SyncOperation({
    required this.id,
    this.userId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    required this.status,
    required this.retryCount,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload_json'] = Variable<String>(payloadJson);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return SyncOperationsCompanion(
      id: Value(id),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payloadJson: Value(payloadJson),
      status: Value(status),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOperation(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String?>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String?>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncOperation copyWith({
    String? id,
    Value<String?> userId = const Value.absent(),
    String? entityType,
    String? entityId,
    String? operation,
    String? payloadJson,
    String? status,
    int? retryCount,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SyncOperation(
    id: id ?? this.id,
    userId: userId.present ? userId.value : this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payloadJson: payloadJson ?? this.payloadJson,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncOperation copyWithCompanion(SyncOperationsCompanion data) {
    return SyncOperation(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperation(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    entityType,
    entityId,
    operation,
    payloadJson,
    status,
    retryCount,
    lastError,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOperation &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SyncOperationsCompanion extends UpdateCompanion<SyncOperation> {
  final Value<String> id;
  final Value<String?> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payloadJson;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncOperationsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOperationsCompanion.insert({
    required String id,
    this.userId = const Value.absent(),
    required String entityType,
    required String entityId,
    required String operation,
    required String payloadJson,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SyncOperation> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOperationsCompanion copyWith({
    Value<String>? id,
    Value<String?>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payloadJson,
    Value<String>? status,
    Value<int>? retryCount,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncOperationsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSetting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagRecordsTable extends TagRecords
    with TableInfo<$TagRecordsTable, TagRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    colorValue,
    archived,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TagRecordsTable createAlias(String alias) {
    return $TagRecordsTable(attachedDatabase, alias);
  }
}

class TagRecord extends DataClass implements Insertable<TagRecord> {
  final String id;
  final String userId;
  final String name;
  final int colorValue;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  const TagRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.colorValue,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TagRecordsCompanion toCompanion(bool nullToAbsent) {
    return TagRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      colorValue: Value(colorValue),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory TagRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  TagRecord copyWith({
    String? id,
    String? userId,
    String? name,
    int? colorValue,
    bool? archived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => TagRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  TagRecord copyWithCompanion(TagRecordsCompanion data) {
    return TagRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, name, colorValue, archived, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TagRecordsCompanion extends UpdateCompanion<TagRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<bool> archived;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TagRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagRecordsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required int colorValue,
    this.archived = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       colorValue = Value(colorValue),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TagRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<bool>? archived,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (archived != null) 'archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<int>? colorValue,
    Value<bool>? archived,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return TagRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagRevisionRecordsTable extends TagRevisionRecords
    with TableInfo<$TagRevisionRecordsTable, TagRevisionRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagRevisionRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tag_records (id)',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tagId,
    userId,
    snapshotJson,
    changedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tag_revision_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRevisionRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotJsonMeta);
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_changedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRevisionRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRevisionRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      )!,
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
    );
  }

  @override
  $TagRevisionRecordsTable createAlias(String alias) {
    return $TagRevisionRecordsTable(attachedDatabase, alias);
  }
}

class TagRevisionRecord extends DataClass
    implements Insertable<TagRevisionRecord> {
  final String id;
  final String tagId;
  final String userId;
  final String snapshotJson;
  final DateTime changedAt;
  const TagRevisionRecord({
    required this.id,
    required this.tagId,
    required this.userId,
    required this.snapshotJson,
    required this.changedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tag_id'] = Variable<String>(tagId);
    map['user_id'] = Variable<String>(userId);
    map['snapshot_json'] = Variable<String>(snapshotJson);
    map['changed_at'] = Variable<DateTime>(changedAt);
    return map;
  }

  TagRevisionRecordsCompanion toCompanion(bool nullToAbsent) {
    return TagRevisionRecordsCompanion(
      id: Value(id),
      tagId: Value(tagId),
      userId: Value(userId),
      snapshotJson: Value(snapshotJson),
      changedAt: Value(changedAt),
    );
  }

  factory TagRevisionRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRevisionRecord(
      id: serializer.fromJson<String>(json['id']),
      tagId: serializer.fromJson<String>(json['tagId']),
      userId: serializer.fromJson<String>(json['userId']),
      snapshotJson: serializer.fromJson<String>(json['snapshotJson']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tagId': serializer.toJson<String>(tagId),
      'userId': serializer.toJson<String>(userId),
      'snapshotJson': serializer.toJson<String>(snapshotJson),
      'changedAt': serializer.toJson<DateTime>(changedAt),
    };
  }

  TagRevisionRecord copyWith({
    String? id,
    String? tagId,
    String? userId,
    String? snapshotJson,
    DateTime? changedAt,
  }) => TagRevisionRecord(
    id: id ?? this.id,
    tagId: tagId ?? this.tagId,
    userId: userId ?? this.userId,
    snapshotJson: snapshotJson ?? this.snapshotJson,
    changedAt: changedAt ?? this.changedAt,
  );
  TagRevisionRecord copyWithCompanion(TagRevisionRecordsCompanion data) {
    return TagRevisionRecord(
      id: data.id.present ? data.id.value : this.id,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      userId: data.userId.present ? data.userId.value : this.userId,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRevisionRecord(')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('userId: $userId, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('changedAt: $changedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, tagId, userId, snapshotJson, changedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRevisionRecord &&
          other.id == this.id &&
          other.tagId == this.tagId &&
          other.userId == this.userId &&
          other.snapshotJson == this.snapshotJson &&
          other.changedAt == this.changedAt);
}

class TagRevisionRecordsCompanion extends UpdateCompanion<TagRevisionRecord> {
  final Value<String> id;
  final Value<String> tagId;
  final Value<String> userId;
  final Value<String> snapshotJson;
  final Value<DateTime> changedAt;
  final Value<int> rowid;
  const TagRevisionRecordsCompanion({
    this.id = const Value.absent(),
    this.tagId = const Value.absent(),
    this.userId = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagRevisionRecordsCompanion.insert({
    required String id,
    required String tagId,
    required String userId,
    required String snapshotJson,
    required DateTime changedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       tagId = Value(tagId),
       userId = Value(userId),
       snapshotJson = Value(snapshotJson),
       changedAt = Value(changedAt);
  static Insertable<TagRevisionRecord> custom({
    Expression<String>? id,
    Expression<String>? tagId,
    Expression<String>? userId,
    Expression<String>? snapshotJson,
    Expression<DateTime>? changedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tagId != null) 'tag_id': tagId,
      if (userId != null) 'user_id': userId,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (changedAt != null) 'changed_at': changedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagRevisionRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? tagId,
    Value<String>? userId,
    Value<String>? snapshotJson,
    Value<DateTime>? changedAt,
    Value<int>? rowid,
  }) {
    return TagRevisionRecordsCompanion(
      id: id ?? this.id,
      tagId: tagId ?? this.tagId,
      userId: userId ?? this.userId,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      changedAt: changedAt ?? this.changedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagRevisionRecordsCompanion(')
          ..write('id: $id, ')
          ..write('tagId: $tagId, ')
          ..write('userId: $userId, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('changedAt: $changedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanRecordsTable extends PlanRecords
    with TableInfo<$PlanRecordsTable, PlanRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<String> goal = GeneratedColumn<String>(
    'goal',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startsOnMeta = const VerificationMeta(
    'startsOn',
  );
  @override
  late final GeneratedColumn<String> startsOn = GeneratedColumn<String>(
    'starts_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsOnMeta = const VerificationMeta('endsOn');
  @override
  late final GeneratedColumn<String> endsOn = GeneratedColumn<String>(
    'ends_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    type,
    colorValue,
    goal,
    startsOn,
    endsOn,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    }
    if (data.containsKey('starts_on')) {
      context.handle(
        _startsOnMeta,
        startsOn.isAcceptableOrUnknown(data['starts_on']!, _startsOnMeta),
      );
    } else if (isInserting) {
      context.missing(_startsOnMeta);
    }
    if (data.containsKey('ends_on')) {
      context.handle(
        _endsOnMeta,
        endsOn.isAcceptableOrUnknown(data['ends_on']!, _endsOnMeta),
      );
    } else if (isInserting) {
      context.missing(_endsOnMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlanRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal'],
      ),
      startsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}starts_on'],
      )!,
      endsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ends_on'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $PlanRecordsTable createAlias(String alias) {
    return $PlanRecordsTable(attachedDatabase, alias);
  }
}

class PlanRecord extends DataClass implements Insertable<PlanRecord> {
  final String id;
  final String userId;
  final String name;
  final String type;
  final int colorValue;
  final String? goal;
  final String startsOn;
  final String endsOn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const PlanRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.colorValue,
    this.goal,
    required this.startsOn,
    required this.endsOn,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['color_value'] = Variable<int>(colorValue);
    if (!nullToAbsent || goal != null) {
      map['goal'] = Variable<String>(goal);
    }
    map['starts_on'] = Variable<String>(startsOn);
    map['ends_on'] = Variable<String>(endsOn);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  PlanRecordsCompanion toCompanion(bool nullToAbsent) {
    return PlanRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      type: Value(type),
      colorValue: Value(colorValue),
      goal: goal == null && nullToAbsent ? const Value.absent() : Value(goal),
      startsOn: Value(startsOn),
      endsOn: Value(endsOn),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory PlanRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      goal: serializer.fromJson<String?>(json['goal']),
      startsOn: serializer.fromJson<String>(json['startsOn']),
      endsOn: serializer.fromJson<String>(json['endsOn']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'colorValue': serializer.toJson<int>(colorValue),
      'goal': serializer.toJson<String?>(goal),
      'startsOn': serializer.toJson<String>(startsOn),
      'endsOn': serializer.toJson<String>(endsOn),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  PlanRecord copyWith({
    String? id,
    String? userId,
    String? name,
    String? type,
    int? colorValue,
    Value<String?> goal = const Value.absent(),
    String? startsOn,
    String? endsOn,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => PlanRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    type: type ?? this.type,
    colorValue: colorValue ?? this.colorValue,
    goal: goal.present ? goal.value : this.goal,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn ?? this.endsOn,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  PlanRecord copyWithCompanion(PlanRecordsCompanion data) {
    return PlanRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      goal: data.goal.present ? data.goal.value : this.goal,
      startsOn: data.startsOn.present ? data.startsOn.value : this.startsOn,
      endsOn: data.endsOn.present ? data.endsOn.value : this.endsOn,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('colorValue: $colorValue, ')
          ..write('goal: $goal, ')
          ..write('startsOn: $startsOn, ')
          ..write('endsOn: $endsOn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    type,
    colorValue,
    goal,
    startsOn,
    endsOn,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.type == this.type &&
          other.colorValue == this.colorValue &&
          other.goal == this.goal &&
          other.startsOn == this.startsOn &&
          other.endsOn == this.endsOn &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class PlanRecordsCompanion extends UpdateCompanion<PlanRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> type;
  final Value<int> colorValue;
  final Value<String?> goal;
  final Value<String> startsOn;
  final Value<String> endsOn;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const PlanRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.goal = const Value.absent(),
    this.startsOn = const Value.absent(),
    this.endsOn = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanRecordsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required String type,
    required int colorValue,
    this.goal = const Value.absent(),
    required String startsOn,
    required String endsOn,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       type = Value(type),
       colorValue = Value(colorValue),
       startsOn = Value(startsOn),
       endsOn = Value(endsOn),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<int>? colorValue,
    Expression<String>? goal,
    Expression<String>? startsOn,
    Expression<String>? endsOn,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (colorValue != null) 'color_value': colorValue,
      if (goal != null) 'goal': goal,
      if (startsOn != null) 'starts_on': startsOn,
      if (endsOn != null) 'ends_on': endsOn,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? type,
    Value<int>? colorValue,
    Value<String?>? goal,
    Value<String>? startsOn,
    Value<String>? endsOn,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return PlanRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      colorValue: colorValue ?? this.colorValue,
      goal: goal ?? this.goal,
      startsOn: startsOn ?? this.startsOn,
      endsOn: endsOn ?? this.endsOn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (goal.present) {
      map['goal'] = Variable<String>(goal.value);
    }
    if (startsOn.present) {
      map['starts_on'] = Variable<String>(startsOn.value);
    }
    if (endsOn.present) {
      map['ends_on'] = Variable<String>(endsOn.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('colorValue: $colorValue, ')
          ..write('goal: $goal, ')
          ..write('startsOn: $startsOn, ')
          ..write('endsOn: $endsOn, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlanTaskRecordsTable extends PlanTaskRecords
    with TableInfo<$PlanTaskRecordsTable, PlanTaskRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanTaskRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES plan_records (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_tasks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    planId,
    taskId,
    userId,
    weight,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plan_task_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanTaskRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {planId, taskId};
  @override
  PlanTaskRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanTaskRecord(
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlanTaskRecordsTable createAlias(String alias) {
    return $PlanTaskRecordsTable(attachedDatabase, alias);
  }
}

class PlanTaskRecord extends DataClass implements Insertable<PlanTaskRecord> {
  final String planId;
  final String taskId;
  final String userId;
  final double weight;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PlanTaskRecord({
    required this.planId,
    required this.taskId,
    required this.userId,
    required this.weight,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['plan_id'] = Variable<String>(planId);
    map['task_id'] = Variable<String>(taskId);
    map['user_id'] = Variable<String>(userId);
    map['weight'] = Variable<double>(weight);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlanTaskRecordsCompanion toCompanion(bool nullToAbsent) {
    return PlanTaskRecordsCompanion(
      planId: Value(planId),
      taskId: Value(taskId),
      userId: Value(userId),
      weight: Value(weight),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlanTaskRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanTaskRecord(
      planId: serializer.fromJson<String>(json['planId']),
      taskId: serializer.fromJson<String>(json['taskId']),
      userId: serializer.fromJson<String>(json['userId']),
      weight: serializer.fromJson<double>(json['weight']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'planId': serializer.toJson<String>(planId),
      'taskId': serializer.toJson<String>(taskId),
      'userId': serializer.toJson<String>(userId),
      'weight': serializer.toJson<double>(weight),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlanTaskRecord copyWith({
    String? planId,
    String? taskId,
    String? userId,
    double? weight,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PlanTaskRecord(
    planId: planId ?? this.planId,
    taskId: taskId ?? this.taskId,
    userId: userId ?? this.userId,
    weight: weight ?? this.weight,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlanTaskRecord copyWithCompanion(PlanTaskRecordsCompanion data) {
    return PlanTaskRecord(
      planId: data.planId.present ? data.planId.value : this.planId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      userId: data.userId.present ? data.userId.value : this.userId,
      weight: data.weight.present ? data.weight.value : this.weight,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanTaskRecord(')
          ..write('planId: $planId, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('weight: $weight, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(planId, taskId, userId, weight, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanTaskRecord &&
          other.planId == this.planId &&
          other.taskId == this.taskId &&
          other.userId == this.userId &&
          other.weight == this.weight &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlanTaskRecordsCompanion extends UpdateCompanion<PlanTaskRecord> {
  final Value<String> planId;
  final Value<String> taskId;
  final Value<String> userId;
  final Value<double> weight;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlanTaskRecordsCompanion({
    this.planId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.userId = const Value.absent(),
    this.weight = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanTaskRecordsCompanion.insert({
    required String planId,
    required String taskId,
    required String userId,
    this.weight = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : planId = Value(planId),
       taskId = Value(taskId),
       userId = Value(userId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlanTaskRecord> custom({
    Expression<String>? planId,
    Expression<String>? taskId,
    Expression<String>? userId,
    Expression<double>? weight,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (planId != null) 'plan_id': planId,
      if (taskId != null) 'task_id': taskId,
      if (userId != null) 'user_id': userId,
      if (weight != null) 'weight': weight,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanTaskRecordsCompanion copyWith({
    Value<String>? planId,
    Value<String>? taskId,
    Value<String>? userId,
    Value<double>? weight,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlanTaskRecordsCompanion(
      planId: planId ?? this.planId,
      taskId: taskId ?? this.taskId,
      userId: userId ?? this.userId,
      weight: weight ?? this.weight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanTaskRecordsCompanion(')
          ..write('planId: $planId, ')
          ..write('taskId: $taskId, ')
          ..write('userId: $userId, ')
          ..write('weight: $weight, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewRecordsTable extends ReviewRecords
    with TableInfo<$ReviewRecordsTable, ReviewRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewTypeMeta = const VerificationMeta(
    'reviewType',
  );
  @override
  late final GeneratedColumn<String> reviewType = GeneratedColumn<String>(
    'review_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodStartMeta = const VerificationMeta(
    'periodStart',
  );
  @override
  late final GeneratedColumn<String> periodStart = GeneratedColumn<String>(
    'period_start',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodEndMeta = const VerificationMeta(
    'periodEnd',
  );
  @override
  late final GeneratedColumn<String> periodEnd = GeneratedColumn<String>(
    'period_end',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _happenedTextMeta = const VerificationMeta(
    'happenedText',
  );
  @override
  late final GeneratedColumn<String> happenedText = GeneratedColumn<String>(
    'happened_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _learnedTextMeta = const VerificationMeta(
    'learnedText',
  );
  @override
  late final GeneratedColumn<String> learnedText = GeneratedColumn<String>(
    'learned_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _improveTextMeta = const VerificationMeta(
    'improveText',
  );
  @override
  late final GeneratedColumn<String> improveText = GeneratedColumn<String>(
    'improve_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<int> mood = GeneratedColumn<int>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _objectiveSnapshotJsonMeta =
      const VerificationMeta('objectiveSnapshotJson');
  @override
  late final GeneratedColumn<String> objectiveSnapshotJson =
      GeneratedColumn<String>(
        'objective_snapshot_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    reviewType,
    periodStart,
    periodEnd,
    happenedText,
    learnedText,
    improveText,
    mood,
    objectiveSnapshotJson,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('review_type')) {
      context.handle(
        _reviewTypeMeta,
        reviewType.isAcceptableOrUnknown(data['review_type']!, _reviewTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewTypeMeta);
    }
    if (data.containsKey('period_start')) {
      context.handle(
        _periodStartMeta,
        periodStart.isAcceptableOrUnknown(
          data['period_start']!,
          _periodStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodStartMeta);
    }
    if (data.containsKey('period_end')) {
      context.handle(
        _periodEndMeta,
        periodEnd.isAcceptableOrUnknown(data['period_end']!, _periodEndMeta),
      );
    } else if (isInserting) {
      context.missing(_periodEndMeta);
    }
    if (data.containsKey('happened_text')) {
      context.handle(
        _happenedTextMeta,
        happenedText.isAcceptableOrUnknown(
          data['happened_text']!,
          _happenedTextMeta,
        ),
      );
    }
    if (data.containsKey('learned_text')) {
      context.handle(
        _learnedTextMeta,
        learnedText.isAcceptableOrUnknown(
          data['learned_text']!,
          _learnedTextMeta,
        ),
      );
    }
    if (data.containsKey('improve_text')) {
      context.handle(
        _improveTextMeta,
        improveText.isAcceptableOrUnknown(
          data['improve_text']!,
          _improveTextMeta,
        ),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('objective_snapshot_json')) {
      context.handle(
        _objectiveSnapshotJsonMeta,
        objectiveSnapshotJson.isAcceptableOrUnknown(
          data['objective_snapshot_json']!,
          _objectiveSnapshotJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, reviewType, periodStart},
  ];
  @override
  ReviewRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      reviewType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_type'],
      )!,
      periodStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_start'],
      )!,
      periodEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_end'],
      )!,
      happenedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}happened_text'],
      ),
      learnedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}learned_text'],
      ),
      improveText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}improve_text'],
      ),
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mood'],
      ),
      objectiveSnapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}objective_snapshot_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ReviewRecordsTable createAlias(String alias) {
    return $ReviewRecordsTable(attachedDatabase, alias);
  }
}

class ReviewRecord extends DataClass implements Insertable<ReviewRecord> {
  final String id;
  final String userId;
  final String reviewType;
  final String periodStart;
  final String periodEnd;
  final String? happenedText;
  final String? learnedText;
  final String? improveText;
  final int? mood;
  final String objectiveSnapshotJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ReviewRecord({
    required this.id,
    required this.userId,
    required this.reviewType,
    required this.periodStart,
    required this.periodEnd,
    this.happenedText,
    this.learnedText,
    this.improveText,
    this.mood,
    required this.objectiveSnapshotJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['review_type'] = Variable<String>(reviewType);
    map['period_start'] = Variable<String>(periodStart);
    map['period_end'] = Variable<String>(periodEnd);
    if (!nullToAbsent || happenedText != null) {
      map['happened_text'] = Variable<String>(happenedText);
    }
    if (!nullToAbsent || learnedText != null) {
      map['learned_text'] = Variable<String>(learnedText);
    }
    if (!nullToAbsent || improveText != null) {
      map['improve_text'] = Variable<String>(improveText);
    }
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<int>(mood);
    }
    map['objective_snapshot_json'] = Variable<String>(objectiveSnapshotJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ReviewRecordsCompanion toCompanion(bool nullToAbsent) {
    return ReviewRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      reviewType: Value(reviewType),
      periodStart: Value(periodStart),
      periodEnd: Value(periodEnd),
      happenedText: happenedText == null && nullToAbsent
          ? const Value.absent()
          : Value(happenedText),
      learnedText: learnedText == null && nullToAbsent
          ? const Value.absent()
          : Value(learnedText),
      improveText: improveText == null && nullToAbsent
          ? const Value.absent()
          : Value(improveText),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      objectiveSnapshotJson: Value(objectiveSnapshotJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ReviewRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      reviewType: serializer.fromJson<String>(json['reviewType']),
      periodStart: serializer.fromJson<String>(json['periodStart']),
      periodEnd: serializer.fromJson<String>(json['periodEnd']),
      happenedText: serializer.fromJson<String?>(json['happenedText']),
      learnedText: serializer.fromJson<String?>(json['learnedText']),
      improveText: serializer.fromJson<String?>(json['improveText']),
      mood: serializer.fromJson<int?>(json['mood']),
      objectiveSnapshotJson: serializer.fromJson<String>(
        json['objectiveSnapshotJson'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'reviewType': serializer.toJson<String>(reviewType),
      'periodStart': serializer.toJson<String>(periodStart),
      'periodEnd': serializer.toJson<String>(periodEnd),
      'happenedText': serializer.toJson<String?>(happenedText),
      'learnedText': serializer.toJson<String?>(learnedText),
      'improveText': serializer.toJson<String?>(improveText),
      'mood': serializer.toJson<int?>(mood),
      'objectiveSnapshotJson': serializer.toJson<String>(objectiveSnapshotJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ReviewRecord copyWith({
    String? id,
    String? userId,
    String? reviewType,
    String? periodStart,
    String? periodEnd,
    Value<String?> happenedText = const Value.absent(),
    Value<String?> learnedText = const Value.absent(),
    Value<String?> improveText = const Value.absent(),
    Value<int?> mood = const Value.absent(),
    String? objectiveSnapshotJson,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ReviewRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    reviewType: reviewType ?? this.reviewType,
    periodStart: periodStart ?? this.periodStart,
    periodEnd: periodEnd ?? this.periodEnd,
    happenedText: happenedText.present ? happenedText.value : this.happenedText,
    learnedText: learnedText.present ? learnedText.value : this.learnedText,
    improveText: improveText.present ? improveText.value : this.improveText,
    mood: mood.present ? mood.value : this.mood,
    objectiveSnapshotJson: objectiveSnapshotJson ?? this.objectiveSnapshotJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ReviewRecord copyWithCompanion(ReviewRecordsCompanion data) {
    return ReviewRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      reviewType: data.reviewType.present
          ? data.reviewType.value
          : this.reviewType,
      periodStart: data.periodStart.present
          ? data.periodStart.value
          : this.periodStart,
      periodEnd: data.periodEnd.present ? data.periodEnd.value : this.periodEnd,
      happenedText: data.happenedText.present
          ? data.happenedText.value
          : this.happenedText,
      learnedText: data.learnedText.present
          ? data.learnedText.value
          : this.learnedText,
      improveText: data.improveText.present
          ? data.improveText.value
          : this.improveText,
      mood: data.mood.present ? data.mood.value : this.mood,
      objectiveSnapshotJson: data.objectiveSnapshotJson.present
          ? data.objectiveSnapshotJson.value
          : this.objectiveSnapshotJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('reviewType: $reviewType, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('happenedText: $happenedText, ')
          ..write('learnedText: $learnedText, ')
          ..write('improveText: $improveText, ')
          ..write('mood: $mood, ')
          ..write('objectiveSnapshotJson: $objectiveSnapshotJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    reviewType,
    periodStart,
    periodEnd,
    happenedText,
    learnedText,
    improveText,
    mood,
    objectiveSnapshotJson,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.reviewType == this.reviewType &&
          other.periodStart == this.periodStart &&
          other.periodEnd == this.periodEnd &&
          other.happenedText == this.happenedText &&
          other.learnedText == this.learnedText &&
          other.improveText == this.improveText &&
          other.mood == this.mood &&
          other.objectiveSnapshotJson == this.objectiveSnapshotJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ReviewRecordsCompanion extends UpdateCompanion<ReviewRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> reviewType;
  final Value<String> periodStart;
  final Value<String> periodEnd;
  final Value<String?> happenedText;
  final Value<String?> learnedText;
  final Value<String?> improveText;
  final Value<int?> mood;
  final Value<String> objectiveSnapshotJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ReviewRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.reviewType = const Value.absent(),
    this.periodStart = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.happenedText = const Value.absent(),
    this.learnedText = const Value.absent(),
    this.improveText = const Value.absent(),
    this.mood = const Value.absent(),
    this.objectiveSnapshotJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewRecordsCompanion.insert({
    required String id,
    required String userId,
    required String reviewType,
    required String periodStart,
    required String periodEnd,
    this.happenedText = const Value.absent(),
    this.learnedText = const Value.absent(),
    this.improveText = const Value.absent(),
    this.mood = const Value.absent(),
    this.objectiveSnapshotJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       reviewType = Value(reviewType),
       periodStart = Value(periodStart),
       periodEnd = Value(periodEnd),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ReviewRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? reviewType,
    Expression<String>? periodStart,
    Expression<String>? periodEnd,
    Expression<String>? happenedText,
    Expression<String>? learnedText,
    Expression<String>? improveText,
    Expression<int>? mood,
    Expression<String>? objectiveSnapshotJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (reviewType != null) 'review_type': reviewType,
      if (periodStart != null) 'period_start': periodStart,
      if (periodEnd != null) 'period_end': periodEnd,
      if (happenedText != null) 'happened_text': happenedText,
      if (learnedText != null) 'learned_text': learnedText,
      if (improveText != null) 'improve_text': improveText,
      if (mood != null) 'mood': mood,
      if (objectiveSnapshotJson != null)
        'objective_snapshot_json': objectiveSnapshotJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? reviewType,
    Value<String>? periodStart,
    Value<String>? periodEnd,
    Value<String?>? happenedText,
    Value<String?>? learnedText,
    Value<String?>? improveText,
    Value<int?>? mood,
    Value<String>? objectiveSnapshotJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ReviewRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      reviewType: reviewType ?? this.reviewType,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      happenedText: happenedText ?? this.happenedText,
      learnedText: learnedText ?? this.learnedText,
      improveText: improveText ?? this.improveText,
      mood: mood ?? this.mood,
      objectiveSnapshotJson:
          objectiveSnapshotJson ?? this.objectiveSnapshotJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (reviewType.present) {
      map['review_type'] = Variable<String>(reviewType.value);
    }
    if (periodStart.present) {
      map['period_start'] = Variable<String>(periodStart.value);
    }
    if (periodEnd.present) {
      map['period_end'] = Variable<String>(periodEnd.value);
    }
    if (happenedText.present) {
      map['happened_text'] = Variable<String>(happenedText.value);
    }
    if (learnedText.present) {
      map['learned_text'] = Variable<String>(learnedText.value);
    }
    if (improveText.present) {
      map['improve_text'] = Variable<String>(improveText.value);
    }
    if (mood.present) {
      map['mood'] = Variable<int>(mood.value);
    }
    if (objectiveSnapshotJson.present) {
      map['objective_snapshot_json'] = Variable<String>(
        objectiveSnapshotJson.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('reviewType: $reviewType, ')
          ..write('periodStart: $periodStart, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('happenedText: $happenedText, ')
          ..write('learnedText: $learnedText, ')
          ..write('improveText: $improveText, ')
          ..write('mood: $mood, ')
          ..write('objectiveSnapshotJson: $objectiveSnapshotJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CourseRecordsTable extends CourseRecords
    with TableInfo<$CourseRecordsTable, CourseRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teacherMeta = const VerificationMeta(
    'teacher',
  );
  @override
  late final GeneratedColumn<String> teacher = GeneratedColumn<String>(
    'teacher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _classroomMeta = const VerificationMeta(
    'classroom',
  );
  @override
  late final GeneratedColumn<String> classroom = GeneratedColumn<String>(
    'classroom',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _semesterMeta = const VerificationMeta(
    'semester',
  );
  @override
  late final GeneratedColumn<String> semester = GeneratedColumn<String>(
    'semester',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _semesterIdMeta = const VerificationMeta(
    'semesterId',
  );
  @override
  late final GeneratedColumn<String> semesterId = GeneratedColumn<String>(
    'semester_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _semesterStartsOnMeta = const VerificationMeta(
    'semesterStartsOn',
  );
  @override
  late final GeneratedColumn<DateTime> semesterStartsOn =
      GeneratedColumn<DateTime>(
        'semester_starts_on',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _semesterEndsOnMeta = const VerificationMeta(
    'semesterEndsOn',
  );
  @override
  late final GeneratedColumn<DateTime> semesterEndsOn =
      GeneratedColumn<DateTime>(
        'semester_ends_on',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    colorValue,
    teacher,
    classroom,
    semester,
    semesterId,
    semesterStartsOn,
    semesterEndsOn,
    notes,
    status,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CourseRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('teacher')) {
      context.handle(
        _teacherMeta,
        teacher.isAcceptableOrUnknown(data['teacher']!, _teacherMeta),
      );
    }
    if (data.containsKey('classroom')) {
      context.handle(
        _classroomMeta,
        classroom.isAcceptableOrUnknown(data['classroom']!, _classroomMeta),
      );
    }
    if (data.containsKey('semester')) {
      context.handle(
        _semesterMeta,
        semester.isAcceptableOrUnknown(data['semester']!, _semesterMeta),
      );
    }
    if (data.containsKey('semester_id')) {
      context.handle(
        _semesterIdMeta,
        semesterId.isAcceptableOrUnknown(data['semester_id']!, _semesterIdMeta),
      );
    }
    if (data.containsKey('semester_starts_on')) {
      context.handle(
        _semesterStartsOnMeta,
        semesterStartsOn.isAcceptableOrUnknown(
          data['semester_starts_on']!,
          _semesterStartsOnMeta,
        ),
      );
    }
    if (data.containsKey('semester_ends_on')) {
      context.handle(
        _semesterEndsOnMeta,
        semesterEndsOn.isAcceptableOrUnknown(
          data['semester_ends_on']!,
          _semesterEndsOnMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CourseRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      teacher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}teacher'],
      ),
      classroom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}classroom'],
      ),
      semester: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}semester'],
      ),
      semesterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}semester_id'],
      ),
      semesterStartsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}semester_starts_on'],
      ),
      semesterEndsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}semester_ends_on'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CourseRecordsTable createAlias(String alias) {
    return $CourseRecordsTable(attachedDatabase, alias);
  }
}

class CourseRecord extends DataClass implements Insertable<CourseRecord> {
  final String id;
  final String userId;
  final String name;
  final int colorValue;
  final String? teacher;
  final String? classroom;
  final String? semester;
  final String? semesterId;
  final DateTime? semesterStartsOn;
  final DateTime? semesterEndsOn;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const CourseRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.colorValue,
    this.teacher,
    this.classroom,
    this.semester,
    this.semesterId,
    this.semesterStartsOn,
    this.semesterEndsOn,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    if (!nullToAbsent || teacher != null) {
      map['teacher'] = Variable<String>(teacher);
    }
    if (!nullToAbsent || classroom != null) {
      map['classroom'] = Variable<String>(classroom);
    }
    if (!nullToAbsent || semester != null) {
      map['semester'] = Variable<String>(semester);
    }
    if (!nullToAbsent || semesterId != null) {
      map['semester_id'] = Variable<String>(semesterId);
    }
    if (!nullToAbsent || semesterStartsOn != null) {
      map['semester_starts_on'] = Variable<DateTime>(semesterStartsOn);
    }
    if (!nullToAbsent || semesterEndsOn != null) {
      map['semester_ends_on'] = Variable<DateTime>(semesterEndsOn);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  CourseRecordsCompanion toCompanion(bool nullToAbsent) {
    return CourseRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      colorValue: Value(colorValue),
      teacher: teacher == null && nullToAbsent
          ? const Value.absent()
          : Value(teacher),
      classroom: classroom == null && nullToAbsent
          ? const Value.absent()
          : Value(classroom),
      semester: semester == null && nullToAbsent
          ? const Value.absent()
          : Value(semester),
      semesterId: semesterId == null && nullToAbsent
          ? const Value.absent()
          : Value(semesterId),
      semesterStartsOn: semesterStartsOn == null && nullToAbsent
          ? const Value.absent()
          : Value(semesterStartsOn),
      semesterEndsOn: semesterEndsOn == null && nullToAbsent
          ? const Value.absent()
          : Value(semesterEndsOn),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CourseRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      teacher: serializer.fromJson<String?>(json['teacher']),
      classroom: serializer.fromJson<String?>(json['classroom']),
      semester: serializer.fromJson<String?>(json['semester']),
      semesterId: serializer.fromJson<String?>(json['semesterId']),
      semesterStartsOn: serializer.fromJson<DateTime?>(
        json['semesterStartsOn'],
      ),
      semesterEndsOn: serializer.fromJson<DateTime?>(json['semesterEndsOn']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'teacher': serializer.toJson<String?>(teacher),
      'classroom': serializer.toJson<String?>(classroom),
      'semester': serializer.toJson<String?>(semester),
      'semesterId': serializer.toJson<String?>(semesterId),
      'semesterStartsOn': serializer.toJson<DateTime?>(semesterStartsOn),
      'semesterEndsOn': serializer.toJson<DateTime?>(semesterEndsOn),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  CourseRecord copyWith({
    String? id,
    String? userId,
    String? name,
    int? colorValue,
    Value<String?> teacher = const Value.absent(),
    Value<String?> classroom = const Value.absent(),
    Value<String?> semester = const Value.absent(),
    Value<String?> semesterId = const Value.absent(),
    Value<DateTime?> semesterStartsOn = const Value.absent(),
    Value<DateTime?> semesterEndsOn = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => CourseRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    teacher: teacher.present ? teacher.value : this.teacher,
    classroom: classroom.present ? classroom.value : this.classroom,
    semester: semester.present ? semester.value : this.semester,
    semesterId: semesterId.present ? semesterId.value : this.semesterId,
    semesterStartsOn: semesterStartsOn.present
        ? semesterStartsOn.value
        : this.semesterStartsOn,
    semesterEndsOn: semesterEndsOn.present
        ? semesterEndsOn.value
        : this.semesterEndsOn,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CourseRecord copyWithCompanion(CourseRecordsCompanion data) {
    return CourseRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      teacher: data.teacher.present ? data.teacher.value : this.teacher,
      classroom: data.classroom.present ? data.classroom.value : this.classroom,
      semester: data.semester.present ? data.semester.value : this.semester,
      semesterId: data.semesterId.present
          ? data.semesterId.value
          : this.semesterId,
      semesterStartsOn: data.semesterStartsOn.present
          ? data.semesterStartsOn.value
          : this.semesterStartsOn,
      semesterEndsOn: data.semesterEndsOn.present
          ? data.semesterEndsOn.value
          : this.semesterEndsOn,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('teacher: $teacher, ')
          ..write('classroom: $classroom, ')
          ..write('semester: $semester, ')
          ..write('semesterId: $semesterId, ')
          ..write('semesterStartsOn: $semesterStartsOn, ')
          ..write('semesterEndsOn: $semesterEndsOn, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    colorValue,
    teacher,
    classroom,
    semester,
    semesterId,
    semesterStartsOn,
    semesterEndsOn,
    notes,
    status,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.teacher == this.teacher &&
          other.classroom == this.classroom &&
          other.semester == this.semester &&
          other.semesterId == this.semesterId &&
          other.semesterStartsOn == this.semesterStartsOn &&
          other.semesterEndsOn == this.semesterEndsOn &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CourseRecordsCompanion extends UpdateCompanion<CourseRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<String?> teacher;
  final Value<String?> classroom;
  final Value<String?> semester;
  final Value<String?> semesterId;
  final Value<DateTime?> semesterStartsOn;
  final Value<DateTime?> semesterEndsOn;
  final Value<String?> notes;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const CourseRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.teacher = const Value.absent(),
    this.classroom = const Value.absent(),
    this.semester = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.semesterStartsOn = const Value.absent(),
    this.semesterEndsOn = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CourseRecordsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required int colorValue,
    this.teacher = const Value.absent(),
    this.classroom = const Value.absent(),
    this.semester = const Value.absent(),
    this.semesterId = const Value.absent(),
    this.semesterStartsOn = const Value.absent(),
    this.semesterEndsOn = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       colorValue = Value(colorValue),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CourseRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<String>? teacher,
    Expression<String>? classroom,
    Expression<String>? semester,
    Expression<String>? semesterId,
    Expression<DateTime>? semesterStartsOn,
    Expression<DateTime>? semesterEndsOn,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (teacher != null) 'teacher': teacher,
      if (classroom != null) 'classroom': classroom,
      if (semester != null) 'semester': semester,
      if (semesterId != null) 'semester_id': semesterId,
      if (semesterStartsOn != null) 'semester_starts_on': semesterStartsOn,
      if (semesterEndsOn != null) 'semester_ends_on': semesterEndsOn,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CourseRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<int>? colorValue,
    Value<String?>? teacher,
    Value<String?>? classroom,
    Value<String?>? semester,
    Value<String?>? semesterId,
    Value<DateTime?>? semesterStartsOn,
    Value<DateTime?>? semesterEndsOn,
    Value<String?>? notes,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CourseRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      teacher: teacher ?? this.teacher,
      classroom: classroom ?? this.classroom,
      semester: semester ?? this.semester,
      semesterId: semesterId ?? this.semesterId,
      semesterStartsOn: semesterStartsOn ?? this.semesterStartsOn,
      semesterEndsOn: semesterEndsOn ?? this.semesterEndsOn,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (teacher.present) {
      map['teacher'] = Variable<String>(teacher.value);
    }
    if (classroom.present) {
      map['classroom'] = Variable<String>(classroom.value);
    }
    if (semester.present) {
      map['semester'] = Variable<String>(semester.value);
    }
    if (semesterId.present) {
      map['semester_id'] = Variable<String>(semesterId.value);
    }
    if (semesterStartsOn.present) {
      map['semester_starts_on'] = Variable<DateTime>(semesterStartsOn.value);
    }
    if (semesterEndsOn.present) {
      map['semester_ends_on'] = Variable<DateTime>(semesterEndsOn.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('teacher: $teacher, ')
          ..write('classroom: $classroom, ')
          ..write('semester: $semester, ')
          ..write('semesterId: $semesterId, ')
          ..write('semesterStartsOn: $semesterStartsOn, ')
          ..write('semesterEndsOn: $semesterEndsOn, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CourseScheduleRuleRecordsTable extends CourseScheduleRuleRecords
    with TableInfo<$CourseScheduleRuleRecordsTable, CourseScheduleRuleRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseScheduleRuleRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<String> courseId = GeneratedColumn<String>(
    'course_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES course_records (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekdayMeta = const VerificationMeta(
    'weekday',
  );
  @override
  late final GeneratedColumn<int> weekday = GeneratedColumn<int>(
    'weekday',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekRuleTypeMeta = const VerificationMeta(
    'weekRuleType',
  );
  @override
  late final GeneratedColumn<String> weekRuleType = GeneratedColumn<String>(
    'week_rule_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startWeekMeta = const VerificationMeta(
    'startWeek',
  );
  @override
  late final GeneratedColumn<int> startWeek = GeneratedColumn<int>(
    'start_week',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endWeekMeta = const VerificationMeta(
    'endWeek',
  );
  @override
  late final GeneratedColumn<int> endWeek = GeneratedColumn<int>(
    'end_week',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intervalWeeksMeta = const VerificationMeta(
    'intervalWeeks',
  );
  @override
  late final GeneratedColumn<int> intervalWeeks = GeneratedColumn<int>(
    'interval_weeks',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weekNumbersJsonMeta = const VerificationMeta(
    'weekNumbersJson',
  );
  @override
  late final GeneratedColumn<String> weekNumbersJson = GeneratedColumn<String>(
    'week_numbers_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _scheduleTemplateIdMeta =
      const VerificationMeta('scheduleTemplateId');
  @override
  late final GeneratedColumn<String> scheduleTemplateId =
      GeneratedColumn<String>(
        'schedule_template_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sectionIdsJsonMeta = const VerificationMeta(
    'sectionIdsJson',
  );
  @override
  late final GeneratedColumn<String> sectionIdsJson = GeneratedColumn<String>(
    'section_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _startsAtMinuteMeta = const VerificationMeta(
    'startsAtMinute',
  );
  @override
  late final GeneratedColumn<int> startsAtMinute = GeneratedColumn<int>(
    'starts_at_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMinuteMeta = const VerificationMeta(
    'endsAtMinute',
  );
  @override
  late final GeneratedColumn<int> endsAtMinute = GeneratedColumn<int>(
    'ends_at_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remindBeforeMinutesMeta =
      const VerificationMeta('remindBeforeMinutes');
  @override
  late final GeneratedColumn<int> remindBeforeMinutes = GeneratedColumn<int>(
    'remind_before_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    courseId,
    userId,
    weekday,
    weekRuleType,
    startWeek,
    endWeek,
    intervalWeeks,
    weekNumbersJson,
    scheduleTemplateId,
    sectionIdsJson,
    startsAtMinute,
    endsAtMinute,
    remindBeforeMinutes,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_schedule_rule_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<CourseScheduleRuleRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('weekday')) {
      context.handle(
        _weekdayMeta,
        weekday.isAcceptableOrUnknown(data['weekday']!, _weekdayMeta),
      );
    } else if (isInserting) {
      context.missing(_weekdayMeta);
    }
    if (data.containsKey('week_rule_type')) {
      context.handle(
        _weekRuleTypeMeta,
        weekRuleType.isAcceptableOrUnknown(
          data['week_rule_type']!,
          _weekRuleTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekRuleTypeMeta);
    }
    if (data.containsKey('start_week')) {
      context.handle(
        _startWeekMeta,
        startWeek.isAcceptableOrUnknown(data['start_week']!, _startWeekMeta),
      );
    }
    if (data.containsKey('end_week')) {
      context.handle(
        _endWeekMeta,
        endWeek.isAcceptableOrUnknown(data['end_week']!, _endWeekMeta),
      );
    }
    if (data.containsKey('interval_weeks')) {
      context.handle(
        _intervalWeeksMeta,
        intervalWeeks.isAcceptableOrUnknown(
          data['interval_weeks']!,
          _intervalWeeksMeta,
        ),
      );
    }
    if (data.containsKey('week_numbers_json')) {
      context.handle(
        _weekNumbersJsonMeta,
        weekNumbersJson.isAcceptableOrUnknown(
          data['week_numbers_json']!,
          _weekNumbersJsonMeta,
        ),
      );
    }
    if (data.containsKey('schedule_template_id')) {
      context.handle(
        _scheduleTemplateIdMeta,
        scheduleTemplateId.isAcceptableOrUnknown(
          data['schedule_template_id']!,
          _scheduleTemplateIdMeta,
        ),
      );
    }
    if (data.containsKey('section_ids_json')) {
      context.handle(
        _sectionIdsJsonMeta,
        sectionIdsJson.isAcceptableOrUnknown(
          data['section_ids_json']!,
          _sectionIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('starts_at_minute')) {
      context.handle(
        _startsAtMinuteMeta,
        startsAtMinute.isAcceptableOrUnknown(
          data['starts_at_minute']!,
          _startsAtMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startsAtMinuteMeta);
    }
    if (data.containsKey('ends_at_minute')) {
      context.handle(
        _endsAtMinuteMeta,
        endsAtMinute.isAcceptableOrUnknown(
          data['ends_at_minute']!,
          _endsAtMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endsAtMinuteMeta);
    }
    if (data.containsKey('remind_before_minutes')) {
      context.handle(
        _remindBeforeMinutesMeta,
        remindBeforeMinutes.isAcceptableOrUnknown(
          data['remind_before_minutes']!,
          _remindBeforeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CourseScheduleRuleRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseScheduleRuleRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      weekday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday'],
      )!,
      weekRuleType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_rule_type'],
      )!,
      startWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_week'],
      ),
      endWeek: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_week'],
      ),
      intervalWeeks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_weeks'],
      ),
      weekNumbersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}week_numbers_json'],
      )!,
      scheduleTemplateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_template_id'],
      ),
      sectionIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}section_ids_json'],
      )!,
      startsAtMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_minute'],
      )!,
      endsAtMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_minute'],
      )!,
      remindBeforeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_before_minutes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CourseScheduleRuleRecordsTable createAlias(String alias) {
    return $CourseScheduleRuleRecordsTable(attachedDatabase, alias);
  }
}

class CourseScheduleRuleRecord extends DataClass
    implements Insertable<CourseScheduleRuleRecord> {
  final String id;
  final String courseId;
  final String userId;
  final int weekday;
  final String weekRuleType;
  final int? startWeek;
  final int? endWeek;
  final int? intervalWeeks;
  final String weekNumbersJson;
  final String? scheduleTemplateId;
  final String sectionIdsJson;
  final int startsAtMinute;
  final int endsAtMinute;
  final int? remindBeforeMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const CourseScheduleRuleRecord({
    required this.id,
    required this.courseId,
    required this.userId,
    required this.weekday,
    required this.weekRuleType,
    this.startWeek,
    this.endWeek,
    this.intervalWeeks,
    required this.weekNumbersJson,
    this.scheduleTemplateId,
    required this.sectionIdsJson,
    required this.startsAtMinute,
    required this.endsAtMinute,
    this.remindBeforeMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['course_id'] = Variable<String>(courseId);
    map['user_id'] = Variable<String>(userId);
    map['weekday'] = Variable<int>(weekday);
    map['week_rule_type'] = Variable<String>(weekRuleType);
    if (!nullToAbsent || startWeek != null) {
      map['start_week'] = Variable<int>(startWeek);
    }
    if (!nullToAbsent || endWeek != null) {
      map['end_week'] = Variable<int>(endWeek);
    }
    if (!nullToAbsent || intervalWeeks != null) {
      map['interval_weeks'] = Variable<int>(intervalWeeks);
    }
    map['week_numbers_json'] = Variable<String>(weekNumbersJson);
    if (!nullToAbsent || scheduleTemplateId != null) {
      map['schedule_template_id'] = Variable<String>(scheduleTemplateId);
    }
    map['section_ids_json'] = Variable<String>(sectionIdsJson);
    map['starts_at_minute'] = Variable<int>(startsAtMinute);
    map['ends_at_minute'] = Variable<int>(endsAtMinute);
    if (!nullToAbsent || remindBeforeMinutes != null) {
      map['remind_before_minutes'] = Variable<int>(remindBeforeMinutes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  CourseScheduleRuleRecordsCompanion toCompanion(bool nullToAbsent) {
    return CourseScheduleRuleRecordsCompanion(
      id: Value(id),
      courseId: Value(courseId),
      userId: Value(userId),
      weekday: Value(weekday),
      weekRuleType: Value(weekRuleType),
      startWeek: startWeek == null && nullToAbsent
          ? const Value.absent()
          : Value(startWeek),
      endWeek: endWeek == null && nullToAbsent
          ? const Value.absent()
          : Value(endWeek),
      intervalWeeks: intervalWeeks == null && nullToAbsent
          ? const Value.absent()
          : Value(intervalWeeks),
      weekNumbersJson: Value(weekNumbersJson),
      scheduleTemplateId: scheduleTemplateId == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduleTemplateId),
      sectionIdsJson: Value(sectionIdsJson),
      startsAtMinute: Value(startsAtMinute),
      endsAtMinute: Value(endsAtMinute),
      remindBeforeMinutes: remindBeforeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(remindBeforeMinutes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CourseScheduleRuleRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseScheduleRuleRecord(
      id: serializer.fromJson<String>(json['id']),
      courseId: serializer.fromJson<String>(json['courseId']),
      userId: serializer.fromJson<String>(json['userId']),
      weekday: serializer.fromJson<int>(json['weekday']),
      weekRuleType: serializer.fromJson<String>(json['weekRuleType']),
      startWeek: serializer.fromJson<int?>(json['startWeek']),
      endWeek: serializer.fromJson<int?>(json['endWeek']),
      intervalWeeks: serializer.fromJson<int?>(json['intervalWeeks']),
      weekNumbersJson: serializer.fromJson<String>(json['weekNumbersJson']),
      scheduleTemplateId: serializer.fromJson<String?>(
        json['scheduleTemplateId'],
      ),
      sectionIdsJson: serializer.fromJson<String>(json['sectionIdsJson']),
      startsAtMinute: serializer.fromJson<int>(json['startsAtMinute']),
      endsAtMinute: serializer.fromJson<int>(json['endsAtMinute']),
      remindBeforeMinutes: serializer.fromJson<int?>(
        json['remindBeforeMinutes'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'courseId': serializer.toJson<String>(courseId),
      'userId': serializer.toJson<String>(userId),
      'weekday': serializer.toJson<int>(weekday),
      'weekRuleType': serializer.toJson<String>(weekRuleType),
      'startWeek': serializer.toJson<int?>(startWeek),
      'endWeek': serializer.toJson<int?>(endWeek),
      'intervalWeeks': serializer.toJson<int?>(intervalWeeks),
      'weekNumbersJson': serializer.toJson<String>(weekNumbersJson),
      'scheduleTemplateId': serializer.toJson<String?>(scheduleTemplateId),
      'sectionIdsJson': serializer.toJson<String>(sectionIdsJson),
      'startsAtMinute': serializer.toJson<int>(startsAtMinute),
      'endsAtMinute': serializer.toJson<int>(endsAtMinute),
      'remindBeforeMinutes': serializer.toJson<int?>(remindBeforeMinutes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  CourseScheduleRuleRecord copyWith({
    String? id,
    String? courseId,
    String? userId,
    int? weekday,
    String? weekRuleType,
    Value<int?> startWeek = const Value.absent(),
    Value<int?> endWeek = const Value.absent(),
    Value<int?> intervalWeeks = const Value.absent(),
    String? weekNumbersJson,
    Value<String?> scheduleTemplateId = const Value.absent(),
    String? sectionIdsJson,
    int? startsAtMinute,
    int? endsAtMinute,
    Value<int?> remindBeforeMinutes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => CourseScheduleRuleRecord(
    id: id ?? this.id,
    courseId: courseId ?? this.courseId,
    userId: userId ?? this.userId,
    weekday: weekday ?? this.weekday,
    weekRuleType: weekRuleType ?? this.weekRuleType,
    startWeek: startWeek.present ? startWeek.value : this.startWeek,
    endWeek: endWeek.present ? endWeek.value : this.endWeek,
    intervalWeeks: intervalWeeks.present
        ? intervalWeeks.value
        : this.intervalWeeks,
    weekNumbersJson: weekNumbersJson ?? this.weekNumbersJson,
    scheduleTemplateId: scheduleTemplateId.present
        ? scheduleTemplateId.value
        : this.scheduleTemplateId,
    sectionIdsJson: sectionIdsJson ?? this.sectionIdsJson,
    startsAtMinute: startsAtMinute ?? this.startsAtMinute,
    endsAtMinute: endsAtMinute ?? this.endsAtMinute,
    remindBeforeMinutes: remindBeforeMinutes.present
        ? remindBeforeMinutes.value
        : this.remindBeforeMinutes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CourseScheduleRuleRecord copyWithCompanion(
    CourseScheduleRuleRecordsCompanion data,
  ) {
    return CourseScheduleRuleRecord(
      id: data.id.present ? data.id.value : this.id,
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      userId: data.userId.present ? data.userId.value : this.userId,
      weekday: data.weekday.present ? data.weekday.value : this.weekday,
      weekRuleType: data.weekRuleType.present
          ? data.weekRuleType.value
          : this.weekRuleType,
      startWeek: data.startWeek.present ? data.startWeek.value : this.startWeek,
      endWeek: data.endWeek.present ? data.endWeek.value : this.endWeek,
      intervalWeeks: data.intervalWeeks.present
          ? data.intervalWeeks.value
          : this.intervalWeeks,
      weekNumbersJson: data.weekNumbersJson.present
          ? data.weekNumbersJson.value
          : this.weekNumbersJson,
      scheduleTemplateId: data.scheduleTemplateId.present
          ? data.scheduleTemplateId.value
          : this.scheduleTemplateId,
      sectionIdsJson: data.sectionIdsJson.present
          ? data.sectionIdsJson.value
          : this.sectionIdsJson,
      startsAtMinute: data.startsAtMinute.present
          ? data.startsAtMinute.value
          : this.startsAtMinute,
      endsAtMinute: data.endsAtMinute.present
          ? data.endsAtMinute.value
          : this.endsAtMinute,
      remindBeforeMinutes: data.remindBeforeMinutes.present
          ? data.remindBeforeMinutes.value
          : this.remindBeforeMinutes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseScheduleRuleRecord(')
          ..write('id: $id, ')
          ..write('courseId: $courseId, ')
          ..write('userId: $userId, ')
          ..write('weekday: $weekday, ')
          ..write('weekRuleType: $weekRuleType, ')
          ..write('startWeek: $startWeek, ')
          ..write('endWeek: $endWeek, ')
          ..write('intervalWeeks: $intervalWeeks, ')
          ..write('weekNumbersJson: $weekNumbersJson, ')
          ..write('scheduleTemplateId: $scheduleTemplateId, ')
          ..write('sectionIdsJson: $sectionIdsJson, ')
          ..write('startsAtMinute: $startsAtMinute, ')
          ..write('endsAtMinute: $endsAtMinute, ')
          ..write('remindBeforeMinutes: $remindBeforeMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    courseId,
    userId,
    weekday,
    weekRuleType,
    startWeek,
    endWeek,
    intervalWeeks,
    weekNumbersJson,
    scheduleTemplateId,
    sectionIdsJson,
    startsAtMinute,
    endsAtMinute,
    remindBeforeMinutes,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseScheduleRuleRecord &&
          other.id == this.id &&
          other.courseId == this.courseId &&
          other.userId == this.userId &&
          other.weekday == this.weekday &&
          other.weekRuleType == this.weekRuleType &&
          other.startWeek == this.startWeek &&
          other.endWeek == this.endWeek &&
          other.intervalWeeks == this.intervalWeeks &&
          other.weekNumbersJson == this.weekNumbersJson &&
          other.scheduleTemplateId == this.scheduleTemplateId &&
          other.sectionIdsJson == this.sectionIdsJson &&
          other.startsAtMinute == this.startsAtMinute &&
          other.endsAtMinute == this.endsAtMinute &&
          other.remindBeforeMinutes == this.remindBeforeMinutes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CourseScheduleRuleRecordsCompanion
    extends UpdateCompanion<CourseScheduleRuleRecord> {
  final Value<String> id;
  final Value<String> courseId;
  final Value<String> userId;
  final Value<int> weekday;
  final Value<String> weekRuleType;
  final Value<int?> startWeek;
  final Value<int?> endWeek;
  final Value<int?> intervalWeeks;
  final Value<String> weekNumbersJson;
  final Value<String?> scheduleTemplateId;
  final Value<String> sectionIdsJson;
  final Value<int> startsAtMinute;
  final Value<int> endsAtMinute;
  final Value<int?> remindBeforeMinutes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const CourseScheduleRuleRecordsCompanion({
    this.id = const Value.absent(),
    this.courseId = const Value.absent(),
    this.userId = const Value.absent(),
    this.weekday = const Value.absent(),
    this.weekRuleType = const Value.absent(),
    this.startWeek = const Value.absent(),
    this.endWeek = const Value.absent(),
    this.intervalWeeks = const Value.absent(),
    this.weekNumbersJson = const Value.absent(),
    this.scheduleTemplateId = const Value.absent(),
    this.sectionIdsJson = const Value.absent(),
    this.startsAtMinute = const Value.absent(),
    this.endsAtMinute = const Value.absent(),
    this.remindBeforeMinutes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CourseScheduleRuleRecordsCompanion.insert({
    required String id,
    required String courseId,
    required String userId,
    required int weekday,
    required String weekRuleType,
    this.startWeek = const Value.absent(),
    this.endWeek = const Value.absent(),
    this.intervalWeeks = const Value.absent(),
    this.weekNumbersJson = const Value.absent(),
    this.scheduleTemplateId = const Value.absent(),
    this.sectionIdsJson = const Value.absent(),
    required int startsAtMinute,
    required int endsAtMinute,
    this.remindBeforeMinutes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       courseId = Value(courseId),
       userId = Value(userId),
       weekday = Value(weekday),
       weekRuleType = Value(weekRuleType),
       startsAtMinute = Value(startsAtMinute),
       endsAtMinute = Value(endsAtMinute),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CourseScheduleRuleRecord> custom({
    Expression<String>? id,
    Expression<String>? courseId,
    Expression<String>? userId,
    Expression<int>? weekday,
    Expression<String>? weekRuleType,
    Expression<int>? startWeek,
    Expression<int>? endWeek,
    Expression<int>? intervalWeeks,
    Expression<String>? weekNumbersJson,
    Expression<String>? scheduleTemplateId,
    Expression<String>? sectionIdsJson,
    Expression<int>? startsAtMinute,
    Expression<int>? endsAtMinute,
    Expression<int>? remindBeforeMinutes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (courseId != null) 'course_id': courseId,
      if (userId != null) 'user_id': userId,
      if (weekday != null) 'weekday': weekday,
      if (weekRuleType != null) 'week_rule_type': weekRuleType,
      if (startWeek != null) 'start_week': startWeek,
      if (endWeek != null) 'end_week': endWeek,
      if (intervalWeeks != null) 'interval_weeks': intervalWeeks,
      if (weekNumbersJson != null) 'week_numbers_json': weekNumbersJson,
      if (scheduleTemplateId != null)
        'schedule_template_id': scheduleTemplateId,
      if (sectionIdsJson != null) 'section_ids_json': sectionIdsJson,
      if (startsAtMinute != null) 'starts_at_minute': startsAtMinute,
      if (endsAtMinute != null) 'ends_at_minute': endsAtMinute,
      if (remindBeforeMinutes != null)
        'remind_before_minutes': remindBeforeMinutes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CourseScheduleRuleRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? courseId,
    Value<String>? userId,
    Value<int>? weekday,
    Value<String>? weekRuleType,
    Value<int?>? startWeek,
    Value<int?>? endWeek,
    Value<int?>? intervalWeeks,
    Value<String>? weekNumbersJson,
    Value<String?>? scheduleTemplateId,
    Value<String>? sectionIdsJson,
    Value<int>? startsAtMinute,
    Value<int>? endsAtMinute,
    Value<int?>? remindBeforeMinutes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CourseScheduleRuleRecordsCompanion(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      userId: userId ?? this.userId,
      weekday: weekday ?? this.weekday,
      weekRuleType: weekRuleType ?? this.weekRuleType,
      startWeek: startWeek ?? this.startWeek,
      endWeek: endWeek ?? this.endWeek,
      intervalWeeks: intervalWeeks ?? this.intervalWeeks,
      weekNumbersJson: weekNumbersJson ?? this.weekNumbersJson,
      scheduleTemplateId: scheduleTemplateId ?? this.scheduleTemplateId,
      sectionIdsJson: sectionIdsJson ?? this.sectionIdsJson,
      startsAtMinute: startsAtMinute ?? this.startsAtMinute,
      endsAtMinute: endsAtMinute ?? this.endsAtMinute,
      remindBeforeMinutes: remindBeforeMinutes ?? this.remindBeforeMinutes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (courseId.present) {
      map['course_id'] = Variable<String>(courseId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (weekday.present) {
      map['weekday'] = Variable<int>(weekday.value);
    }
    if (weekRuleType.present) {
      map['week_rule_type'] = Variable<String>(weekRuleType.value);
    }
    if (startWeek.present) {
      map['start_week'] = Variable<int>(startWeek.value);
    }
    if (endWeek.present) {
      map['end_week'] = Variable<int>(endWeek.value);
    }
    if (intervalWeeks.present) {
      map['interval_weeks'] = Variable<int>(intervalWeeks.value);
    }
    if (weekNumbersJson.present) {
      map['week_numbers_json'] = Variable<String>(weekNumbersJson.value);
    }
    if (scheduleTemplateId.present) {
      map['schedule_template_id'] = Variable<String>(scheduleTemplateId.value);
    }
    if (sectionIdsJson.present) {
      map['section_ids_json'] = Variable<String>(sectionIdsJson.value);
    }
    if (startsAtMinute.present) {
      map['starts_at_minute'] = Variable<int>(startsAtMinute.value);
    }
    if (endsAtMinute.present) {
      map['ends_at_minute'] = Variable<int>(endsAtMinute.value);
    }
    if (remindBeforeMinutes.present) {
      map['remind_before_minutes'] = Variable<int>(remindBeforeMinutes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseScheduleRuleRecordsCompanion(')
          ..write('id: $id, ')
          ..write('courseId: $courseId, ')
          ..write('userId: $userId, ')
          ..write('weekday: $weekday, ')
          ..write('weekRuleType: $weekRuleType, ')
          ..write('startWeek: $startWeek, ')
          ..write('endWeek: $endWeek, ')
          ..write('intervalWeeks: $intervalWeeks, ')
          ..write('weekNumbersJson: $weekNumbersJson, ')
          ..write('scheduleTemplateId: $scheduleTemplateId, ')
          ..write('sectionIdsJson: $sectionIdsJson, ')
          ..write('startsAtMinute: $startsAtMinute, ')
          ..write('endsAtMinute: $endsAtMinute, ')
          ..write('remindBeforeMinutes: $remindBeforeMinutes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduleTemplateRecordsTable extends ScheduleTemplateRecords
    with TableInfo<$ScheduleTemplateRecordsTable, ScheduleTemplateRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleTemplateRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Asia/Shanghai'),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    timezone,
    isDefault,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_template_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleTemplateRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleTemplateRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleTemplateRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ScheduleTemplateRecordsTable createAlias(String alias) {
    return $ScheduleTemplateRecordsTable(attachedDatabase, alias);
  }
}

class ScheduleTemplateRecord extends DataClass
    implements Insertable<ScheduleTemplateRecord> {
  final String id;
  final String userId;
  final String name;
  final String timezone;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ScheduleTemplateRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.timezone,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['timezone'] = Variable<String>(timezone);
    map['is_default'] = Variable<bool>(isDefault);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ScheduleTemplateRecordsCompanion toCompanion(bool nullToAbsent) {
    return ScheduleTemplateRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      timezone: Value(timezone),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ScheduleTemplateRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleTemplateRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      timezone: serializer.fromJson<String>(json['timezone']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'timezone': serializer.toJson<String>(timezone),
      'isDefault': serializer.toJson<bool>(isDefault),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ScheduleTemplateRecord copyWith({
    String? id,
    String? userId,
    String? name,
    String? timezone,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ScheduleTemplateRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    timezone: timezone ?? this.timezone,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ScheduleTemplateRecord copyWithCompanion(
    ScheduleTemplateRecordsCompanion data,
  ) {
    return ScheduleTemplateRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleTemplateRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('timezone: $timezone, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    timezone,
    isDefault,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleTemplateRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.timezone == this.timezone &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ScheduleTemplateRecordsCompanion
    extends UpdateCompanion<ScheduleTemplateRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<String> timezone;
  final Value<bool> isDefault;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ScheduleTemplateRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.timezone = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduleTemplateRecordsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    this.timezone = const Value.absent(),
    this.isDefault = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ScheduleTemplateRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<String>? timezone,
    Expression<bool>? isDefault,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (timezone != null) 'timezone': timezone,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduleTemplateRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<String>? timezone,
    Value<bool>? isDefault,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ScheduleTemplateRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleTemplateRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('timezone: $timezone, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduleTemplateSegmentRecordsTable
    extends ScheduleTemplateSegmentRecords
    with
        TableInfo<
          $ScheduleTemplateSegmentRecordsTable,
          ScheduleTemplateSegmentRecord
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleTemplateSegmentRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES schedule_template_records (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsAtMinuteMeta = const VerificationMeta(
    'startsAtMinute',
  );
  @override
  late final GeneratedColumn<int> startsAtMinute = GeneratedColumn<int>(
    'starts_at_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMinuteMeta = const VerificationMeta(
    'endsAtMinute',
  );
  @override
  late final GeneratedColumn<int> endsAtMinute = GeneratedColumn<int>(
    'ends_at_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _segmentTypeMeta = const VerificationMeta(
    'segmentType',
  );
  @override
  late final GeneratedColumn<String> segmentType = GeneratedColumn<String>(
    'segment_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('classTime'),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    templateId,
    userId,
    name,
    startsAtMinute,
    endsAtMinute,
    segmentType,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_template_segment_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleTemplateSegmentRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('starts_at_minute')) {
      context.handle(
        _startsAtMinuteMeta,
        startsAtMinute.isAcceptableOrUnknown(
          data['starts_at_minute']!,
          _startsAtMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startsAtMinuteMeta);
    }
    if (data.containsKey('ends_at_minute')) {
      context.handle(
        _endsAtMinuteMeta,
        endsAtMinute.isAcceptableOrUnknown(
          data['ends_at_minute']!,
          _endsAtMinuteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endsAtMinuteMeta);
    }
    if (data.containsKey('segment_type')) {
      context.handle(
        _segmentTypeMeta,
        segmentType.isAcceptableOrUnknown(
          data['segment_type']!,
          _segmentTypeMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleTemplateSegmentRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleTemplateSegmentRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      startsAtMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_minute'],
      )!,
      endsAtMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_minute'],
      )!,
      segmentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}segment_type'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ScheduleTemplateSegmentRecordsTable createAlias(String alias) {
    return $ScheduleTemplateSegmentRecordsTable(attachedDatabase, alias);
  }
}

class ScheduleTemplateSegmentRecord extends DataClass
    implements Insertable<ScheduleTemplateSegmentRecord> {
  final String id;
  final String templateId;
  final String userId;
  final String name;
  final int startsAtMinute;
  final int endsAtMinute;
  final String segmentType;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ScheduleTemplateSegmentRecord({
    required this.id,
    required this.templateId,
    required this.userId,
    required this.name,
    required this.startsAtMinute,
    required this.endsAtMinute,
    required this.segmentType,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['template_id'] = Variable<String>(templateId);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['starts_at_minute'] = Variable<int>(startsAtMinute);
    map['ends_at_minute'] = Variable<int>(endsAtMinute);
    map['segment_type'] = Variable<String>(segmentType);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ScheduleTemplateSegmentRecordsCompanion toCompanion(bool nullToAbsent) {
    return ScheduleTemplateSegmentRecordsCompanion(
      id: Value(id),
      templateId: Value(templateId),
      userId: Value(userId),
      name: Value(name),
      startsAtMinute: Value(startsAtMinute),
      endsAtMinute: Value(endsAtMinute),
      segmentType: Value(segmentType),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ScheduleTemplateSegmentRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleTemplateSegmentRecord(
      id: serializer.fromJson<String>(json['id']),
      templateId: serializer.fromJson<String>(json['templateId']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      startsAtMinute: serializer.fromJson<int>(json['startsAtMinute']),
      endsAtMinute: serializer.fromJson<int>(json['endsAtMinute']),
      segmentType: serializer.fromJson<String>(json['segmentType']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateId': serializer.toJson<String>(templateId),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'startsAtMinute': serializer.toJson<int>(startsAtMinute),
      'endsAtMinute': serializer.toJson<int>(endsAtMinute),
      'segmentType': serializer.toJson<String>(segmentType),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ScheduleTemplateSegmentRecord copyWith({
    String? id,
    String? templateId,
    String? userId,
    String? name,
    int? startsAtMinute,
    int? endsAtMinute,
    String? segmentType,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ScheduleTemplateSegmentRecord(
    id: id ?? this.id,
    templateId: templateId ?? this.templateId,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    startsAtMinute: startsAtMinute ?? this.startsAtMinute,
    endsAtMinute: endsAtMinute ?? this.endsAtMinute,
    segmentType: segmentType ?? this.segmentType,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ScheduleTemplateSegmentRecord copyWithCompanion(
    ScheduleTemplateSegmentRecordsCompanion data,
  ) {
    return ScheduleTemplateSegmentRecord(
      id: data.id.present ? data.id.value : this.id,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      startsAtMinute: data.startsAtMinute.present
          ? data.startsAtMinute.value
          : this.startsAtMinute,
      endsAtMinute: data.endsAtMinute.present
          ? data.endsAtMinute.value
          : this.endsAtMinute,
      segmentType: data.segmentType.present
          ? data.segmentType.value
          : this.segmentType,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleTemplateSegmentRecord(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('startsAtMinute: $startsAtMinute, ')
          ..write('endsAtMinute: $endsAtMinute, ')
          ..write('segmentType: $segmentType, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    templateId,
    userId,
    name,
    startsAtMinute,
    endsAtMinute,
    segmentType,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleTemplateSegmentRecord &&
          other.id == this.id &&
          other.templateId == this.templateId &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.startsAtMinute == this.startsAtMinute &&
          other.endsAtMinute == this.endsAtMinute &&
          other.segmentType == this.segmentType &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ScheduleTemplateSegmentRecordsCompanion
    extends UpdateCompanion<ScheduleTemplateSegmentRecord> {
  final Value<String> id;
  final Value<String> templateId;
  final Value<String> userId;
  final Value<String> name;
  final Value<int> startsAtMinute;
  final Value<int> endsAtMinute;
  final Value<String> segmentType;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ScheduleTemplateSegmentRecordsCompanion({
    this.id = const Value.absent(),
    this.templateId = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.startsAtMinute = const Value.absent(),
    this.endsAtMinute = const Value.absent(),
    this.segmentType = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScheduleTemplateSegmentRecordsCompanion.insert({
    required String id,
    required String templateId,
    required String userId,
    required String name,
    required int startsAtMinute,
    required int endsAtMinute,
    this.segmentType = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       templateId = Value(templateId),
       userId = Value(userId),
       name = Value(name),
       startsAtMinute = Value(startsAtMinute),
       endsAtMinute = Value(endsAtMinute),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ScheduleTemplateSegmentRecord> custom({
    Expression<String>? id,
    Expression<String>? templateId,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<int>? startsAtMinute,
    Expression<int>? endsAtMinute,
    Expression<String>? segmentType,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateId != null) 'template_id': templateId,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (startsAtMinute != null) 'starts_at_minute': startsAtMinute,
      if (endsAtMinute != null) 'ends_at_minute': endsAtMinute,
      if (segmentType != null) 'segment_type': segmentType,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScheduleTemplateSegmentRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? templateId,
    Value<String>? userId,
    Value<String>? name,
    Value<int>? startsAtMinute,
    Value<int>? endsAtMinute,
    Value<String>? segmentType,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ScheduleTemplateSegmentRecordsCompanion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      startsAtMinute: startsAtMinute ?? this.startsAtMinute,
      endsAtMinute: endsAtMinute ?? this.endsAtMinute,
      segmentType: segmentType ?? this.segmentType,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startsAtMinute.present) {
      map['starts_at_minute'] = Variable<int>(startsAtMinute.value);
    }
    if (endsAtMinute.present) {
      map['ends_at_minute'] = Variable<int>(endsAtMinute.value);
    }
    if (segmentType.present) {
      map['segment_type'] = Variable<String>(segmentType.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleTemplateSegmentRecordsCompanion(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('startsAtMinute: $startsAtMinute, ')
          ..write('endsAtMinute: $endsAtMinute, ')
          ..write('segmentType: $segmentType, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SemesterRecordsTable extends SemesterRecords
    with TableInfo<$SemesterRecordsTable, SemesterRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SemesterRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstWeekStartDateMeta =
      const VerificationMeta('firstWeekStartDate');
  @override
  late final GeneratedColumn<DateTime> firstWeekStartDate =
      GeneratedColumn<DateTime>(
        'first_week_start_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _totalWeeksMeta = const VerificationMeta(
    'totalWeeks',
  );
  @override
  late final GeneratedColumn<int> totalWeeks = GeneratedColumn<int>(
    'total_weeks',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleTemplateIdMeta =
      const VerificationMeta('scheduleTemplateId');
  @override
  late final GeneratedColumn<String> scheduleTemplateId =
      GeneratedColumn<String>(
        'schedule_template_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isCurrentMeta = const VerificationMeta(
    'isCurrent',
  );
  @override
  late final GeneratedColumn<bool> isCurrent = GeneratedColumn<bool>(
    'is_current',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_current" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    name,
    firstWeekStartDate,
    totalWeeks,
    scheduleTemplateId,
    isCurrent,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'semester_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SemesterRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('first_week_start_date')) {
      context.handle(
        _firstWeekStartDateMeta,
        firstWeekStartDate.isAcceptableOrUnknown(
          data['first_week_start_date']!,
          _firstWeekStartDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstWeekStartDateMeta);
    }
    if (data.containsKey('total_weeks')) {
      context.handle(
        _totalWeeksMeta,
        totalWeeks.isAcceptableOrUnknown(data['total_weeks']!, _totalWeeksMeta),
      );
    } else if (isInserting) {
      context.missing(_totalWeeksMeta);
    }
    if (data.containsKey('schedule_template_id')) {
      context.handle(
        _scheduleTemplateIdMeta,
        scheduleTemplateId.isAcceptableOrUnknown(
          data['schedule_template_id']!,
          _scheduleTemplateIdMeta,
        ),
      );
    }
    if (data.containsKey('is_current')) {
      context.handle(
        _isCurrentMeta,
        isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SemesterRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SemesterRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      firstWeekStartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_week_start_date'],
      )!,
      totalWeeks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_weeks'],
      )!,
      scheduleTemplateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_template_id'],
      ),
      isCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_current'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $SemesterRecordsTable createAlias(String alias) {
    return $SemesterRecordsTable(attachedDatabase, alias);
  }
}

class SemesterRecord extends DataClass implements Insertable<SemesterRecord> {
  final String id;
  final String userId;
  final String name;
  final DateTime firstWeekStartDate;
  final int totalWeeks;
  final String? scheduleTemplateId;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const SemesterRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.firstWeekStartDate,
    required this.totalWeeks,
    this.scheduleTemplateId,
    required this.isCurrent,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['name'] = Variable<String>(name);
    map['first_week_start_date'] = Variable<DateTime>(firstWeekStartDate);
    map['total_weeks'] = Variable<int>(totalWeeks);
    if (!nullToAbsent || scheduleTemplateId != null) {
      map['schedule_template_id'] = Variable<String>(scheduleTemplateId);
    }
    map['is_current'] = Variable<bool>(isCurrent);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  SemesterRecordsCompanion toCompanion(bool nullToAbsent) {
    return SemesterRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      firstWeekStartDate: Value(firstWeekStartDate),
      totalWeeks: Value(totalWeeks),
      scheduleTemplateId: scheduleTemplateId == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduleTemplateId),
      isCurrent: Value(isCurrent),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory SemesterRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SemesterRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      firstWeekStartDate: serializer.fromJson<DateTime>(
        json['firstWeekStartDate'],
      ),
      totalWeeks: serializer.fromJson<int>(json['totalWeeks']),
      scheduleTemplateId: serializer.fromJson<String?>(
        json['scheduleTemplateId'],
      ),
      isCurrent: serializer.fromJson<bool>(json['isCurrent']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'name': serializer.toJson<String>(name),
      'firstWeekStartDate': serializer.toJson<DateTime>(firstWeekStartDate),
      'totalWeeks': serializer.toJson<int>(totalWeeks),
      'scheduleTemplateId': serializer.toJson<String?>(scheduleTemplateId),
      'isCurrent': serializer.toJson<bool>(isCurrent),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  SemesterRecord copyWith({
    String? id,
    String? userId,
    String? name,
    DateTime? firstWeekStartDate,
    int? totalWeeks,
    Value<String?> scheduleTemplateId = const Value.absent(),
    bool? isCurrent,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => SemesterRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    firstWeekStartDate: firstWeekStartDate ?? this.firstWeekStartDate,
    totalWeeks: totalWeeks ?? this.totalWeeks,
    scheduleTemplateId: scheduleTemplateId.present
        ? scheduleTemplateId.value
        : this.scheduleTemplateId,
    isCurrent: isCurrent ?? this.isCurrent,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  SemesterRecord copyWithCompanion(SemesterRecordsCompanion data) {
    return SemesterRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      firstWeekStartDate: data.firstWeekStartDate.present
          ? data.firstWeekStartDate.value
          : this.firstWeekStartDate,
      totalWeeks: data.totalWeeks.present
          ? data.totalWeeks.value
          : this.totalWeeks,
      scheduleTemplateId: data.scheduleTemplateId.present
          ? data.scheduleTemplateId.value
          : this.scheduleTemplateId,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SemesterRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('firstWeekStartDate: $firstWeekStartDate, ')
          ..write('totalWeeks: $totalWeeks, ')
          ..write('scheduleTemplateId: $scheduleTemplateId, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    name,
    firstWeekStartDate,
    totalWeeks,
    scheduleTemplateId,
    isCurrent,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SemesterRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.firstWeekStartDate == this.firstWeekStartDate &&
          other.totalWeeks == this.totalWeeks &&
          other.scheduleTemplateId == this.scheduleTemplateId &&
          other.isCurrent == this.isCurrent &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class SemesterRecordsCompanion extends UpdateCompanion<SemesterRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> name;
  final Value<DateTime> firstWeekStartDate;
  final Value<int> totalWeeks;
  final Value<String?> scheduleTemplateId;
  final Value<bool> isCurrent;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const SemesterRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.firstWeekStartDate = const Value.absent(),
    this.totalWeeks = const Value.absent(),
    this.scheduleTemplateId = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SemesterRecordsCompanion.insert({
    required String id,
    required String userId,
    required String name,
    required DateTime firstWeekStartDate,
    required int totalWeeks,
    this.scheduleTemplateId = const Value.absent(),
    this.isCurrent = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       name = Value(name),
       firstWeekStartDate = Value(firstWeekStartDate),
       totalWeeks = Value(totalWeeks),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SemesterRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? name,
    Expression<DateTime>? firstWeekStartDate,
    Expression<int>? totalWeeks,
    Expression<String>? scheduleTemplateId,
    Expression<bool>? isCurrent,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (firstWeekStartDate != null)
        'first_week_start_date': firstWeekStartDate,
      if (totalWeeks != null) 'total_weeks': totalWeeks,
      if (scheduleTemplateId != null)
        'schedule_template_id': scheduleTemplateId,
      if (isCurrent != null) 'is_current': isCurrent,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SemesterRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? name,
    Value<DateTime>? firstWeekStartDate,
    Value<int>? totalWeeks,
    Value<String?>? scheduleTemplateId,
    Value<bool>? isCurrent,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return SemesterRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      firstWeekStartDate: firstWeekStartDate ?? this.firstWeekStartDate,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      scheduleTemplateId: scheduleTemplateId ?? this.scheduleTemplateId,
      isCurrent: isCurrent ?? this.isCurrent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (firstWeekStartDate.present) {
      map['first_week_start_date'] = Variable<DateTime>(
        firstWeekStartDate.value,
      );
    }
    if (totalWeeks.present) {
      map['total_weeks'] = Variable<int>(totalWeeks.value);
    }
    if (scheduleTemplateId.present) {
      map['schedule_template_id'] = Variable<String>(scheduleTemplateId.value);
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<bool>(isCurrent.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SemesterRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('firstWeekStartDate: $firstWeekStartDate, ')
          ..write('totalWeeks: $totalWeeks, ')
          ..write('scheduleTemplateId: $scheduleTemplateId, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyItemOverrideRecordsTable extends DailyItemOverrideRecords
    with TableInfo<$DailyItemOverrideRecordsTable, DailyItemOverrideRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyItemOverrideRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemTypeMeta = const VerificationMeta(
    'itemType',
  );
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
    'item_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plannedStartMinuteMeta =
      const VerificationMeta('plannedStartMinute');
  @override
  late final GeneratedColumn<int> plannedStartMinute = GeneratedColumn<int>(
    'planned_start_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedEndMinuteMeta = const VerificationMeta(
    'plannedEndMinute',
  );
  @override
  late final GeneratedColumn<int> plannedEndMinute = GeneratedColumn<int>(
    'planned_end_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reminderMinuteOfDayMeta =
      const VerificationMeta('reminderMinuteOfDay');
  @override
  late final GeneratedColumn<int> reminderMinuteOfDay = GeneratedColumn<int>(
    'reminder_minute_of_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetDurationSecondsMeta =
      const VerificationMeta('targetDurationSeconds');
  @override
  late final GeneratedColumn<int> targetDurationSeconds = GeneratedColumn<int>(
    'target_duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _temporaryClassroomMeta =
      const VerificationMeta('temporaryClassroom');
  @override
  late final GeneratedColumn<String> temporaryClassroom =
      GeneratedColumn<String>(
        'temporary_classroom',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    itemType,
    itemId,
    localDate,
    action,
    plannedStartMinute,
    plannedEndMinute,
    reminderMinuteOfDay,
    targetDurationSeconds,
    temporaryClassroom,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_item_override_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyItemOverrideRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('item_type')) {
      context.handle(
        _itemTypeMeta,
        itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_itemTypeMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('planned_start_minute')) {
      context.handle(
        _plannedStartMinuteMeta,
        plannedStartMinute.isAcceptableOrUnknown(
          data['planned_start_minute']!,
          _plannedStartMinuteMeta,
        ),
      );
    }
    if (data.containsKey('planned_end_minute')) {
      context.handle(
        _plannedEndMinuteMeta,
        plannedEndMinute.isAcceptableOrUnknown(
          data['planned_end_minute']!,
          _plannedEndMinuteMeta,
        ),
      );
    }
    if (data.containsKey('reminder_minute_of_day')) {
      context.handle(
        _reminderMinuteOfDayMeta,
        reminderMinuteOfDay.isAcceptableOrUnknown(
          data['reminder_minute_of_day']!,
          _reminderMinuteOfDayMeta,
        ),
      );
    }
    if (data.containsKey('target_duration_seconds')) {
      context.handle(
        _targetDurationSecondsMeta,
        targetDurationSeconds.isAcceptableOrUnknown(
          data['target_duration_seconds']!,
          _targetDurationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('temporary_classroom')) {
      context.handle(
        _temporaryClassroomMeta,
        temporaryClassroom.isAcceptableOrUnknown(
          data['temporary_classroom']!,
          _temporaryClassroomMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, itemType, itemId, localDate},
  ];
  @override
  DailyItemOverrideRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyItemOverrideRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      itemType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_type'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      plannedStartMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_start_minute'],
      ),
      plannedEndMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_end_minute'],
      ),
      reminderMinuteOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_minute_of_day'],
      ),
      targetDurationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_duration_seconds'],
      ),
      temporaryClassroom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}temporary_classroom'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $DailyItemOverrideRecordsTable createAlias(String alias) {
    return $DailyItemOverrideRecordsTable(attachedDatabase, alias);
  }
}

class DailyItemOverrideRecord extends DataClass
    implements Insertable<DailyItemOverrideRecord> {
  final String id;
  final String userId;
  final String itemType;
  final String itemId;
  final String localDate;
  final String action;
  final int? plannedStartMinute;
  final int? plannedEndMinute;
  final int? reminderMinuteOfDay;
  final int? targetDurationSeconds;
  final String? temporaryClassroom;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const DailyItemOverrideRecord({
    required this.id,
    required this.userId,
    required this.itemType,
    required this.itemId,
    required this.localDate,
    required this.action,
    this.plannedStartMinute,
    this.plannedEndMinute,
    this.reminderMinuteOfDay,
    this.targetDurationSeconds,
    this.temporaryClassroom,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['item_type'] = Variable<String>(itemType);
    map['item_id'] = Variable<String>(itemId);
    map['local_date'] = Variable<String>(localDate);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || plannedStartMinute != null) {
      map['planned_start_minute'] = Variable<int>(plannedStartMinute);
    }
    if (!nullToAbsent || plannedEndMinute != null) {
      map['planned_end_minute'] = Variable<int>(plannedEndMinute);
    }
    if (!nullToAbsent || reminderMinuteOfDay != null) {
      map['reminder_minute_of_day'] = Variable<int>(reminderMinuteOfDay);
    }
    if (!nullToAbsent || targetDurationSeconds != null) {
      map['target_duration_seconds'] = Variable<int>(targetDurationSeconds);
    }
    if (!nullToAbsent || temporaryClassroom != null) {
      map['temporary_classroom'] = Variable<String>(temporaryClassroom);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  DailyItemOverrideRecordsCompanion toCompanion(bool nullToAbsent) {
    return DailyItemOverrideRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      itemType: Value(itemType),
      itemId: Value(itemId),
      localDate: Value(localDate),
      action: Value(action),
      plannedStartMinute: plannedStartMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedStartMinute),
      plannedEndMinute: plannedEndMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedEndMinute),
      reminderMinuteOfDay: reminderMinuteOfDay == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderMinuteOfDay),
      targetDurationSeconds: targetDurationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDurationSeconds),
      temporaryClassroom: temporaryClassroom == null && nullToAbsent
          ? const Value.absent()
          : Value(temporaryClassroom),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory DailyItemOverrideRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyItemOverrideRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      itemType: serializer.fromJson<String>(json['itemType']),
      itemId: serializer.fromJson<String>(json['itemId']),
      localDate: serializer.fromJson<String>(json['localDate']),
      action: serializer.fromJson<String>(json['action']),
      plannedStartMinute: serializer.fromJson<int?>(json['plannedStartMinute']),
      plannedEndMinute: serializer.fromJson<int?>(json['plannedEndMinute']),
      reminderMinuteOfDay: serializer.fromJson<int?>(
        json['reminderMinuteOfDay'],
      ),
      targetDurationSeconds: serializer.fromJson<int?>(
        json['targetDurationSeconds'],
      ),
      temporaryClassroom: serializer.fromJson<String?>(
        json['temporaryClassroom'],
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'itemType': serializer.toJson<String>(itemType),
      'itemId': serializer.toJson<String>(itemId),
      'localDate': serializer.toJson<String>(localDate),
      'action': serializer.toJson<String>(action),
      'plannedStartMinute': serializer.toJson<int?>(plannedStartMinute),
      'plannedEndMinute': serializer.toJson<int?>(plannedEndMinute),
      'reminderMinuteOfDay': serializer.toJson<int?>(reminderMinuteOfDay),
      'targetDurationSeconds': serializer.toJson<int?>(targetDurationSeconds),
      'temporaryClassroom': serializer.toJson<String?>(temporaryClassroom),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  DailyItemOverrideRecord copyWith({
    String? id,
    String? userId,
    String? itemType,
    String? itemId,
    String? localDate,
    String? action,
    Value<int?> plannedStartMinute = const Value.absent(),
    Value<int?> plannedEndMinute = const Value.absent(),
    Value<int?> reminderMinuteOfDay = const Value.absent(),
    Value<int?> targetDurationSeconds = const Value.absent(),
    Value<String?> temporaryClassroom = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => DailyItemOverrideRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    itemType: itemType ?? this.itemType,
    itemId: itemId ?? this.itemId,
    localDate: localDate ?? this.localDate,
    action: action ?? this.action,
    plannedStartMinute: plannedStartMinute.present
        ? plannedStartMinute.value
        : this.plannedStartMinute,
    plannedEndMinute: plannedEndMinute.present
        ? plannedEndMinute.value
        : this.plannedEndMinute,
    reminderMinuteOfDay: reminderMinuteOfDay.present
        ? reminderMinuteOfDay.value
        : this.reminderMinuteOfDay,
    targetDurationSeconds: targetDurationSeconds.present
        ? targetDurationSeconds.value
        : this.targetDurationSeconds,
    temporaryClassroom: temporaryClassroom.present
        ? temporaryClassroom.value
        : this.temporaryClassroom,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  DailyItemOverrideRecord copyWithCompanion(
    DailyItemOverrideRecordsCompanion data,
  ) {
    return DailyItemOverrideRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      action: data.action.present ? data.action.value : this.action,
      plannedStartMinute: data.plannedStartMinute.present
          ? data.plannedStartMinute.value
          : this.plannedStartMinute,
      plannedEndMinute: data.plannedEndMinute.present
          ? data.plannedEndMinute.value
          : this.plannedEndMinute,
      reminderMinuteOfDay: data.reminderMinuteOfDay.present
          ? data.reminderMinuteOfDay.value
          : this.reminderMinuteOfDay,
      targetDurationSeconds: data.targetDurationSeconds.present
          ? data.targetDurationSeconds.value
          : this.targetDurationSeconds,
      temporaryClassroom: data.temporaryClassroom.present
          ? data.temporaryClassroom.value
          : this.temporaryClassroom,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyItemOverrideRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('itemType: $itemType, ')
          ..write('itemId: $itemId, ')
          ..write('localDate: $localDate, ')
          ..write('action: $action, ')
          ..write('plannedStartMinute: $plannedStartMinute, ')
          ..write('plannedEndMinute: $plannedEndMinute, ')
          ..write('reminderMinuteOfDay: $reminderMinuteOfDay, ')
          ..write('targetDurationSeconds: $targetDurationSeconds, ')
          ..write('temporaryClassroom: $temporaryClassroom, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    itemType,
    itemId,
    localDate,
    action,
    plannedStartMinute,
    plannedEndMinute,
    reminderMinuteOfDay,
    targetDurationSeconds,
    temporaryClassroom,
    notes,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyItemOverrideRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.itemType == this.itemType &&
          other.itemId == this.itemId &&
          other.localDate == this.localDate &&
          other.action == this.action &&
          other.plannedStartMinute == this.plannedStartMinute &&
          other.plannedEndMinute == this.plannedEndMinute &&
          other.reminderMinuteOfDay == this.reminderMinuteOfDay &&
          other.targetDurationSeconds == this.targetDurationSeconds &&
          other.temporaryClassroom == this.temporaryClassroom &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class DailyItemOverrideRecordsCompanion
    extends UpdateCompanion<DailyItemOverrideRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> itemType;
  final Value<String> itemId;
  final Value<String> localDate;
  final Value<String> action;
  final Value<int?> plannedStartMinute;
  final Value<int?> plannedEndMinute;
  final Value<int?> reminderMinuteOfDay;
  final Value<int?> targetDurationSeconds;
  final Value<String?> temporaryClassroom;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const DailyItemOverrideRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.itemType = const Value.absent(),
    this.itemId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.action = const Value.absent(),
    this.plannedStartMinute = const Value.absent(),
    this.plannedEndMinute = const Value.absent(),
    this.reminderMinuteOfDay = const Value.absent(),
    this.targetDurationSeconds = const Value.absent(),
    this.temporaryClassroom = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyItemOverrideRecordsCompanion.insert({
    required String id,
    required String userId,
    required String itemType,
    required String itemId,
    required String localDate,
    required String action,
    this.plannedStartMinute = const Value.absent(),
    this.plannedEndMinute = const Value.absent(),
    this.reminderMinuteOfDay = const Value.absent(),
    this.targetDurationSeconds = const Value.absent(),
    this.temporaryClassroom = const Value.absent(),
    this.notes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       itemType = Value(itemType),
       itemId = Value(itemId),
       localDate = Value(localDate),
       action = Value(action),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DailyItemOverrideRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? itemType,
    Expression<String>? itemId,
    Expression<String>? localDate,
    Expression<String>? action,
    Expression<int>? plannedStartMinute,
    Expression<int>? plannedEndMinute,
    Expression<int>? reminderMinuteOfDay,
    Expression<int>? targetDurationSeconds,
    Expression<String>? temporaryClassroom,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (itemType != null) 'item_type': itemType,
      if (itemId != null) 'item_id': itemId,
      if (localDate != null) 'local_date': localDate,
      if (action != null) 'action': action,
      if (plannedStartMinute != null)
        'planned_start_minute': plannedStartMinute,
      if (plannedEndMinute != null) 'planned_end_minute': plannedEndMinute,
      if (reminderMinuteOfDay != null)
        'reminder_minute_of_day': reminderMinuteOfDay,
      if (targetDurationSeconds != null)
        'target_duration_seconds': targetDurationSeconds,
      if (temporaryClassroom != null) 'temporary_classroom': temporaryClassroom,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyItemOverrideRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? itemType,
    Value<String>? itemId,
    Value<String>? localDate,
    Value<String>? action,
    Value<int?>? plannedStartMinute,
    Value<int?>? plannedEndMinute,
    Value<int?>? reminderMinuteOfDay,
    Value<int?>? targetDurationSeconds,
    Value<String?>? temporaryClassroom,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return DailyItemOverrideRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      itemType: itemType ?? this.itemType,
      itemId: itemId ?? this.itemId,
      localDate: localDate ?? this.localDate,
      action: action ?? this.action,
      plannedStartMinute: plannedStartMinute ?? this.plannedStartMinute,
      plannedEndMinute: plannedEndMinute ?? this.plannedEndMinute,
      reminderMinuteOfDay: reminderMinuteOfDay ?? this.reminderMinuteOfDay,
      targetDurationSeconds:
          targetDurationSeconds ?? this.targetDurationSeconds,
      temporaryClassroom: temporaryClassroom ?? this.temporaryClassroom,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (plannedStartMinute.present) {
      map['planned_start_minute'] = Variable<int>(plannedStartMinute.value);
    }
    if (plannedEndMinute.present) {
      map['planned_end_minute'] = Variable<int>(plannedEndMinute.value);
    }
    if (reminderMinuteOfDay.present) {
      map['reminder_minute_of_day'] = Variable<int>(reminderMinuteOfDay.value);
    }
    if (targetDurationSeconds.present) {
      map['target_duration_seconds'] = Variable<int>(
        targetDurationSeconds.value,
      );
    }
    if (temporaryClassroom.present) {
      map['temporary_classroom'] = Variable<String>(temporaryClassroom.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyItemOverrideRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('itemType: $itemType, ')
          ..write('itemId: $itemId, ')
          ..write('localDate: $localDate, ')
          ..write('action: $action, ')
          ..write('plannedStartMinute: $plannedStartMinute, ')
          ..write('plannedEndMinute: $plannedEndMinute, ')
          ..write('reminderMinuteOfDay: $reminderMinuteOfDay, ')
          ..write('targetDurationSeconds: $targetDurationSeconds, ')
          ..write('temporaryClassroom: $temporaryClassroom, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReminderRuleRecordsTable extends ReminderRuleRecords
    with TableInfo<$ReminderRuleRecordsTable, ReminderRuleRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReminderRuleRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerTypeMeta = const VerificationMeta(
    'ownerType',
  );
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
    'owner_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reminderKindMeta = const VerificationMeta(
    'reminderKind',
  );
  @override
  late final GeneratedColumn<String> reminderKind = GeneratedColumn<String>(
    'reminder_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _scheduledMinuteOfDayMeta =
      const VerificationMeta('scheduledMinuteOfDay');
  @override
  late final GeneratedColumn<int> scheduledMinuteOfDay = GeneratedColumn<int>(
    'scheduled_minute_of_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remindBeforeMinutesMeta =
      const VerificationMeta('remindBeforeMinutes');
  @override
  late final GeneratedColumn<int> remindBeforeMinutes = GeneratedColumn<int>(
    'remind_before_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Asia/Shanghai'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    ownerType,
    ownerId,
    reminderKind,
    enabled,
    scheduledMinuteOfDay,
    remindBeforeMinutes,
    localDate,
    timezone,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminder_rule_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReminderRuleRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(
        _ownerTypeMeta,
        ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('reminder_kind')) {
      context.handle(
        _reminderKindMeta,
        reminderKind.isAcceptableOrUnknown(
          data['reminder_kind']!,
          _reminderKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reminderKindMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('scheduled_minute_of_day')) {
      context.handle(
        _scheduledMinuteOfDayMeta,
        scheduledMinuteOfDay.isAcceptableOrUnknown(
          data['scheduled_minute_of_day']!,
          _scheduledMinuteOfDayMeta,
        ),
      );
    }
    if (data.containsKey('remind_before_minutes')) {
      context.handle(
        _remindBeforeMinutesMeta,
        remindBeforeMinutes.isAcceptableOrUnknown(
          data['remind_before_minutes']!,
          _remindBeforeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReminderRuleRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReminderRuleRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      ownerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_type'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      reminderKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminder_kind'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      scheduledMinuteOfDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scheduled_minute_of_day'],
      ),
      remindBeforeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_before_minutes'],
      ),
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      ),
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $ReminderRuleRecordsTable createAlias(String alias) {
    return $ReminderRuleRecordsTable(attachedDatabase, alias);
  }
}

class ReminderRuleRecord extends DataClass
    implements Insertable<ReminderRuleRecord> {
  final String id;
  final String userId;
  final String ownerType;
  final String ownerId;
  final String reminderKind;
  final bool enabled;
  final int? scheduledMinuteOfDay;
  final int? remindBeforeMinutes;
  final String? localDate;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ReminderRuleRecord({
    required this.id,
    required this.userId,
    required this.ownerType,
    required this.ownerId,
    required this.reminderKind,
    required this.enabled,
    this.scheduledMinuteOfDay,
    this.remindBeforeMinutes,
    this.localDate,
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['owner_type'] = Variable<String>(ownerType);
    map['owner_id'] = Variable<String>(ownerId);
    map['reminder_kind'] = Variable<String>(reminderKind);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || scheduledMinuteOfDay != null) {
      map['scheduled_minute_of_day'] = Variable<int>(scheduledMinuteOfDay);
    }
    if (!nullToAbsent || remindBeforeMinutes != null) {
      map['remind_before_minutes'] = Variable<int>(remindBeforeMinutes);
    }
    if (!nullToAbsent || localDate != null) {
      map['local_date'] = Variable<String>(localDate);
    }
    map['timezone'] = Variable<String>(timezone);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ReminderRuleRecordsCompanion toCompanion(bool nullToAbsent) {
    return ReminderRuleRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      ownerType: Value(ownerType),
      ownerId: Value(ownerId),
      reminderKind: Value(reminderKind),
      enabled: Value(enabled),
      scheduledMinuteOfDay: scheduledMinuteOfDay == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledMinuteOfDay),
      remindBeforeMinutes: remindBeforeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(remindBeforeMinutes),
      localDate: localDate == null && nullToAbsent
          ? const Value.absent()
          : Value(localDate),
      timezone: Value(timezone),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ReminderRuleRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReminderRuleRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      reminderKind: serializer.fromJson<String>(json['reminderKind']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      scheduledMinuteOfDay: serializer.fromJson<int?>(
        json['scheduledMinuteOfDay'],
      ),
      remindBeforeMinutes: serializer.fromJson<int?>(
        json['remindBeforeMinutes'],
      ),
      localDate: serializer.fromJson<String?>(json['localDate']),
      timezone: serializer.fromJson<String>(json['timezone']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'ownerType': serializer.toJson<String>(ownerType),
      'ownerId': serializer.toJson<String>(ownerId),
      'reminderKind': serializer.toJson<String>(reminderKind),
      'enabled': serializer.toJson<bool>(enabled),
      'scheduledMinuteOfDay': serializer.toJson<int?>(scheduledMinuteOfDay),
      'remindBeforeMinutes': serializer.toJson<int?>(remindBeforeMinutes),
      'localDate': serializer.toJson<String?>(localDate),
      'timezone': serializer.toJson<String>(timezone),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ReminderRuleRecord copyWith({
    String? id,
    String? userId,
    String? ownerType,
    String? ownerId,
    String? reminderKind,
    bool? enabled,
    Value<int?> scheduledMinuteOfDay = const Value.absent(),
    Value<int?> remindBeforeMinutes = const Value.absent(),
    Value<String?> localDate = const Value.absent(),
    String? timezone,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => ReminderRuleRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    ownerType: ownerType ?? this.ownerType,
    ownerId: ownerId ?? this.ownerId,
    reminderKind: reminderKind ?? this.reminderKind,
    enabled: enabled ?? this.enabled,
    scheduledMinuteOfDay: scheduledMinuteOfDay.present
        ? scheduledMinuteOfDay.value
        : this.scheduledMinuteOfDay,
    remindBeforeMinutes: remindBeforeMinutes.present
        ? remindBeforeMinutes.value
        : this.remindBeforeMinutes,
    localDate: localDate.present ? localDate.value : this.localDate,
    timezone: timezone ?? this.timezone,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  ReminderRuleRecord copyWithCompanion(ReminderRuleRecordsCompanion data) {
    return ReminderRuleRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      reminderKind: data.reminderKind.present
          ? data.reminderKind.value
          : this.reminderKind,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      scheduledMinuteOfDay: data.scheduledMinuteOfDay.present
          ? data.scheduledMinuteOfDay.value
          : this.scheduledMinuteOfDay,
      remindBeforeMinutes: data.remindBeforeMinutes.present
          ? data.remindBeforeMinutes.value
          : this.remindBeforeMinutes,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReminderRuleRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('reminderKind: $reminderKind, ')
          ..write('enabled: $enabled, ')
          ..write('scheduledMinuteOfDay: $scheduledMinuteOfDay, ')
          ..write('remindBeforeMinutes: $remindBeforeMinutes, ')
          ..write('localDate: $localDate, ')
          ..write('timezone: $timezone, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    ownerType,
    ownerId,
    reminderKind,
    enabled,
    scheduledMinuteOfDay,
    remindBeforeMinutes,
    localDate,
    timezone,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReminderRuleRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.ownerType == this.ownerType &&
          other.ownerId == this.ownerId &&
          other.reminderKind == this.reminderKind &&
          other.enabled == this.enabled &&
          other.scheduledMinuteOfDay == this.scheduledMinuteOfDay &&
          other.remindBeforeMinutes == this.remindBeforeMinutes &&
          other.localDate == this.localDate &&
          other.timezone == this.timezone &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ReminderRuleRecordsCompanion extends UpdateCompanion<ReminderRuleRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> ownerType;
  final Value<String> ownerId;
  final Value<String> reminderKind;
  final Value<bool> enabled;
  final Value<int?> scheduledMinuteOfDay;
  final Value<int?> remindBeforeMinutes;
  final Value<String?> localDate;
  final Value<String> timezone;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ReminderRuleRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.reminderKind = const Value.absent(),
    this.enabled = const Value.absent(),
    this.scheduledMinuteOfDay = const Value.absent(),
    this.remindBeforeMinutes = const Value.absent(),
    this.localDate = const Value.absent(),
    this.timezone = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReminderRuleRecordsCompanion.insert({
    required String id,
    required String userId,
    required String ownerType,
    required String ownerId,
    required String reminderKind,
    this.enabled = const Value.absent(),
    this.scheduledMinuteOfDay = const Value.absent(),
    this.remindBeforeMinutes = const Value.absent(),
    this.localDate = const Value.absent(),
    this.timezone = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       ownerType = Value(ownerType),
       ownerId = Value(ownerId),
       reminderKind = Value(reminderKind),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ReminderRuleRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? ownerType,
    Expression<String>? ownerId,
    Expression<String>? reminderKind,
    Expression<bool>? enabled,
    Expression<int>? scheduledMinuteOfDay,
    Expression<int>? remindBeforeMinutes,
    Expression<String>? localDate,
    Expression<String>? timezone,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (ownerType != null) 'owner_type': ownerType,
      if (ownerId != null) 'owner_id': ownerId,
      if (reminderKind != null) 'reminder_kind': reminderKind,
      if (enabled != null) 'enabled': enabled,
      if (scheduledMinuteOfDay != null)
        'scheduled_minute_of_day': scheduledMinuteOfDay,
      if (remindBeforeMinutes != null)
        'remind_before_minutes': remindBeforeMinutes,
      if (localDate != null) 'local_date': localDate,
      if (timezone != null) 'timezone': timezone,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReminderRuleRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? ownerType,
    Value<String>? ownerId,
    Value<String>? reminderKind,
    Value<bool>? enabled,
    Value<int?>? scheduledMinuteOfDay,
    Value<int?>? remindBeforeMinutes,
    Value<String?>? localDate,
    Value<String>? timezone,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return ReminderRuleRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      reminderKind: reminderKind ?? this.reminderKind,
      enabled: enabled ?? this.enabled,
      scheduledMinuteOfDay: scheduledMinuteOfDay ?? this.scheduledMinuteOfDay,
      remindBeforeMinutes: remindBeforeMinutes ?? this.remindBeforeMinutes,
      localDate: localDate ?? this.localDate,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (reminderKind.present) {
      map['reminder_kind'] = Variable<String>(reminderKind.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (scheduledMinuteOfDay.present) {
      map['scheduled_minute_of_day'] = Variable<int>(
        scheduledMinuteOfDay.value,
      );
    }
    if (remindBeforeMinutes.present) {
      map['remind_before_minutes'] = Variable<int>(remindBeforeMinutes.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReminderRuleRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('reminderKind: $reminderKind, ')
          ..write('enabled: $enabled, ')
          ..write('scheduledMinuteOfDay: $scheduledMinuteOfDay, ')
          ..write('remindBeforeMinutes: $remindBeforeMinutes, ')
          ..write('localDate: $localDate, ')
          ..write('timezone: $timezone, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlarmRuleRecordsTable extends AlarmRuleRecords
    with TableInfo<$AlarmRuleRecordsTable, AlarmRuleRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmRuleRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerTypeMeta = const VerificationMeta(
    'ownerType',
  );
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
    'owner_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _behaviorMeta = const VerificationMeta(
    'behavior',
  );
  @override
  late final GeneratedColumn<String> behavior = GeneratedColumn<String>(
    'behavior',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('once'),
  );
  static const VerificationMeta _soundNameMeta = const VerificationMeta(
    'soundName',
  );
  @override
  late final GeneratedColumn<String> soundName = GeneratedColumn<String>(
    'sound_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snoozeMinutesMeta = const VerificationMeta(
    'snoozeMinutes',
  );
  @override
  late final GeneratedColumn<int> snoozeMinutes = GeneratedColumn<int>(
    'snooze_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repeatIntervalMinutesMeta =
      const VerificationMeta('repeatIntervalMinutes');
  @override
  late final GeneratedColumn<int> repeatIntervalMinutes = GeneratedColumn<int>(
    'repeat_interval_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxRingSecondsMeta = const VerificationMeta(
    'maxRingSeconds',
  );
  @override
  late final GeneratedColumn<int> maxRingSeconds = GeneratedColumn<int>(
    'max_ring_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    ownerType,
    ownerId,
    enabled,
    behavior,
    soundName,
    snoozeMinutes,
    repeatIntervalMinutes,
    maxRingSeconds,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_rule_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmRuleRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(
        _ownerTypeMeta,
        ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('behavior')) {
      context.handle(
        _behaviorMeta,
        behavior.isAcceptableOrUnknown(data['behavior']!, _behaviorMeta),
      );
    }
    if (data.containsKey('sound_name')) {
      context.handle(
        _soundNameMeta,
        soundName.isAcceptableOrUnknown(data['sound_name']!, _soundNameMeta),
      );
    }
    if (data.containsKey('snooze_minutes')) {
      context.handle(
        _snoozeMinutesMeta,
        snoozeMinutes.isAcceptableOrUnknown(
          data['snooze_minutes']!,
          _snoozeMinutesMeta,
        ),
      );
    }
    if (data.containsKey('repeat_interval_minutes')) {
      context.handle(
        _repeatIntervalMinutesMeta,
        repeatIntervalMinutes.isAcceptableOrUnknown(
          data['repeat_interval_minutes']!,
          _repeatIntervalMinutesMeta,
        ),
      );
    }
    if (data.containsKey('max_ring_seconds')) {
      context.handle(
        _maxRingSecondsMeta,
        maxRingSeconds.isAcceptableOrUnknown(
          data['max_ring_seconds']!,
          _maxRingSecondsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmRuleRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmRuleRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      ownerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_type'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      behavior: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}behavior'],
      )!,
      soundName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sound_name'],
      ),
      snoozeMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snooze_minutes'],
      ),
      repeatIntervalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeat_interval_minutes'],
      ),
      maxRingSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_ring_seconds'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $AlarmRuleRecordsTable createAlias(String alias) {
    return $AlarmRuleRecordsTable(attachedDatabase, alias);
  }
}

class AlarmRuleRecord extends DataClass implements Insertable<AlarmRuleRecord> {
  final String id;
  final String userId;
  final String ownerType;
  final String ownerId;
  final bool enabled;
  final String behavior;
  final String? soundName;
  final int? snoozeMinutes;
  final int? repeatIntervalMinutes;
  final int? maxRingSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const AlarmRuleRecord({
    required this.id,
    required this.userId,
    required this.ownerType,
    required this.ownerId,
    required this.enabled,
    required this.behavior,
    this.soundName,
    this.snoozeMinutes,
    this.repeatIntervalMinutes,
    this.maxRingSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['owner_type'] = Variable<String>(ownerType);
    map['owner_id'] = Variable<String>(ownerId);
    map['enabled'] = Variable<bool>(enabled);
    map['behavior'] = Variable<String>(behavior);
    if (!nullToAbsent || soundName != null) {
      map['sound_name'] = Variable<String>(soundName);
    }
    if (!nullToAbsent || snoozeMinutes != null) {
      map['snooze_minutes'] = Variable<int>(snoozeMinutes);
    }
    if (!nullToAbsent || repeatIntervalMinutes != null) {
      map['repeat_interval_minutes'] = Variable<int>(repeatIntervalMinutes);
    }
    if (!nullToAbsent || maxRingSeconds != null) {
      map['max_ring_seconds'] = Variable<int>(maxRingSeconds);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  AlarmRuleRecordsCompanion toCompanion(bool nullToAbsent) {
    return AlarmRuleRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      ownerType: Value(ownerType),
      ownerId: Value(ownerId),
      enabled: Value(enabled),
      behavior: Value(behavior),
      soundName: soundName == null && nullToAbsent
          ? const Value.absent()
          : Value(soundName),
      snoozeMinutes: snoozeMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(snoozeMinutes),
      repeatIntervalMinutes: repeatIntervalMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatIntervalMinutes),
      maxRingSeconds: maxRingSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(maxRingSeconds),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory AlarmRuleRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmRuleRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      behavior: serializer.fromJson<String>(json['behavior']),
      soundName: serializer.fromJson<String?>(json['soundName']),
      snoozeMinutes: serializer.fromJson<int?>(json['snoozeMinutes']),
      repeatIntervalMinutes: serializer.fromJson<int?>(
        json['repeatIntervalMinutes'],
      ),
      maxRingSeconds: serializer.fromJson<int?>(json['maxRingSeconds']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'ownerType': serializer.toJson<String>(ownerType),
      'ownerId': serializer.toJson<String>(ownerId),
      'enabled': serializer.toJson<bool>(enabled),
      'behavior': serializer.toJson<String>(behavior),
      'soundName': serializer.toJson<String?>(soundName),
      'snoozeMinutes': serializer.toJson<int?>(snoozeMinutes),
      'repeatIntervalMinutes': serializer.toJson<int?>(repeatIntervalMinutes),
      'maxRingSeconds': serializer.toJson<int?>(maxRingSeconds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  AlarmRuleRecord copyWith({
    String? id,
    String? userId,
    String? ownerType,
    String? ownerId,
    bool? enabled,
    String? behavior,
    Value<String?> soundName = const Value.absent(),
    Value<int?> snoozeMinutes = const Value.absent(),
    Value<int?> repeatIntervalMinutes = const Value.absent(),
    Value<int?> maxRingSeconds = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => AlarmRuleRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    ownerType: ownerType ?? this.ownerType,
    ownerId: ownerId ?? this.ownerId,
    enabled: enabled ?? this.enabled,
    behavior: behavior ?? this.behavior,
    soundName: soundName.present ? soundName.value : this.soundName,
    snoozeMinutes: snoozeMinutes.present
        ? snoozeMinutes.value
        : this.snoozeMinutes,
    repeatIntervalMinutes: repeatIntervalMinutes.present
        ? repeatIntervalMinutes.value
        : this.repeatIntervalMinutes,
    maxRingSeconds: maxRingSeconds.present
        ? maxRingSeconds.value
        : this.maxRingSeconds,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  AlarmRuleRecord copyWithCompanion(AlarmRuleRecordsCompanion data) {
    return AlarmRuleRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      behavior: data.behavior.present ? data.behavior.value : this.behavior,
      soundName: data.soundName.present ? data.soundName.value : this.soundName,
      snoozeMinutes: data.snoozeMinutes.present
          ? data.snoozeMinutes.value
          : this.snoozeMinutes,
      repeatIntervalMinutes: data.repeatIntervalMinutes.present
          ? data.repeatIntervalMinutes.value
          : this.repeatIntervalMinutes,
      maxRingSeconds: data.maxRingSeconds.present
          ? data.maxRingSeconds.value
          : this.maxRingSeconds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmRuleRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('enabled: $enabled, ')
          ..write('behavior: $behavior, ')
          ..write('soundName: $soundName, ')
          ..write('snoozeMinutes: $snoozeMinutes, ')
          ..write('repeatIntervalMinutes: $repeatIntervalMinutes, ')
          ..write('maxRingSeconds: $maxRingSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    ownerType,
    ownerId,
    enabled,
    behavior,
    soundName,
    snoozeMinutes,
    repeatIntervalMinutes,
    maxRingSeconds,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmRuleRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.ownerType == this.ownerType &&
          other.ownerId == this.ownerId &&
          other.enabled == this.enabled &&
          other.behavior == this.behavior &&
          other.soundName == this.soundName &&
          other.snoozeMinutes == this.snoozeMinutes &&
          other.repeatIntervalMinutes == this.repeatIntervalMinutes &&
          other.maxRingSeconds == this.maxRingSeconds &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class AlarmRuleRecordsCompanion extends UpdateCompanion<AlarmRuleRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> ownerType;
  final Value<String> ownerId;
  final Value<bool> enabled;
  final Value<String> behavior;
  final Value<String?> soundName;
  final Value<int?> snoozeMinutes;
  final Value<int?> repeatIntervalMinutes;
  final Value<int?> maxRingSeconds;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const AlarmRuleRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.behavior = const Value.absent(),
    this.soundName = const Value.absent(),
    this.snoozeMinutes = const Value.absent(),
    this.repeatIntervalMinutes = const Value.absent(),
    this.maxRingSeconds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlarmRuleRecordsCompanion.insert({
    required String id,
    required String userId,
    required String ownerType,
    required String ownerId,
    this.enabled = const Value.absent(),
    this.behavior = const Value.absent(),
    this.soundName = const Value.absent(),
    this.snoozeMinutes = const Value.absent(),
    this.repeatIntervalMinutes = const Value.absent(),
    this.maxRingSeconds = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       ownerType = Value(ownerType),
       ownerId = Value(ownerId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AlarmRuleRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? ownerType,
    Expression<String>? ownerId,
    Expression<bool>? enabled,
    Expression<String>? behavior,
    Expression<String>? soundName,
    Expression<int>? snoozeMinutes,
    Expression<int>? repeatIntervalMinutes,
    Expression<int>? maxRingSeconds,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (ownerType != null) 'owner_type': ownerType,
      if (ownerId != null) 'owner_id': ownerId,
      if (enabled != null) 'enabled': enabled,
      if (behavior != null) 'behavior': behavior,
      if (soundName != null) 'sound_name': soundName,
      if (snoozeMinutes != null) 'snooze_minutes': snoozeMinutes,
      if (repeatIntervalMinutes != null)
        'repeat_interval_minutes': repeatIntervalMinutes,
      if (maxRingSeconds != null) 'max_ring_seconds': maxRingSeconds,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlarmRuleRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? ownerType,
    Value<String>? ownerId,
    Value<bool>? enabled,
    Value<String>? behavior,
    Value<String?>? soundName,
    Value<int?>? snoozeMinutes,
    Value<int?>? repeatIntervalMinutes,
    Value<int?>? maxRingSeconds,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return AlarmRuleRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      ownerType: ownerType ?? this.ownerType,
      ownerId: ownerId ?? this.ownerId,
      enabled: enabled ?? this.enabled,
      behavior: behavior ?? this.behavior,
      soundName: soundName ?? this.soundName,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      repeatIntervalMinutes:
          repeatIntervalMinutes ?? this.repeatIntervalMinutes,
      maxRingSeconds: maxRingSeconds ?? this.maxRingSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (behavior.present) {
      map['behavior'] = Variable<String>(behavior.value);
    }
    if (soundName.present) {
      map['sound_name'] = Variable<String>(soundName.value);
    }
    if (snoozeMinutes.present) {
      map['snooze_minutes'] = Variable<int>(snoozeMinutes.value);
    }
    if (repeatIntervalMinutes.present) {
      map['repeat_interval_minutes'] = Variable<int>(
        repeatIntervalMinutes.value,
      );
    }
    if (maxRingSeconds.present) {
      map['max_ring_seconds'] = Variable<int>(maxRingSeconds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmRuleRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('ownerType: $ownerType, ')
          ..write('ownerId: $ownerId, ')
          ..write('enabled: $enabled, ')
          ..write('behavior: $behavior, ')
          ..write('soundName: $soundName, ')
          ..write('snoozeMinutes: $snoozeMinutes, ')
          ..write('repeatIntervalMinutes: $repeatIntervalMinutes, ')
          ..write('maxRingSeconds: $maxRingSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AdHocTimerRecordsTable extends AdHocTimerRecords
    with TableInfo<$AdHocTimerRecordsTable, AdHocTimerRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AdHocTimerRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
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
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timerStatusMeta = const VerificationMeta(
    'timerStatus',
  );
  @override
  late final GeneratedColumn<String> timerStatus = GeneratedColumn<String>(
    'timer_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('idle'),
  );
  static const VerificationMeta _accumulatedDurationSecondsMeta =
      const VerificationMeta('accumulatedDurationSeconds');
  @override
  late final GeneratedColumn<int> accumulatedDurationSeconds =
      GeneratedColumn<int>(
        'accumulated_duration_seconds',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _currentStartedAtMeta = const VerificationMeta(
    'currentStartedAt',
  );
  @override
  late final GeneratedColumn<DateTime> currentStartedAt =
      GeneratedColumn<DateTime>(
        'current_started_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    tagId,
    colorValue,
    notes,
    startedAt,
    timerStatus,
    accumulatedDurationSeconds,
    currentStartedAt,
    endedAt,
    completedAt,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ad_hoc_timer_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AdHocTimerRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('timer_status')) {
      context.handle(
        _timerStatusMeta,
        timerStatus.isAcceptableOrUnknown(
          data['timer_status']!,
          _timerStatusMeta,
        ),
      );
    }
    if (data.containsKey('accumulated_duration_seconds')) {
      context.handle(
        _accumulatedDurationSecondsMeta,
        accumulatedDurationSeconds.isAcceptableOrUnknown(
          data['accumulated_duration_seconds']!,
          _accumulatedDurationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('current_started_at')) {
      context.handle(
        _currentStartedAtMeta,
        currentStartedAt.isAcceptableOrUnknown(
          data['current_started_at']!,
          _currentStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AdHocTimerRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AdHocTimerRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      ),
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      timerStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timer_status'],
      )!,
      accumulatedDurationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accumulated_duration_seconds'],
      )!,
      currentStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}current_started_at'],
      ),
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $AdHocTimerRecordsTable createAlias(String alias) {
    return $AdHocTimerRecordsTable(attachedDatabase, alias);
  }
}

class AdHocTimerRecord extends DataClass
    implements Insertable<AdHocTimerRecord> {
  final String id;
  final String userId;
  final String title;
  final String? tagId;
  final int colorValue;
  final String? notes;
  final DateTime startedAt;
  final String timerStatus;
  final int accumulatedDurationSeconds;
  final DateTime? currentStartedAt;
  final DateTime? endedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const AdHocTimerRecord({
    required this.id,
    required this.userId,
    required this.title,
    this.tagId,
    required this.colorValue,
    this.notes,
    required this.startedAt,
    required this.timerStatus,
    required this.accumulatedDurationSeconds,
    this.currentStartedAt,
    this.endedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || tagId != null) {
      map['tag_id'] = Variable<String>(tagId);
    }
    map['color_value'] = Variable<int>(colorValue);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    map['timer_status'] = Variable<String>(timerStatus);
    map['accumulated_duration_seconds'] = Variable<int>(
      accumulatedDurationSeconds,
    );
    if (!nullToAbsent || currentStartedAt != null) {
      map['current_started_at'] = Variable<DateTime>(currentStartedAt);
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  AdHocTimerRecordsCompanion toCompanion(bool nullToAbsent) {
    return AdHocTimerRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      title: Value(title),
      tagId: tagId == null && nullToAbsent
          ? const Value.absent()
          : Value(tagId),
      colorValue: Value(colorValue),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      startedAt: Value(startedAt),
      timerStatus: Value(timerStatus),
      accumulatedDurationSeconds: Value(accumulatedDurationSeconds),
      currentStartedAt: currentStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(currentStartedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory AdHocTimerRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AdHocTimerRecord(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      tagId: serializer.fromJson<String?>(json['tagId']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      notes: serializer.fromJson<String?>(json['notes']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      timerStatus: serializer.fromJson<String>(json['timerStatus']),
      accumulatedDurationSeconds: serializer.fromJson<int>(
        json['accumulatedDurationSeconds'],
      ),
      currentStartedAt: serializer.fromJson<DateTime?>(
        json['currentStartedAt'],
      ),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'tagId': serializer.toJson<String?>(tagId),
      'colorValue': serializer.toJson<int>(colorValue),
      'notes': serializer.toJson<String?>(notes),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'timerStatus': serializer.toJson<String>(timerStatus),
      'accumulatedDurationSeconds': serializer.toJson<int>(
        accumulatedDurationSeconds,
      ),
      'currentStartedAt': serializer.toJson<DateTime?>(currentStartedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  AdHocTimerRecord copyWith({
    String? id,
    String? userId,
    String? title,
    Value<String?> tagId = const Value.absent(),
    int? colorValue,
    Value<String?> notes = const Value.absent(),
    DateTime? startedAt,
    String? timerStatus,
    int? accumulatedDurationSeconds,
    Value<DateTime?> currentStartedAt = const Value.absent(),
    Value<DateTime?> endedAt = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => AdHocTimerRecord(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    tagId: tagId.present ? tagId.value : this.tagId,
    colorValue: colorValue ?? this.colorValue,
    notes: notes.present ? notes.value : this.notes,
    startedAt: startedAt ?? this.startedAt,
    timerStatus: timerStatus ?? this.timerStatus,
    accumulatedDurationSeconds:
        accumulatedDurationSeconds ?? this.accumulatedDurationSeconds,
    currentStartedAt: currentStartedAt.present
        ? currentStartedAt.value
        : this.currentStartedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  AdHocTimerRecord copyWithCompanion(AdHocTimerRecordsCompanion data) {
    return AdHocTimerRecord(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      notes: data.notes.present ? data.notes.value : this.notes,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      timerStatus: data.timerStatus.present
          ? data.timerStatus.value
          : this.timerStatus,
      accumulatedDurationSeconds: data.accumulatedDurationSeconds.present
          ? data.accumulatedDurationSeconds.value
          : this.accumulatedDurationSeconds,
      currentStartedAt: data.currentStartedAt.present
          ? data.currentStartedAt.value
          : this.currentStartedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AdHocTimerRecord(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('tagId: $tagId, ')
          ..write('colorValue: $colorValue, ')
          ..write('notes: $notes, ')
          ..write('startedAt: $startedAt, ')
          ..write('timerStatus: $timerStatus, ')
          ..write('accumulatedDurationSeconds: $accumulatedDurationSeconds, ')
          ..write('currentStartedAt: $currentStartedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    tagId,
    colorValue,
    notes,
    startedAt,
    timerStatus,
    accumulatedDurationSeconds,
    currentStartedAt,
    endedAt,
    completedAt,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AdHocTimerRecord &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.tagId == this.tagId &&
          other.colorValue == this.colorValue &&
          other.notes == this.notes &&
          other.startedAt == this.startedAt &&
          other.timerStatus == this.timerStatus &&
          other.accumulatedDurationSeconds == this.accumulatedDurationSeconds &&
          other.currentStartedAt == this.currentStartedAt &&
          other.endedAt == this.endedAt &&
          other.completedAt == this.completedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class AdHocTimerRecordsCompanion extends UpdateCompanion<AdHocTimerRecord> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> title;
  final Value<String?> tagId;
  final Value<int> colorValue;
  final Value<String?> notes;
  final Value<DateTime> startedAt;
  final Value<String> timerStatus;
  final Value<int> accumulatedDurationSeconds;
  final Value<DateTime?> currentStartedAt;
  final Value<DateTime?> endedAt;
  final Value<DateTime?> completedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const AdHocTimerRecordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.title = const Value.absent(),
    this.tagId = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.notes = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.timerStatus = const Value.absent(),
    this.accumulatedDurationSeconds = const Value.absent(),
    this.currentStartedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AdHocTimerRecordsCompanion.insert({
    required String id,
    required String userId,
    required String title,
    this.tagId = const Value.absent(),
    required int colorValue,
    this.notes = const Value.absent(),
    required DateTime startedAt,
    this.timerStatus = const Value.absent(),
    this.accumulatedDurationSeconds = const Value.absent(),
    this.currentStartedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       title = Value(title),
       colorValue = Value(colorValue),
       startedAt = Value(startedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AdHocTimerRecord> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? title,
    Expression<String>? tagId,
    Expression<int>? colorValue,
    Expression<String>? notes,
    Expression<DateTime>? startedAt,
    Expression<String>? timerStatus,
    Expression<int>? accumulatedDurationSeconds,
    Expression<DateTime>? currentStartedAt,
    Expression<DateTime>? endedAt,
    Expression<DateTime>? completedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (tagId != null) 'tag_id': tagId,
      if (colorValue != null) 'color_value': colorValue,
      if (notes != null) 'notes': notes,
      if (startedAt != null) 'started_at': startedAt,
      if (timerStatus != null) 'timer_status': timerStatus,
      if (accumulatedDurationSeconds != null)
        'accumulated_duration_seconds': accumulatedDurationSeconds,
      if (currentStartedAt != null) 'current_started_at': currentStartedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AdHocTimerRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? title,
    Value<String?>? tagId,
    Value<int>? colorValue,
    Value<String?>? notes,
    Value<DateTime>? startedAt,
    Value<String>? timerStatus,
    Value<int>? accumulatedDurationSeconds,
    Value<DateTime?>? currentStartedAt,
    Value<DateTime?>? endedAt,
    Value<DateTime?>? completedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return AdHocTimerRecordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      tagId: tagId ?? this.tagId,
      colorValue: colorValue ?? this.colorValue,
      notes: notes ?? this.notes,
      startedAt: startedAt ?? this.startedAt,
      timerStatus: timerStatus ?? this.timerStatus,
      accumulatedDurationSeconds:
          accumulatedDurationSeconds ?? this.accumulatedDurationSeconds,
      currentStartedAt: currentStartedAt ?? this.currentStartedAt,
      endedAt: endedAt ?? this.endedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (timerStatus.present) {
      map['timer_status'] = Variable<String>(timerStatus.value);
    }
    if (accumulatedDurationSeconds.present) {
      map['accumulated_duration_seconds'] = Variable<int>(
        accumulatedDurationSeconds.value,
      );
    }
    if (currentStartedAt.present) {
      map['current_started_at'] = Variable<DateTime>(currentStartedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AdHocTimerRecordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('tagId: $tagId, ')
          ..write('colorValue: $colorValue, ')
          ..write('notes: $notes, ')
          ..write('startedAt: $startedAt, ')
          ..write('timerStatus: $timerStatus, ')
          ..write('accumulatedDurationSeconds: $accumulatedDurationSeconds, ')
          ..write('currentStartedAt: $currentStartedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AdHocTimerIntervalRecordsTable extends AdHocTimerIntervalRecords
    with TableInfo<$AdHocTimerIntervalRecordsTable, AdHocTimerIntervalRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AdHocTimerIntervalRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timerIdMeta = const VerificationMeta(
    'timerId',
  );
  @override
  late final GeneratedColumn<String> timerId = GeneratedColumn<String>(
    'timer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    timerId,
    userId,
    startedAt,
    endedAt,
    durationSeconds,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ad_hoc_timer_interval_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<AdHocTimerIntervalRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('timer_id')) {
      context.handle(
        _timerIdMeta,
        timerId.isAcceptableOrUnknown(data['timer_id']!, _timerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_timerIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AdHocTimerIntervalRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AdHocTimerIntervalRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      timerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timer_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AdHocTimerIntervalRecordsTable createAlias(String alias) {
    return $AdHocTimerIntervalRecordsTable(attachedDatabase, alias);
  }
}

class AdHocTimerIntervalRecord extends DataClass
    implements Insertable<AdHocTimerIntervalRecord> {
  final String id;
  final String timerId;
  final String userId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  const AdHocTimerIntervalRecord({
    required this.id,
    required this.timerId,
    required this.userId,
    required this.startedAt,
    this.endedAt,
    required this.durationSeconds,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['timer_id'] = Variable<String>(timerId);
    map['user_id'] = Variable<String>(userId);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AdHocTimerIntervalRecordsCompanion toCompanion(bool nullToAbsent) {
    return AdHocTimerIntervalRecordsCompanion(
      id: Value(id),
      timerId: Value(timerId),
      userId: Value(userId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      durationSeconds: Value(durationSeconds),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory AdHocTimerIntervalRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AdHocTimerIntervalRecord(
      id: serializer.fromJson<String>(json['id']),
      timerId: serializer.fromJson<String>(json['timerId']),
      userId: serializer.fromJson<String>(json['userId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'timerId': serializer.toJson<String>(timerId),
      'userId': serializer.toJson<String>(userId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AdHocTimerIntervalRecord copyWith({
    String? id,
    String? timerId,
    String? userId,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    int? durationSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => AdHocTimerIntervalRecord(
    id: id ?? this.id,
    timerId: timerId ?? this.timerId,
    userId: userId ?? this.userId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AdHocTimerIntervalRecord copyWithCompanion(
    AdHocTimerIntervalRecordsCompanion data,
  ) {
    return AdHocTimerIntervalRecord(
      id: data.id.present ? data.id.value : this.id,
      timerId: data.timerId.present ? data.timerId.value : this.timerId,
      userId: data.userId.present ? data.userId.value : this.userId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AdHocTimerIntervalRecord(')
          ..write('id: $id, ')
          ..write('timerId: $timerId, ')
          ..write('userId: $userId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    timerId,
    userId,
    startedAt,
    endedAt,
    durationSeconds,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AdHocTimerIntervalRecord &&
          other.id == this.id &&
          other.timerId == this.timerId &&
          other.userId == this.userId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationSeconds == this.durationSeconds &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AdHocTimerIntervalRecordsCompanion
    extends UpdateCompanion<AdHocTimerIntervalRecord> {
  final Value<String> id;
  final Value<String> timerId;
  final Value<String> userId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> durationSeconds;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AdHocTimerIntervalRecordsCompanion({
    this.id = const Value.absent(),
    this.timerId = const Value.absent(),
    this.userId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AdHocTimerIntervalRecordsCompanion.insert({
    required String id,
    required String timerId,
    required String userId,
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       timerId = Value(timerId),
       userId = Value(userId),
       startedAt = Value(startedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<AdHocTimerIntervalRecord> custom({
    Expression<String>? id,
    Expression<String>? timerId,
    Expression<String>? userId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? durationSeconds,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timerId != null) 'timer_id': timerId,
      if (userId != null) 'user_id': userId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AdHocTimerIntervalRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? timerId,
    Value<String>? userId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? durationSeconds,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return AdHocTimerIntervalRecordsCompanion(
      id: id ?? this.id,
      timerId: timerId ?? this.timerId,
      userId: userId ?? this.userId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (timerId.present) {
      map['timer_id'] = Variable<String>(timerId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AdHocTimerIntervalRecordsCompanion(')
          ..write('id: $id, ')
          ..write('timerId: $timerId, ')
          ..write('userId: $userId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalTasksTable localTasks = $LocalTasksTable(this);
  late final $LongTermTaskRecordsTable longTermTaskRecords =
      $LongTermTaskRecordsTable(this);
  late final $TaskScheduleRecordsTable taskScheduleRecords =
      $TaskScheduleRecordsTable(this);
  late final $OneTimeReminderRecordsTable oneTimeReminderRecords =
      $OneTimeReminderRecordsTable(this);
  late final $TaskCompletionRecordsTable taskCompletionRecords =
      $TaskCompletionRecordsTable(this);
  late final $TimerSessionRecordsTable timerSessionRecords =
      $TimerSessionRecordsTable(this);
  late final $TaskRevisionRecordsTable taskRevisionRecords =
      $TaskRevisionRecordsTable(this);
  late final $SyncOperationsTable syncOperations = $SyncOperationsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $TagRecordsTable tagRecords = $TagRecordsTable(this);
  late final $TagRevisionRecordsTable tagRevisionRecords =
      $TagRevisionRecordsTable(this);
  late final $PlanRecordsTable planRecords = $PlanRecordsTable(this);
  late final $PlanTaskRecordsTable planTaskRecords = $PlanTaskRecordsTable(
    this,
  );
  late final $ReviewRecordsTable reviewRecords = $ReviewRecordsTable(this);
  late final $CourseRecordsTable courseRecords = $CourseRecordsTable(this);
  late final $CourseScheduleRuleRecordsTable courseScheduleRuleRecords =
      $CourseScheduleRuleRecordsTable(this);
  late final $ScheduleTemplateRecordsTable scheduleTemplateRecords =
      $ScheduleTemplateRecordsTable(this);
  late final $ScheduleTemplateSegmentRecordsTable
  scheduleTemplateSegmentRecords = $ScheduleTemplateSegmentRecordsTable(this);
  late final $SemesterRecordsTable semesterRecords = $SemesterRecordsTable(
    this,
  );
  late final $DailyItemOverrideRecordsTable dailyItemOverrideRecords =
      $DailyItemOverrideRecordsTable(this);
  late final $ReminderRuleRecordsTable reminderRuleRecords =
      $ReminderRuleRecordsTable(this);
  late final $AlarmRuleRecordsTable alarmRuleRecords = $AlarmRuleRecordsTable(
    this,
  );
  late final $AdHocTimerRecordsTable adHocTimerRecords =
      $AdHocTimerRecordsTable(this);
  late final $AdHocTimerIntervalRecordsTable adHocTimerIntervalRecords =
      $AdHocTimerIntervalRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localTasks,
    longTermTaskRecords,
    taskScheduleRecords,
    oneTimeReminderRecords,
    taskCompletionRecords,
    timerSessionRecords,
    taskRevisionRecords,
    syncOperations,
    appSettings,
    tagRecords,
    tagRevisionRecords,
    planRecords,
    planTaskRecords,
    reviewRecords,
    courseRecords,
    courseScheduleRuleRecords,
    scheduleTemplateRecords,
    scheduleTemplateSegmentRecords,
    semesterRecords,
    dailyItemOverrideRecords,
    reminderRuleRecords,
    alarmRuleRecords,
    adHocTimerRecords,
    adHocTimerIntervalRecords,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('long_term_task_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_schedule_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('one_time_reminder_records', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_completion_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('timer_session_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('task_revision_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'plan_records',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('plan_task_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_tasks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('plan_task_records', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'course_records',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('course_schedule_rule_records', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'schedule_template_records',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate(
          'schedule_template_segment_records',
          kind: UpdateKind.delete,
        ),
      ],
    ),
  ]);
}

typedef $$LocalTasksTableCreateCompanionBuilder =
    LocalTasksCompanion Function({
      required String id,
      Value<String?> userId,
      required String name,
      required String taskType,
      required int colorValue,
      Value<String> iconName,
      Value<String?> tagId,
      Value<String?> notes,
      Value<String> status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> syncVersion,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$LocalTasksTableUpdateCompanionBuilder =
    LocalTasksCompanion Function({
      Value<String> id,
      Value<String?> userId,
      Value<String> name,
      Value<String> taskType,
      Value<int> colorValue,
      Value<String> iconName,
      Value<String?> tagId,
      Value<String?> notes,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> syncVersion,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$LocalTasksTableReferences
    extends BaseReferences<_$AppDatabase, $LocalTasksTable, LocalTask> {
  $$LocalTasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $LongTermTaskRecordsTable,
    List<LongTermTaskRecord>
  >
  _longTermTaskRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.longTermTaskRecords,
        aliasName: 'local_tasks__id__long_term_task_records__task_id',
      );

  $$LongTermTaskRecordsTableProcessedTableManager get longTermTaskRecordsRefs {
    final manager = $$LongTermTaskRecordsTableTableManager(
      $_db,
      $_db.longTermTaskRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _longTermTaskRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TaskScheduleRecordsTable,
    List<TaskScheduleRecord>
  >
  _taskScheduleRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.taskScheduleRecords,
        aliasName: 'local_tasks__id__task_schedule_records__task_id',
      );

  $$TaskScheduleRecordsTableProcessedTableManager get taskScheduleRecordsRefs {
    final manager = $$TaskScheduleRecordsTableTableManager(
      $_db,
      $_db.taskScheduleRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _taskScheduleRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $OneTimeReminderRecordsTable,
    List<OneTimeReminderRecord>
  >
  _oneTimeReminderRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.oneTimeReminderRecords,
        aliasName: 'local_tasks__id__one_time_reminder_records__task_id',
      );

  $$OneTimeReminderRecordsTableProcessedTableManager
  get oneTimeReminderRecordsRefs {
    final manager = $$OneTimeReminderRecordsTableTableManager(
      $_db,
      $_db.oneTimeReminderRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _oneTimeReminderRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TaskCompletionRecordsTable,
    List<TaskCompletionRecord>
  >
  _taskCompletionRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.taskCompletionRecords,
        aliasName: 'local_tasks__id__task_completion_records__task_id',
      );

  $$TaskCompletionRecordsTableProcessedTableManager
  get taskCompletionRecordsRefs {
    final manager = $$TaskCompletionRecordsTableTableManager(
      $_db,
      $_db.taskCompletionRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _taskCompletionRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TimerSessionRecordsTable,
    List<TimerSessionRecord>
  >
  _timerSessionRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.timerSessionRecords,
        aliasName: 'local_tasks__id__timer_session_records__task_id',
      );

  $$TimerSessionRecordsTableProcessedTableManager get timerSessionRecordsRefs {
    final manager = $$TimerSessionRecordsTableTableManager(
      $_db,
      $_db.timerSessionRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _timerSessionRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TaskRevisionRecordsTable,
    List<TaskRevisionRecord>
  >
  _taskRevisionRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.taskRevisionRecords,
        aliasName: 'local_tasks__id__task_revision_records__task_id',
      );

  $$TaskRevisionRecordsTableProcessedTableManager get taskRevisionRecordsRefs {
    final manager = $$TaskRevisionRecordsTableTableManager(
      $_db,
      $_db.taskRevisionRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _taskRevisionRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlanTaskRecordsTable, List<PlanTaskRecord>>
  _planTaskRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.planTaskRecords,
    aliasName: 'local_tasks__id__plan_task_records__task_id',
  );

  $$PlanTaskRecordsTableProcessedTableManager get planTaskRecordsRefs {
    final manager = $$PlanTaskRecordsTableTableManager(
      $_db,
      $_db.planTaskRecords,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _planTaskRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalTasksTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconName => $composableBuilder(
    column: $table.iconName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> longTermTaskRecordsRefs(
    Expression<bool> Function($$LongTermTaskRecordsTableFilterComposer f) f,
  ) {
    final $$LongTermTaskRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.longTermTaskRecords,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LongTermTaskRecordsTableFilterComposer(
            $db: $db,
            $table: $db.longTermTaskRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskScheduleRecordsRefs(
    Expression<bool> Function($$TaskScheduleRecordsTableFilterComposer f) f,
  ) {
    final $$TaskScheduleRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskScheduleRecords,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskScheduleRecordsTableFilterComposer(
            $db: $db,
            $table: $db.taskScheduleRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> oneTimeReminderRecordsRefs(
    Expression<bool> Function($$OneTimeReminderRecordsTableFilterComposer f) f,
  ) {
    final $$OneTimeReminderRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.oneTimeReminderRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OneTimeReminderRecordsTableFilterComposer(
                $db: $db,
                $table: $db.oneTimeReminderRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> taskCompletionRecordsRefs(
    Expression<bool> Function($$TaskCompletionRecordsTableFilterComposer f) f,
  ) {
    final $$TaskCompletionRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.taskCompletionRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TaskCompletionRecordsTableFilterComposer(
                $db: $db,
                $table: $db.taskCompletionRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> timerSessionRecordsRefs(
    Expression<bool> Function($$TimerSessionRecordsTableFilterComposer f) f,
  ) {
    final $$TimerSessionRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timerSessionRecords,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimerSessionRecordsTableFilterComposer(
            $db: $db,
            $table: $db.timerSessionRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> taskRevisionRecordsRefs(
    Expression<bool> Function($$TaskRevisionRecordsTableFilterComposer f) f,
  ) {
    final $$TaskRevisionRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.taskRevisionRecords,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TaskRevisionRecordsTableFilterComposer(
            $db: $db,
            $table: $db.taskRevisionRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> planTaskRecordsRefs(
    Expression<bool> Function($$PlanTaskRecordsTableFilterComposer f) f,
  ) {
    final $$PlanTaskRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planTaskRecords,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanTaskRecordsTableFilterComposer(
            $db: $db,
            $table: $db.planTaskRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconName => $composableBuilder(
    column: $table.iconName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTasksTable> {
  $$LocalTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get iconName =>
      $composableBuilder(column: $table.iconName, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> longTermTaskRecordsRefs<T extends Object>(
    Expression<T> Function($$LongTermTaskRecordsTableAnnotationComposer a) f,
  ) {
    final $$LongTermTaskRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.longTermTaskRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LongTermTaskRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.longTermTaskRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> taskScheduleRecordsRefs<T extends Object>(
    Expression<T> Function($$TaskScheduleRecordsTableAnnotationComposer a) f,
  ) {
    final $$TaskScheduleRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.taskScheduleRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TaskScheduleRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.taskScheduleRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> oneTimeReminderRecordsRefs<T extends Object>(
    Expression<T> Function($$OneTimeReminderRecordsTableAnnotationComposer a) f,
  ) {
    final $$OneTimeReminderRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.oneTimeReminderRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OneTimeReminderRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.oneTimeReminderRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> taskCompletionRecordsRefs<T extends Object>(
    Expression<T> Function($$TaskCompletionRecordsTableAnnotationComposer a) f,
  ) {
    final $$TaskCompletionRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.taskCompletionRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TaskCompletionRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.taskCompletionRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> timerSessionRecordsRefs<T extends Object>(
    Expression<T> Function($$TimerSessionRecordsTableAnnotationComposer a) f,
  ) {
    final $$TimerSessionRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.timerSessionRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TimerSessionRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.timerSessionRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> taskRevisionRecordsRefs<T extends Object>(
    Expression<T> Function($$TaskRevisionRecordsTableAnnotationComposer a) f,
  ) {
    final $$TaskRevisionRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.taskRevisionRecords,
          getReferencedColumn: (t) => t.taskId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TaskRevisionRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.taskRevisionRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> planTaskRecordsRefs<T extends Object>(
    Expression<T> Function($$PlanTaskRecordsTableAnnotationComposer a) f,
  ) {
    final $$PlanTaskRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planTaskRecords,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanTaskRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.planTaskRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalTasksTable,
          LocalTask,
          $$LocalTasksTableFilterComposer,
          $$LocalTasksTableOrderingComposer,
          $$LocalTasksTableAnnotationComposer,
          $$LocalTasksTableCreateCompanionBuilder,
          $$LocalTasksTableUpdateCompanionBuilder,
          (LocalTask, $$LocalTasksTableReferences),
          LocalTask,
          PrefetchHooks Function({
            bool longTermTaskRecordsRefs,
            bool taskScheduleRecordsRefs,
            bool oneTimeReminderRecordsRefs,
            bool taskCompletionRecordsRefs,
            bool timerSessionRecordsRefs,
            bool taskRevisionRecordsRefs,
            bool planTaskRecordsRefs,
          })
        > {
  $$LocalTasksTableTableManager(_$AppDatabase db, $LocalTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> taskType = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String> iconName = const Value.absent(),
                Value<String?> tagId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> syncVersion = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion(
                id: id,
                userId: userId,
                name: name,
                taskType: taskType,
                colorValue: colorValue,
                iconName: iconName,
                tagId: tagId,
                notes: notes,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                syncVersion: syncVersion,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> userId = const Value.absent(),
                required String name,
                required String taskType,
                required int colorValue,
                Value<String> iconName = const Value.absent(),
                Value<String?> tagId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> syncVersion = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTasksCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                taskType: taskType,
                colorValue: colorValue,
                iconName: iconName,
                tagId: tagId,
                notes: notes,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                syncVersion: syncVersion,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalTasksTable, LocalTask>(table),
                  $$LocalTasksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                longTermTaskRecordsRefs = false,
                taskScheduleRecordsRefs = false,
                oneTimeReminderRecordsRefs = false,
                taskCompletionRecordsRefs = false,
                timerSessionRecordsRefs = false,
                taskRevisionRecordsRefs = false,
                planTaskRecordsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (longTermTaskRecordsRefs) db.longTermTaskRecords,
                    if (taskScheduleRecordsRefs) db.taskScheduleRecords,
                    if (oneTimeReminderRecordsRefs) db.oneTimeReminderRecords,
                    if (taskCompletionRecordsRefs) db.taskCompletionRecords,
                    if (timerSessionRecordsRefs) db.timerSessionRecords,
                    if (taskRevisionRecordsRefs) db.taskRevisionRecords,
                    if (planTaskRecordsRefs) db.planTaskRecords,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (longTermTaskRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          LongTermTaskRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._longTermTaskRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).longTermTaskRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskScheduleRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          TaskScheduleRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._taskScheduleRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskScheduleRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (oneTimeReminderRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          OneTimeReminderRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._oneTimeReminderRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).oneTimeReminderRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskCompletionRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          TaskCompletionRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._taskCompletionRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskCompletionRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (timerSessionRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          TimerSessionRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._timerSessionRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).timerSessionRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (taskRevisionRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          TaskRevisionRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._taskRevisionRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).taskRevisionRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (planTaskRecordsRefs)
                        await $_getPrefetchedData<
                          LocalTask,
                          $LocalTasksTable,
                          PlanTaskRecord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalTasksTableReferences
                              ._planTaskRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalTasksTableReferences(
                                db,
                                table,
                                p0,
                              ).planTaskRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.taskId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$LocalTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalTasksTable,
      LocalTask,
      $$LocalTasksTableFilterComposer,
      $$LocalTasksTableOrderingComposer,
      $$LocalTasksTableAnnotationComposer,
      $$LocalTasksTableCreateCompanionBuilder,
      $$LocalTasksTableUpdateCompanionBuilder,
      (LocalTask, $$LocalTasksTableReferences),
      LocalTask,
      PrefetchHooks Function({
        bool longTermTaskRecordsRefs,
        bool taskScheduleRecordsRefs,
        bool oneTimeReminderRecordsRefs,
        bool taskCompletionRecordsRefs,
        bool timerSessionRecordsRefs,
        bool taskRevisionRecordsRefs,
        bool planTaskRecordsRefs,
      })
    >;
typedef $$LongTermTaskRecordsTableCreateCompanionBuilder =
    LongTermTaskRecordsCompanion Function({
      required String taskId,
      required String userId,
      required String checkMode,
      Value<int?> targetDurationSeconds,
      Value<int?> targetDays,
      Value<bool> holidayPause,
      Value<int?> scheduledMinuteOfDay,
      Value<int?> reminderMinuteOfDay,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$LongTermTaskRecordsTableUpdateCompanionBuilder =
    LongTermTaskRecordsCompanion Function({
      Value<String> taskId,
      Value<String> userId,
      Value<String> checkMode,
      Value<int?> targetDurationSeconds,
      Value<int?> targetDays,
      Value<bool> holidayPause,
      Value<int?> scheduledMinuteOfDay,
      Value<int?> reminderMinuteOfDay,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$LongTermTaskRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $LongTermTaskRecordsTable,
          LongTermTaskRecord
        > {
  $$LongTermTaskRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) => db.localTasks
      .createAlias('long_term_task_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LongTermTaskRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $LongTermTaskRecordsTable> {
  $$LongTermTaskRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkMode => $composableBuilder(
    column: $table.checkMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetDurationSeconds => $composableBuilder(
    column: $table.targetDurationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetDays => $composableBuilder(
    column: $table.targetDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get holidayPause => $composableBuilder(
    column: $table.holidayPause,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledMinuteOfDay => $composableBuilder(
    column: $table.scheduledMinuteOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderMinuteOfDay => $composableBuilder(
    column: $table.reminderMinuteOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LongTermTaskRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LongTermTaskRecordsTable> {
  $$LongTermTaskRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkMode => $composableBuilder(
    column: $table.checkMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetDurationSeconds => $composableBuilder(
    column: $table.targetDurationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetDays => $composableBuilder(
    column: $table.targetDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get holidayPause => $composableBuilder(
    column: $table.holidayPause,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledMinuteOfDay => $composableBuilder(
    column: $table.scheduledMinuteOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderMinuteOfDay => $composableBuilder(
    column: $table.reminderMinuteOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LongTermTaskRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LongTermTaskRecordsTable> {
  $$LongTermTaskRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get checkMode =>
      $composableBuilder(column: $table.checkMode, builder: (column) => column);

  GeneratedColumn<int> get targetDurationSeconds => $composableBuilder(
    column: $table.targetDurationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetDays => $composableBuilder(
    column: $table.targetDays,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get holidayPause => $composableBuilder(
    column: $table.holidayPause,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scheduledMinuteOfDay => $composableBuilder(
    column: $table.scheduledMinuteOfDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderMinuteOfDay => $composableBuilder(
    column: $table.reminderMinuteOfDay,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LongTermTaskRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LongTermTaskRecordsTable,
          LongTermTaskRecord,
          $$LongTermTaskRecordsTableFilterComposer,
          $$LongTermTaskRecordsTableOrderingComposer,
          $$LongTermTaskRecordsTableAnnotationComposer,
          $$LongTermTaskRecordsTableCreateCompanionBuilder,
          $$LongTermTaskRecordsTableUpdateCompanionBuilder,
          (LongTermTaskRecord, $$LongTermTaskRecordsTableReferences),
          LongTermTaskRecord,
          PrefetchHooks Function({bool taskId})
        > {
  $$LongTermTaskRecordsTableTableManager(
    _$AppDatabase db,
    $LongTermTaskRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LongTermTaskRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LongTermTaskRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LongTermTaskRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> checkMode = const Value.absent(),
                Value<int?> targetDurationSeconds = const Value.absent(),
                Value<int?> targetDays = const Value.absent(),
                Value<bool> holidayPause = const Value.absent(),
                Value<int?> scheduledMinuteOfDay = const Value.absent(),
                Value<int?> reminderMinuteOfDay = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LongTermTaskRecordsCompanion(
                taskId: taskId,
                userId: userId,
                checkMode: checkMode,
                targetDurationSeconds: targetDurationSeconds,
                targetDays: targetDays,
                holidayPause: holidayPause,
                scheduledMinuteOfDay: scheduledMinuteOfDay,
                reminderMinuteOfDay: reminderMinuteOfDay,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String userId,
                required String checkMode,
                Value<int?> targetDurationSeconds = const Value.absent(),
                Value<int?> targetDays = const Value.absent(),
                Value<bool> holidayPause = const Value.absent(),
                Value<int?> scheduledMinuteOfDay = const Value.absent(),
                Value<int?> reminderMinuteOfDay = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => LongTermTaskRecordsCompanion.insert(
                taskId: taskId,
                userId: userId,
                checkMode: checkMode,
                targetDurationSeconds: targetDurationSeconds,
                targetDays: targetDays,
                holidayPause: holidayPause,
                scheduledMinuteOfDay: scheduledMinuteOfDay,
                reminderMinuteOfDay: reminderMinuteOfDay,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LongTermTaskRecordsTable, LongTermTaskRecord>(
                    table,
                  ),
                  $$LongTermTaskRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$LongTermTaskRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$LongTermTaskRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LongTermTaskRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LongTermTaskRecordsTable,
      LongTermTaskRecord,
      $$LongTermTaskRecordsTableFilterComposer,
      $$LongTermTaskRecordsTableOrderingComposer,
      $$LongTermTaskRecordsTableAnnotationComposer,
      $$LongTermTaskRecordsTableCreateCompanionBuilder,
      $$LongTermTaskRecordsTableUpdateCompanionBuilder,
      (LongTermTaskRecord, $$LongTermTaskRecordsTableReferences),
      LongTermTaskRecord,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TaskScheduleRecordsTableCreateCompanionBuilder =
    TaskScheduleRecordsCompanion Function({
      required String id,
      required String taskId,
      required String userId,
      required String scheduleType,
      required int weekdaysMask,
      required String startsOn,
      Value<String?> endsOn,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TaskScheduleRecordsTableUpdateCompanionBuilder =
    TaskScheduleRecordsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> userId,
      Value<String> scheduleType,
      Value<int> weekdaysMask,
      Value<String> startsOn,
      Value<String?> endsOn,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TaskScheduleRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TaskScheduleRecordsTable,
          TaskScheduleRecord
        > {
  $$TaskScheduleRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) => db.localTasks
      .createAlias('task_schedule_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskScheduleRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskScheduleRecordsTable> {
  $$TaskScheduleRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleType => $composableBuilder(
    column: $table.scheduleType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startsOn => $composableBuilder(
    column: $table.startsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endsOn => $composableBuilder(
    column: $table.endsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskScheduleRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskScheduleRecordsTable> {
  $$TaskScheduleRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleType => $composableBuilder(
    column: $table.scheduleType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startsOn => $composableBuilder(
    column: $table.startsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endsOn => $composableBuilder(
    column: $table.endsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskScheduleRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskScheduleRecordsTable> {
  $$TaskScheduleRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get scheduleType => $composableBuilder(
    column: $table.scheduleType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weekdaysMask => $composableBuilder(
    column: $table.weekdaysMask,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startsOn =>
      $composableBuilder(column: $table.startsOn, builder: (column) => column);

  GeneratedColumn<String> get endsOn =>
      $composableBuilder(column: $table.endsOn, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskScheduleRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskScheduleRecordsTable,
          TaskScheduleRecord,
          $$TaskScheduleRecordsTableFilterComposer,
          $$TaskScheduleRecordsTableOrderingComposer,
          $$TaskScheduleRecordsTableAnnotationComposer,
          $$TaskScheduleRecordsTableCreateCompanionBuilder,
          $$TaskScheduleRecordsTableUpdateCompanionBuilder,
          (TaskScheduleRecord, $$TaskScheduleRecordsTableReferences),
          TaskScheduleRecord,
          PrefetchHooks Function({bool taskId})
        > {
  $$TaskScheduleRecordsTableTableManager(
    _$AppDatabase db,
    $TaskScheduleRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskScheduleRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskScheduleRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TaskScheduleRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> scheduleType = const Value.absent(),
                Value<int> weekdaysMask = const Value.absent(),
                Value<String> startsOn = const Value.absent(),
                Value<String?> endsOn = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskScheduleRecordsCompanion(
                id: id,
                taskId: taskId,
                userId: userId,
                scheduleType: scheduleType,
                weekdaysMask: weekdaysMask,
                startsOn: startsOn,
                endsOn: endsOn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String userId,
                required String scheduleType,
                required int weekdaysMask,
                required String startsOn,
                Value<String?> endsOn = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TaskScheduleRecordsCompanion.insert(
                id: id,
                taskId: taskId,
                userId: userId,
                scheduleType: scheduleType,
                weekdaysMask: weekdaysMask,
                startsOn: startsOn,
                endsOn: endsOn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TaskScheduleRecordsTable, TaskScheduleRecord>(
                    table,
                  ),
                  $$TaskScheduleRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$TaskScheduleRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$TaskScheduleRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskScheduleRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskScheduleRecordsTable,
      TaskScheduleRecord,
      $$TaskScheduleRecordsTableFilterComposer,
      $$TaskScheduleRecordsTableOrderingComposer,
      $$TaskScheduleRecordsTableAnnotationComposer,
      $$TaskScheduleRecordsTableCreateCompanionBuilder,
      $$TaskScheduleRecordsTableUpdateCompanionBuilder,
      (TaskScheduleRecord, $$TaskScheduleRecordsTableReferences),
      TaskScheduleRecord,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$OneTimeReminderRecordsTableCreateCompanionBuilder =
    OneTimeReminderRecordsCompanion Function({
      required String taskId,
      required String userId,
      required DateTime scheduledAt,
      Value<bool> hasScheduledDate,
      Value<int?> remindBeforeMinutes,
      Value<bool> isTimed,
      Value<DateTime?> completedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$OneTimeReminderRecordsTableUpdateCompanionBuilder =
    OneTimeReminderRecordsCompanion Function({
      Value<String> taskId,
      Value<String> userId,
      Value<DateTime> scheduledAt,
      Value<bool> hasScheduledDate,
      Value<int?> remindBeforeMinutes,
      Value<bool> isTimed,
      Value<DateTime?> completedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$OneTimeReminderRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $OneTimeReminderRecordsTable,
          OneTimeReminderRecord
        > {
  $$OneTimeReminderRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) => db.localTasks
      .createAlias('one_time_reminder_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OneTimeReminderRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $OneTimeReminderRecordsTable> {
  $$OneTimeReminderRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasScheduledDate => $composableBuilder(
    column: $table.hasScheduledDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isTimed => $composableBuilder(
    column: $table.isTimed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OneTimeReminderRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $OneTimeReminderRecordsTable> {
  $$OneTimeReminderRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasScheduledDate => $composableBuilder(
    column: $table.hasScheduledDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isTimed => $composableBuilder(
    column: $table.isTimed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OneTimeReminderRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OneTimeReminderRecordsTable> {
  $$OneTimeReminderRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasScheduledDate => $composableBuilder(
    column: $table.hasScheduledDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isTimed =>
      $composableBuilder(column: $table.isTimed, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OneTimeReminderRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OneTimeReminderRecordsTable,
          OneTimeReminderRecord,
          $$OneTimeReminderRecordsTableFilterComposer,
          $$OneTimeReminderRecordsTableOrderingComposer,
          $$OneTimeReminderRecordsTableAnnotationComposer,
          $$OneTimeReminderRecordsTableCreateCompanionBuilder,
          $$OneTimeReminderRecordsTableUpdateCompanionBuilder,
          (OneTimeReminderRecord, $$OneTimeReminderRecordsTableReferences),
          OneTimeReminderRecord,
          PrefetchHooks Function({bool taskId})
        > {
  $$OneTimeReminderRecordsTableTableManager(
    _$AppDatabase db,
    $OneTimeReminderRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OneTimeReminderRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OneTimeReminderRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OneTimeReminderRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<bool> hasScheduledDate = const Value.absent(),
                Value<int?> remindBeforeMinutes = const Value.absent(),
                Value<bool> isTimed = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OneTimeReminderRecordsCompanion(
                taskId: taskId,
                userId: userId,
                scheduledAt: scheduledAt,
                hasScheduledDate: hasScheduledDate,
                remindBeforeMinutes: remindBeforeMinutes,
                isTimed: isTimed,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String userId,
                required DateTime scheduledAt,
                Value<bool> hasScheduledDate = const Value.absent(),
                Value<int?> remindBeforeMinutes = const Value.absent(),
                Value<bool> isTimed = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => OneTimeReminderRecordsCompanion.insert(
                taskId: taskId,
                userId: userId,
                scheduledAt: scheduledAt,
                hasScheduledDate: hasScheduledDate,
                remindBeforeMinutes: remindBeforeMinutes,
                isTimed: isTimed,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $OneTimeReminderRecordsTable,
                    OneTimeReminderRecord
                  >(table),
                  $$OneTimeReminderRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$OneTimeReminderRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$OneTimeReminderRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OneTimeReminderRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OneTimeReminderRecordsTable,
      OneTimeReminderRecord,
      $$OneTimeReminderRecordsTableFilterComposer,
      $$OneTimeReminderRecordsTableOrderingComposer,
      $$OneTimeReminderRecordsTableAnnotationComposer,
      $$OneTimeReminderRecordsTableCreateCompanionBuilder,
      $$OneTimeReminderRecordsTableUpdateCompanionBuilder,
      (OneTimeReminderRecord, $$OneTimeReminderRecordsTableReferences),
      OneTimeReminderRecord,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TaskCompletionRecordsTableCreateCompanionBuilder =
    TaskCompletionRecordsCompanion Function({
      required String id,
      required String taskId,
      required String userId,
      required String localDate,
      Value<int> actualDurationSeconds,
      Value<double> progressPercent,
      Value<bool> targetReached,
      Value<bool> isSuccess,
      Value<String?> exclusionReason,
      Value<DateTime?> completedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TaskCompletionRecordsTableUpdateCompanionBuilder =
    TaskCompletionRecordsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> userId,
      Value<String> localDate,
      Value<int> actualDurationSeconds,
      Value<double> progressPercent,
      Value<bool> targetReached,
      Value<bool> isSuccess,
      Value<String?> exclusionReason,
      Value<DateTime?> completedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TaskCompletionRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TaskCompletionRecordsTable,
          TaskCompletionRecord
        > {
  $$TaskCompletionRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) => db.localTasks
      .createAlias('task_completion_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskCompletionRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskCompletionRecordsTable> {
  $$TaskCompletionRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actualDurationSeconds => $composableBuilder(
    column: $table.actualDurationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get targetReached => $composableBuilder(
    column: $table.targetReached,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSuccess => $composableBuilder(
    column: $table.isSuccess,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exclusionReason => $composableBuilder(
    column: $table.exclusionReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskCompletionRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskCompletionRecordsTable> {
  $$TaskCompletionRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actualDurationSeconds => $composableBuilder(
    column: $table.actualDurationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get targetReached => $composableBuilder(
    column: $table.targetReached,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSuccess => $composableBuilder(
    column: $table.isSuccess,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exclusionReason => $composableBuilder(
    column: $table.exclusionReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskCompletionRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskCompletionRecordsTable> {
  $$TaskCompletionRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<int> get actualDurationSeconds => $composableBuilder(
    column: $table.actualDurationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progressPercent => $composableBuilder(
    column: $table.progressPercent,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get targetReached => $composableBuilder(
    column: $table.targetReached,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isSuccess =>
      $composableBuilder(column: $table.isSuccess, builder: (column) => column);

  GeneratedColumn<String> get exclusionReason => $composableBuilder(
    column: $table.exclusionReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskCompletionRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskCompletionRecordsTable,
          TaskCompletionRecord,
          $$TaskCompletionRecordsTableFilterComposer,
          $$TaskCompletionRecordsTableOrderingComposer,
          $$TaskCompletionRecordsTableAnnotationComposer,
          $$TaskCompletionRecordsTableCreateCompanionBuilder,
          $$TaskCompletionRecordsTableUpdateCompanionBuilder,
          (TaskCompletionRecord, $$TaskCompletionRecordsTableReferences),
          TaskCompletionRecord,
          PrefetchHooks Function({bool taskId})
        > {
  $$TaskCompletionRecordsTableTableManager(
    _$AppDatabase db,
    $TaskCompletionRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskCompletionRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$TaskCompletionRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TaskCompletionRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<int> actualDurationSeconds = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<bool> targetReached = const Value.absent(),
                Value<bool> isSuccess = const Value.absent(),
                Value<String?> exclusionReason = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskCompletionRecordsCompanion(
                id: id,
                taskId: taskId,
                userId: userId,
                localDate: localDate,
                actualDurationSeconds: actualDurationSeconds,
                progressPercent: progressPercent,
                targetReached: targetReached,
                isSuccess: isSuccess,
                exclusionReason: exclusionReason,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String userId,
                required String localDate,
                Value<int> actualDurationSeconds = const Value.absent(),
                Value<double> progressPercent = const Value.absent(),
                Value<bool> targetReached = const Value.absent(),
                Value<bool> isSuccess = const Value.absent(),
                Value<String?> exclusionReason = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TaskCompletionRecordsCompanion.insert(
                id: id,
                taskId: taskId,
                userId: userId,
                localDate: localDate,
                actualDurationSeconds: actualDurationSeconds,
                progressPercent: progressPercent,
                targetReached: targetReached,
                isSuccess: isSuccess,
                exclusionReason: exclusionReason,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $TaskCompletionRecordsTable,
                    TaskCompletionRecord
                  >(table),
                  $$TaskCompletionRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$TaskCompletionRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$TaskCompletionRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskCompletionRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskCompletionRecordsTable,
      TaskCompletionRecord,
      $$TaskCompletionRecordsTableFilterComposer,
      $$TaskCompletionRecordsTableOrderingComposer,
      $$TaskCompletionRecordsTableAnnotationComposer,
      $$TaskCompletionRecordsTableCreateCompanionBuilder,
      $$TaskCompletionRecordsTableUpdateCompanionBuilder,
      (TaskCompletionRecord, $$TaskCompletionRecordsTableReferences),
      TaskCompletionRecord,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TimerSessionRecordsTableCreateCompanionBuilder =
    TimerSessionRecordsCompanion Function({
      required String id,
      required String taskId,
      required String userId,
      Value<String?> tagId,
      required DateTime startedAt,
      Value<String?> logicalDate,
      Value<DateTime?> endedAt,
      Value<int> durationSeconds,
      required String state,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TimerSessionRecordsTableUpdateCompanionBuilder =
    TimerSessionRecordsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> userId,
      Value<String?> tagId,
      Value<DateTime> startedAt,
      Value<String?> logicalDate,
      Value<DateTime?> endedAt,
      Value<int> durationSeconds,
      Value<String> state,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TimerSessionRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TimerSessionRecordsTable,
          TimerSessionRecord
        > {
  $$TimerSessionRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) => db.localTasks
      .createAlias('timer_session_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TimerSessionRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TimerSessionRecordsTable> {
  $$TimerSessionRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logicalDate => $composableBuilder(
    column: $table.logicalDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimerSessionRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TimerSessionRecordsTable> {
  $$TimerSessionRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logicalDate => $composableBuilder(
    column: $table.logicalDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimerSessionRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimerSessionRecordsTable> {
  $$TimerSessionRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get logicalDate => $composableBuilder(
    column: $table.logicalDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimerSessionRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TimerSessionRecordsTable,
          TimerSessionRecord,
          $$TimerSessionRecordsTableFilterComposer,
          $$TimerSessionRecordsTableOrderingComposer,
          $$TimerSessionRecordsTableAnnotationComposer,
          $$TimerSessionRecordsTableCreateCompanionBuilder,
          $$TimerSessionRecordsTableUpdateCompanionBuilder,
          (TimerSessionRecord, $$TimerSessionRecordsTableReferences),
          TimerSessionRecord,
          PrefetchHooks Function({bool taskId})
        > {
  $$TimerSessionRecordsTableTableManager(
    _$AppDatabase db,
    $TimerSessionRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimerSessionRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimerSessionRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TimerSessionRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> tagId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<String?> logicalDate = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimerSessionRecordsCompanion(
                id: id,
                taskId: taskId,
                userId: userId,
                tagId: tagId,
                startedAt: startedAt,
                logicalDate: logicalDate,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String userId,
                Value<String?> tagId = const Value.absent(),
                required DateTime startedAt,
                Value<String?> logicalDate = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                required String state,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TimerSessionRecordsCompanion.insert(
                id: id,
                taskId: taskId,
                userId: userId,
                tagId: tagId,
                startedAt: startedAt,
                logicalDate: logicalDate,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TimerSessionRecordsTable, TimerSessionRecord>(
                    table,
                  ),
                  $$TimerSessionRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$TimerSessionRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$TimerSessionRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TimerSessionRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TimerSessionRecordsTable,
      TimerSessionRecord,
      $$TimerSessionRecordsTableFilterComposer,
      $$TimerSessionRecordsTableOrderingComposer,
      $$TimerSessionRecordsTableAnnotationComposer,
      $$TimerSessionRecordsTableCreateCompanionBuilder,
      $$TimerSessionRecordsTableUpdateCompanionBuilder,
      (TimerSessionRecord, $$TimerSessionRecordsTableReferences),
      TimerSessionRecord,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$TaskRevisionRecordsTableCreateCompanionBuilder =
    TaskRevisionRecordsCompanion Function({
      required String id,
      required String taskId,
      required String userId,
      Value<String?> beforeJson,
      required String afterJson,
      required DateTime changedAt,
      Value<int> rowid,
    });
typedef $$TaskRevisionRecordsTableUpdateCompanionBuilder =
    TaskRevisionRecordsCompanion Function({
      Value<String> id,
      Value<String> taskId,
      Value<String> userId,
      Value<String?> beforeJson,
      Value<String> afterJson,
      Value<DateTime> changedAt,
      Value<int> rowid,
    });

final class $$TaskRevisionRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TaskRevisionRecordsTable,
          TaskRevisionRecord
        > {
  $$TaskRevisionRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) => db.localTasks
      .createAlias('task_revision_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TaskRevisionRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskRevisionRecordsTable> {
  $$TaskRevisionRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterJson => $composableBuilder(
    column: $table.afterJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskRevisionRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskRevisionRecordsTable> {
  $$TaskRevisionRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterJson => $composableBuilder(
    column: $table.afterJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskRevisionRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskRevisionRecordsTable> {
  $$TaskRevisionRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get beforeJson => $composableBuilder(
    column: $table.beforeJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterJson =>
      $composableBuilder(column: $table.afterJson, builder: (column) => column);

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TaskRevisionRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskRevisionRecordsTable,
          TaskRevisionRecord,
          $$TaskRevisionRecordsTableFilterComposer,
          $$TaskRevisionRecordsTableOrderingComposer,
          $$TaskRevisionRecordsTableAnnotationComposer,
          $$TaskRevisionRecordsTableCreateCompanionBuilder,
          $$TaskRevisionRecordsTableUpdateCompanionBuilder,
          (TaskRevisionRecord, $$TaskRevisionRecordsTableReferences),
          TaskRevisionRecord,
          PrefetchHooks Function({bool taskId})
        > {
  $$TaskRevisionRecordsTableTableManager(
    _$AppDatabase db,
    $TaskRevisionRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskRevisionRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskRevisionRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TaskRevisionRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> beforeJson = const Value.absent(),
                Value<String> afterJson = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskRevisionRecordsCompanion(
                id: id,
                taskId: taskId,
                userId: userId,
                beforeJson: beforeJson,
                afterJson: afterJson,
                changedAt: changedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskId,
                required String userId,
                Value<String?> beforeJson = const Value.absent(),
                required String afterJson,
                required DateTime changedAt,
                Value<int> rowid = const Value.absent(),
              }) => TaskRevisionRecordsCompanion.insert(
                id: id,
                taskId: taskId,
                userId: userId,
                beforeJson: beforeJson,
                afterJson: afterJson,
                changedAt: changedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TaskRevisionRecordsTable, TaskRevisionRecord>(
                    table,
                  ),
                  $$TaskRevisionRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$TaskRevisionRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$TaskRevisionRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TaskRevisionRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskRevisionRecordsTable,
      TaskRevisionRecord,
      $$TaskRevisionRecordsTableFilterComposer,
      $$TaskRevisionRecordsTableOrderingComposer,
      $$TaskRevisionRecordsTableAnnotationComposer,
      $$TaskRevisionRecordsTableCreateCompanionBuilder,
      $$TaskRevisionRecordsTableUpdateCompanionBuilder,
      (TaskRevisionRecord, $$TaskRevisionRecordsTableReferences),
      TaskRevisionRecord,
      PrefetchHooks Function({bool taskId})
    >;
typedef $$SyncOperationsTableCreateCompanionBuilder =
    SyncOperationsCompanion Function({
      required String id,
      Value<String?> userId,
      required String entityType,
      required String entityId,
      required String operation,
      required String payloadJson,
      Value<String> status,
      Value<int> retryCount,
      Value<String?> lastError,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncOperationsTableUpdateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<String> id,
      Value<String?> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payloadJson,
      Value<String> status,
      Value<int> retryCount,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOperationsTable,
          SyncOperation,
          $$SyncOperationsTableFilterComposer,
          $$SyncOperationsTableOrderingComposer,
          $$SyncOperationsTableAnnotationComposer,
          $$SyncOperationsTableCreateCompanionBuilder,
          $$SyncOperationsTableUpdateCompanionBuilder,
          (
            SyncOperation,
            BaseReferences<_$AppDatabase, $SyncOperationsTable, SyncOperation>,
          ),
          SyncOperation,
          PrefetchHooks Function()
        > {
  $$SyncOperationsTableTableManager(
    _$AppDatabase db,
    $SyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOperationsCompanion(
                id: id,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                status: status,
                retryCount: retryCount,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> userId = const Value.absent(),
                required String entityType,
                required String entityId,
                required String operation,
                required String payloadJson,
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncOperationsCompanion.insert(
                id: id,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                status: status,
                retryCount: retryCount,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncOperationsTable, SyncOperation>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncOperationsTable,
                    SyncOperation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOperationsTable,
      SyncOperation,
      $$SyncOperationsTableFilterComposer,
      $$SyncOperationsTableOrderingComposer,
      $$SyncOperationsTableAnnotationComposer,
      $$SyncOperationsTableCreateCompanionBuilder,
      $$SyncOperationsTableUpdateCompanionBuilder,
      (
        SyncOperation,
        BaseReferences<_$AppDatabase, $SyncOperationsTable, SyncOperation>,
      ),
      SyncOperation,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$TagRecordsTableCreateCompanionBuilder =
    TagRecordsCompanion Function({
      required String id,
      required String userId,
      required String name,
      required int colorValue,
      Value<bool> archived,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$TagRecordsTableUpdateCompanionBuilder =
    TagRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<int> colorValue,
      Value<bool> archived,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$TagRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $TagRecordsTable, TagRecord> {
  $$TagRecordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TagRevisionRecordsTable, List<TagRevisionRecord>>
  _tagRevisionRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.tagRevisionRecords,
        aliasName: 'tag_records__id__tag_revision_records__tag_id',
      );

  $$TagRevisionRecordsTableProcessedTableManager get tagRevisionRecordsRefs {
    final manager = $$TagRevisionRecordsTableTableManager(
      $_db,
      $_db.tagRevisionRecords,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _tagRevisionRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TagRecordsTable> {
  $$TagRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> tagRevisionRecordsRefs(
    Expression<bool> Function($$TagRevisionRecordsTableFilterComposer f) f,
  ) {
    final $$TagRevisionRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tagRevisionRecords,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagRevisionRecordsTableFilterComposer(
            $db: $db,
            $table: $db.tagRevisionRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TagRecordsTable> {
  $$TagRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagRecordsTable> {
  $$TagRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> tagRevisionRecordsRefs<T extends Object>(
    Expression<T> Function($$TagRevisionRecordsTableAnnotationComposer a) f,
  ) {
    final $$TagRevisionRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.tagRevisionRecords,
          getReferencedColumn: (t) => t.tagId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TagRevisionRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.tagRevisionRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TagRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagRecordsTable,
          TagRecord,
          $$TagRecordsTableFilterComposer,
          $$TagRecordsTableOrderingComposer,
          $$TagRecordsTableAnnotationComposer,
          $$TagRecordsTableCreateCompanionBuilder,
          $$TagRecordsTableUpdateCompanionBuilder,
          (TagRecord, $$TagRecordsTableReferences),
          TagRecord,
          PrefetchHooks Function({bool tagRevisionRecordsRefs})
        > {
  $$TagRecordsTableTableManager(_$AppDatabase db, $TagRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagRecordsCompanion(
                id: id,
                userId: userId,
                name: name,
                colorValue: colorValue,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required int colorValue,
                Value<bool> archived = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => TagRecordsCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                colorValue: colorValue,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TagRecordsTable, TagRecord>(table),
                  $$TagRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tagRevisionRecordsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (tagRevisionRecordsRefs) db.tagRevisionRecords,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tagRevisionRecordsRefs)
                    await $_getPrefetchedData<
                      TagRecord,
                      $TagRecordsTable,
                      TagRevisionRecord
                    >(
                      currentTable: table,
                      referencedTable: $$TagRecordsTableReferences
                          ._tagRevisionRecordsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).tagRevisionRecordsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagRecordsTable,
      TagRecord,
      $$TagRecordsTableFilterComposer,
      $$TagRecordsTableOrderingComposer,
      $$TagRecordsTableAnnotationComposer,
      $$TagRecordsTableCreateCompanionBuilder,
      $$TagRecordsTableUpdateCompanionBuilder,
      (TagRecord, $$TagRecordsTableReferences),
      TagRecord,
      PrefetchHooks Function({bool tagRevisionRecordsRefs})
    >;
typedef $$TagRevisionRecordsTableCreateCompanionBuilder =
    TagRevisionRecordsCompanion Function({
      required String id,
      required String tagId,
      required String userId,
      required String snapshotJson,
      required DateTime changedAt,
      Value<int> rowid,
    });
typedef $$TagRevisionRecordsTableUpdateCompanionBuilder =
    TagRevisionRecordsCompanion Function({
      Value<String> id,
      Value<String> tagId,
      Value<String> userId,
      Value<String> snapshotJson,
      Value<DateTime> changedAt,
      Value<int> rowid,
    });

final class $$TagRevisionRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TagRevisionRecordsTable,
          TagRevisionRecord
        > {
  $$TagRevisionRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TagRecordsTable _tagIdTable(_$AppDatabase db) => db.tagRecords
      .createAlias('tag_revision_records__tag_id__tag_records__id');

  $$TagRecordsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagRecordsTableTableManager(
      $_db,
      $_db.tagRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TagRevisionRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $TagRevisionRecordsTable> {
  $$TagRevisionRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$TagRecordsTableFilterComposer get tagId {
    final $$TagRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagRecordsTableFilterComposer(
            $db: $db,
            $table: $db.tagRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagRevisionRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $TagRevisionRecordsTable> {
  $$TagRevisionRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TagRecordsTableOrderingComposer get tagId {
    final $$TagRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.tagRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagRevisionRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagRevisionRecordsTable> {
  $$TagRevisionRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  $$TagRecordsTableAnnotationComposer get tagId {
    final $$TagRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tagRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.tagRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagRevisionRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagRevisionRecordsTable,
          TagRevisionRecord,
          $$TagRevisionRecordsTableFilterComposer,
          $$TagRevisionRecordsTableOrderingComposer,
          $$TagRevisionRecordsTableAnnotationComposer,
          $$TagRevisionRecordsTableCreateCompanionBuilder,
          $$TagRevisionRecordsTableUpdateCompanionBuilder,
          (TagRevisionRecord, $$TagRevisionRecordsTableReferences),
          TagRevisionRecord,
          PrefetchHooks Function({bool tagId})
        > {
  $$TagRevisionRecordsTableTableManager(
    _$AppDatabase db,
    $TagRevisionRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagRevisionRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagRevisionRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagRevisionRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> snapshotJson = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagRevisionRecordsCompanion(
                id: id,
                tagId: tagId,
                userId: userId,
                snapshotJson: snapshotJson,
                changedAt: changedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String tagId,
                required String userId,
                required String snapshotJson,
                required DateTime changedAt,
                Value<int> rowid = const Value.absent(),
              }) => TagRevisionRecordsCompanion.insert(
                id: id,
                tagId: tagId,
                userId: userId,
                snapshotJson: snapshotJson,
                changedAt: changedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TagRevisionRecordsTable, TagRevisionRecord>(
                    table,
                  ),
                  $$TagRevisionRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable:
                                    $$TagRevisionRecordsTableReferences
                                        ._tagIdTable(db),
                                referencedColumn:
                                    $$TagRevisionRecordsTableReferences
                                        ._tagIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TagRevisionRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagRevisionRecordsTable,
      TagRevisionRecord,
      $$TagRevisionRecordsTableFilterComposer,
      $$TagRevisionRecordsTableOrderingComposer,
      $$TagRevisionRecordsTableAnnotationComposer,
      $$TagRevisionRecordsTableCreateCompanionBuilder,
      $$TagRevisionRecordsTableUpdateCompanionBuilder,
      (TagRevisionRecord, $$TagRevisionRecordsTableReferences),
      TagRevisionRecord,
      PrefetchHooks Function({bool tagId})
    >;
typedef $$PlanRecordsTableCreateCompanionBuilder =
    PlanRecordsCompanion Function({
      required String id,
      required String userId,
      required String name,
      required String type,
      required int colorValue,
      Value<String?> goal,
      required String startsOn,
      required String endsOn,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$PlanRecordsTableUpdateCompanionBuilder =
    PlanRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> type,
      Value<int> colorValue,
      Value<String?> goal,
      Value<String> startsOn,
      Value<String> endsOn,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$PlanRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $PlanRecordsTable, PlanRecord> {
  $$PlanRecordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PlanTaskRecordsTable, List<PlanTaskRecord>>
  _planTaskRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.planTaskRecords,
    aliasName: 'plan_records__id__plan_task_records__plan_id',
  );

  $$PlanTaskRecordsTableProcessedTableManager get planTaskRecordsRefs {
    final manager = $$PlanTaskRecordsTableTableManager(
      $_db,
      $_db.planTaskRecords,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _planTaskRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PlanRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $PlanRecordsTable> {
  $$PlanRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startsOn => $composableBuilder(
    column: $table.startsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endsOn => $composableBuilder(
    column: $table.endsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> planTaskRecordsRefs(
    Expression<bool> Function($$PlanTaskRecordsTableFilterComposer f) f,
  ) {
    final $$PlanTaskRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planTaskRecords,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanTaskRecordsTableFilterComposer(
            $db: $db,
            $table: $db.planTaskRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlanRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanRecordsTable> {
  $$PlanRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startsOn => $composableBuilder(
    column: $table.startsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endsOn => $composableBuilder(
    column: $table.endsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanRecordsTable> {
  $$PlanRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<String> get startsOn =>
      $composableBuilder(column: $table.startsOn, builder: (column) => column);

  GeneratedColumn<String> get endsOn =>
      $composableBuilder(column: $table.endsOn, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> planTaskRecordsRefs<T extends Object>(
    Expression<T> Function($$PlanTaskRecordsTableAnnotationComposer a) f,
  ) {
    final $$PlanTaskRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.planTaskRecords,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanTaskRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.planTaskRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlanRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanRecordsTable,
          PlanRecord,
          $$PlanRecordsTableFilterComposer,
          $$PlanRecordsTableOrderingComposer,
          $$PlanRecordsTableAnnotationComposer,
          $$PlanRecordsTableCreateCompanionBuilder,
          $$PlanRecordsTableUpdateCompanionBuilder,
          (PlanRecord, $$PlanRecordsTableReferences),
          PlanRecord,
          PrefetchHooks Function({bool planTaskRecordsRefs})
        > {
  $$PlanRecordsTableTableManager(_$AppDatabase db, $PlanRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String?> goal = const Value.absent(),
                Value<String> startsOn = const Value.absent(),
                Value<String> endsOn = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanRecordsCompanion(
                id: id,
                userId: userId,
                name: name,
                type: type,
                colorValue: colorValue,
                goal: goal,
                startsOn: startsOn,
                endsOn: endsOn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required String type,
                required int colorValue,
                Value<String?> goal = const Value.absent(),
                required String startsOn,
                required String endsOn,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanRecordsCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                type: type,
                colorValue: colorValue,
                goal: goal,
                startsOn: startsOn,
                endsOn: endsOn,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanRecordsTable, PlanRecord>(table),
                  $$PlanRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planTaskRecordsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (planTaskRecordsRefs) db.planTaskRecords,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (planTaskRecordsRefs)
                    await $_getPrefetchedData<
                      PlanRecord,
                      $PlanRecordsTable,
                      PlanTaskRecord
                    >(
                      currentTable: table,
                      referencedTable: $$PlanRecordsTableReferences
                          ._planTaskRecordsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PlanRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).planTaskRecordsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.planId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PlanRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanRecordsTable,
      PlanRecord,
      $$PlanRecordsTableFilterComposer,
      $$PlanRecordsTableOrderingComposer,
      $$PlanRecordsTableAnnotationComposer,
      $$PlanRecordsTableCreateCompanionBuilder,
      $$PlanRecordsTableUpdateCompanionBuilder,
      (PlanRecord, $$PlanRecordsTableReferences),
      PlanRecord,
      PrefetchHooks Function({bool planTaskRecordsRefs})
    >;
typedef $$PlanTaskRecordsTableCreateCompanionBuilder =
    PlanTaskRecordsCompanion Function({
      required String planId,
      required String taskId,
      required String userId,
      Value<double> weight,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlanTaskRecordsTableUpdateCompanionBuilder =
    PlanTaskRecordsCompanion Function({
      Value<String> planId,
      Value<String> taskId,
      Value<String> userId,
      Value<double> weight,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$PlanTaskRecordsTableReferences
    extends
        BaseReferences<_$AppDatabase, $PlanTaskRecordsTable, PlanTaskRecord> {
  $$PlanTaskRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PlanRecordsTable _planIdTable(_$AppDatabase db) => db.planRecords
      .createAlias('plan_task_records__plan_id__plan_records__id');

  $$PlanRecordsTableProcessedTableManager get planId {
    final $_column = $_itemColumn<String>('plan_id')!;

    final manager = $$PlanRecordsTableTableManager(
      $_db,
      $_db.planRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LocalTasksTable _taskIdTable(_$AppDatabase db) =>
      db.localTasks.createAlias('plan_task_records__task_id__local_tasks__id');

  $$LocalTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager = $$LocalTasksTableTableManager(
      $_db,
      $_db.localTasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlanTaskRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $PlanTaskRecordsTable> {
  $$PlanTaskRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PlanRecordsTableFilterComposer get planId {
    final $$PlanRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.planRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanRecordsTableFilterComposer(
            $db: $db,
            $table: $db.planRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LocalTasksTableFilterComposer get taskId {
    final $$LocalTasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableFilterComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanTaskRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlanTaskRecordsTable> {
  $$PlanTaskRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlanRecordsTableOrderingComposer get planId {
    final $$PlanRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.planRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.planRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LocalTasksTableOrderingComposer get taskId {
    final $$LocalTasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableOrderingComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanTaskRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlanTaskRecordsTable> {
  $$PlanTaskRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PlanRecordsTableAnnotationComposer get planId {
    final $$PlanRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.planRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlanRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.planRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LocalTasksTableAnnotationComposer get taskId {
    final $$LocalTasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.localTasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalTasksTableAnnotationComposer(
            $db: $db,
            $table: $db.localTasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlanTaskRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlanTaskRecordsTable,
          PlanTaskRecord,
          $$PlanTaskRecordsTableFilterComposer,
          $$PlanTaskRecordsTableOrderingComposer,
          $$PlanTaskRecordsTableAnnotationComposer,
          $$PlanTaskRecordsTableCreateCompanionBuilder,
          $$PlanTaskRecordsTableUpdateCompanionBuilder,
          (PlanTaskRecord, $$PlanTaskRecordsTableReferences),
          PlanTaskRecord,
          PrefetchHooks Function({bool planId, bool taskId})
        > {
  $$PlanTaskRecordsTableTableManager(
    _$AppDatabase db,
    $PlanTaskRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanTaskRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlanTaskRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlanTaskRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> planId = const Value.absent(),
                Value<String> taskId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanTaskRecordsCompanion(
                planId: planId,
                taskId: taskId,
                userId: userId,
                weight: weight,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String planId,
                required String taskId,
                required String userId,
                Value<double> weight = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanTaskRecordsCompanion.insert(
                planId: planId,
                taskId: taskId,
                userId: userId,
                weight: weight,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlanTaskRecordsTable, PlanTaskRecord>(table),
                  $$PlanTaskRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planId = false, taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (planId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.planId,
                                referencedTable:
                                    $$PlanTaskRecordsTableReferences
                                        ._planIdTable(db),
                                referencedColumn:
                                    $$PlanTaskRecordsTableReferences
                                        ._planIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (taskId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.taskId,
                                referencedTable:
                                    $$PlanTaskRecordsTableReferences
                                        ._taskIdTable(db),
                                referencedColumn:
                                    $$PlanTaskRecordsTableReferences
                                        ._taskIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlanTaskRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlanTaskRecordsTable,
      PlanTaskRecord,
      $$PlanTaskRecordsTableFilterComposer,
      $$PlanTaskRecordsTableOrderingComposer,
      $$PlanTaskRecordsTableAnnotationComposer,
      $$PlanTaskRecordsTableCreateCompanionBuilder,
      $$PlanTaskRecordsTableUpdateCompanionBuilder,
      (PlanTaskRecord, $$PlanTaskRecordsTableReferences),
      PlanTaskRecord,
      PrefetchHooks Function({bool planId, bool taskId})
    >;
typedef $$ReviewRecordsTableCreateCompanionBuilder =
    ReviewRecordsCompanion Function({
      required String id,
      required String userId,
      required String reviewType,
      required String periodStart,
      required String periodEnd,
      Value<String?> happenedText,
      Value<String?> learnedText,
      Value<String?> improveText,
      Value<int?> mood,
      Value<String> objectiveSnapshotJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ReviewRecordsTableUpdateCompanionBuilder =
    ReviewRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> reviewType,
      Value<String> periodStart,
      Value<String> periodEnd,
      Value<String?> happenedText,
      Value<String?> learnedText,
      Value<String?> improveText,
      Value<int?> mood,
      Value<String> objectiveSnapshotJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ReviewRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewRecordsTable> {
  $$ReviewRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewType => $composableBuilder(
    column: $table.reviewType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get happenedText => $composableBuilder(
    column: $table.happenedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get learnedText => $composableBuilder(
    column: $table.learnedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get improveText => $composableBuilder(
    column: $table.improveText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectiveSnapshotJson => $composableBuilder(
    column: $table.objectiveSnapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewRecordsTable> {
  $$ReviewRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewType => $composableBuilder(
    column: $table.reviewType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get happenedText => $composableBuilder(
    column: $table.happenedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get learnedText => $composableBuilder(
    column: $table.learnedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get improveText => $composableBuilder(
    column: $table.improveText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectiveSnapshotJson => $composableBuilder(
    column: $table.objectiveSnapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewRecordsTable> {
  $$ReviewRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get reviewType => $composableBuilder(
    column: $table.reviewType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodStart => $composableBuilder(
    column: $table.periodStart,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodEnd =>
      $composableBuilder(column: $table.periodEnd, builder: (column) => column);

  GeneratedColumn<String> get happenedText => $composableBuilder(
    column: $table.happenedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get learnedText => $composableBuilder(
    column: $table.learnedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get improveText => $composableBuilder(
    column: $table.improveText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get objectiveSnapshotJson => $composableBuilder(
    column: $table.objectiveSnapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ReviewRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewRecordsTable,
          ReviewRecord,
          $$ReviewRecordsTableFilterComposer,
          $$ReviewRecordsTableOrderingComposer,
          $$ReviewRecordsTableAnnotationComposer,
          $$ReviewRecordsTableCreateCompanionBuilder,
          $$ReviewRecordsTableUpdateCompanionBuilder,
          (
            ReviewRecord,
            BaseReferences<_$AppDatabase, $ReviewRecordsTable, ReviewRecord>,
          ),
          ReviewRecord,
          PrefetchHooks Function()
        > {
  $$ReviewRecordsTableTableManager(_$AppDatabase db, $ReviewRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> reviewType = const Value.absent(),
                Value<String> periodStart = const Value.absent(),
                Value<String> periodEnd = const Value.absent(),
                Value<String?> happenedText = const Value.absent(),
                Value<String?> learnedText = const Value.absent(),
                Value<String?> improveText = const Value.absent(),
                Value<int?> mood = const Value.absent(),
                Value<String> objectiveSnapshotJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewRecordsCompanion(
                id: id,
                userId: userId,
                reviewType: reviewType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                happenedText: happenedText,
                learnedText: learnedText,
                improveText: improveText,
                mood: mood,
                objectiveSnapshotJson: objectiveSnapshotJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String reviewType,
                required String periodStart,
                required String periodEnd,
                Value<String?> happenedText = const Value.absent(),
                Value<String?> learnedText = const Value.absent(),
                Value<String?> improveText = const Value.absent(),
                Value<int?> mood = const Value.absent(),
                Value<String> objectiveSnapshotJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewRecordsCompanion.insert(
                id: id,
                userId: userId,
                reviewType: reviewType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                happenedText: happenedText,
                learnedText: learnedText,
                improveText: improveText,
                mood: mood,
                objectiveSnapshotJson: objectiveSnapshotJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewRecordsTable, ReviewRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReviewRecordsTable,
                    ReviewRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewRecordsTable,
      ReviewRecord,
      $$ReviewRecordsTableFilterComposer,
      $$ReviewRecordsTableOrderingComposer,
      $$ReviewRecordsTableAnnotationComposer,
      $$ReviewRecordsTableCreateCompanionBuilder,
      $$ReviewRecordsTableUpdateCompanionBuilder,
      (
        ReviewRecord,
        BaseReferences<_$AppDatabase, $ReviewRecordsTable, ReviewRecord>,
      ),
      ReviewRecord,
      PrefetchHooks Function()
    >;
typedef $$CourseRecordsTableCreateCompanionBuilder =
    CourseRecordsCompanion Function({
      required String id,
      required String userId,
      required String name,
      required int colorValue,
      Value<String?> teacher,
      Value<String?> classroom,
      Value<String?> semester,
      Value<String?> semesterId,
      Value<DateTime?> semesterStartsOn,
      Value<DateTime?> semesterEndsOn,
      Value<String?> notes,
      Value<String> status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$CourseRecordsTableUpdateCompanionBuilder =
    CourseRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<int> colorValue,
      Value<String?> teacher,
      Value<String?> classroom,
      Value<String?> semester,
      Value<String?> semesterId,
      Value<DateTime?> semesterStartsOn,
      Value<DateTime?> semesterEndsOn,
      Value<String?> notes,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$CourseRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $CourseRecordsTable, CourseRecord> {
  $$CourseRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $CourseScheduleRuleRecordsTable,
    List<CourseScheduleRuleRecord>
  >
  _courseScheduleRuleRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.courseScheduleRuleRecords,
        aliasName:
            'course_records__id__course_schedule_rule_records__course_id',
      );

  $$CourseScheduleRuleRecordsTableProcessedTableManager
  get courseScheduleRuleRecordsRefs {
    final manager = $$CourseScheduleRuleRecordsTableTableManager(
      $_db,
      $_db.courseScheduleRuleRecords,
    ).filter((f) => f.courseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _courseScheduleRuleRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CourseRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $CourseRecordsTable> {
  $$CourseRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teacher => $composableBuilder(
    column: $table.teacher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get classroom => $composableBuilder(
    column: $table.classroom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get semester => $composableBuilder(
    column: $table.semester,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get semesterStartsOn => $composableBuilder(
    column: $table.semesterStartsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get semesterEndsOn => $composableBuilder(
    column: $table.semesterEndsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> courseScheduleRuleRecordsRefs(
    Expression<bool> Function($$CourseScheduleRuleRecordsTableFilterComposer f)
    f,
  ) {
    final $$CourseScheduleRuleRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.courseScheduleRuleRecords,
          getReferencedColumn: (t) => t.courseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CourseScheduleRuleRecordsTableFilterComposer(
                $db: $db,
                $table: $db.courseScheduleRuleRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CourseRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseRecordsTable> {
  $$CourseRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teacher => $composableBuilder(
    column: $table.teacher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get classroom => $composableBuilder(
    column: $table.classroom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get semester => $composableBuilder(
    column: $table.semester,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get semesterStartsOn => $composableBuilder(
    column: $table.semesterStartsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get semesterEndsOn => $composableBuilder(
    column: $table.semesterEndsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CourseRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseRecordsTable> {
  $$CourseRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teacher =>
      $composableBuilder(column: $table.teacher, builder: (column) => column);

  GeneratedColumn<String> get classroom =>
      $composableBuilder(column: $table.classroom, builder: (column) => column);

  GeneratedColumn<String> get semester =>
      $composableBuilder(column: $table.semester, builder: (column) => column);

  GeneratedColumn<String> get semesterId => $composableBuilder(
    column: $table.semesterId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get semesterStartsOn => $composableBuilder(
    column: $table.semesterStartsOn,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get semesterEndsOn => $composableBuilder(
    column: $table.semesterEndsOn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> courseScheduleRuleRecordsRefs<T extends Object>(
    Expression<T> Function($$CourseScheduleRuleRecordsTableAnnotationComposer a)
    f,
  ) {
    final $$CourseScheduleRuleRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.courseScheduleRuleRecords,
          getReferencedColumn: (t) => t.courseId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CourseScheduleRuleRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.courseScheduleRuleRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CourseRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CourseRecordsTable,
          CourseRecord,
          $$CourseRecordsTableFilterComposer,
          $$CourseRecordsTableOrderingComposer,
          $$CourseRecordsTableAnnotationComposer,
          $$CourseRecordsTableCreateCompanionBuilder,
          $$CourseRecordsTableUpdateCompanionBuilder,
          (CourseRecord, $$CourseRecordsTableReferences),
          CourseRecord,
          PrefetchHooks Function({bool courseScheduleRuleRecordsRefs})
        > {
  $$CourseRecordsTableTableManager(_$AppDatabase db, $CourseRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String?> teacher = const Value.absent(),
                Value<String?> classroom = const Value.absent(),
                Value<String?> semester = const Value.absent(),
                Value<String?> semesterId = const Value.absent(),
                Value<DateTime?> semesterStartsOn = const Value.absent(),
                Value<DateTime?> semesterEndsOn = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CourseRecordsCompanion(
                id: id,
                userId: userId,
                name: name,
                colorValue: colorValue,
                teacher: teacher,
                classroom: classroom,
                semester: semester,
                semesterId: semesterId,
                semesterStartsOn: semesterStartsOn,
                semesterEndsOn: semesterEndsOn,
                notes: notes,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required int colorValue,
                Value<String?> teacher = const Value.absent(),
                Value<String?> classroom = const Value.absent(),
                Value<String?> semester = const Value.absent(),
                Value<String?> semesterId = const Value.absent(),
                Value<DateTime?> semesterStartsOn = const Value.absent(),
                Value<DateTime?> semesterEndsOn = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CourseRecordsCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                colorValue: colorValue,
                teacher: teacher,
                classroom: classroom,
                semester: semester,
                semesterId: semesterId,
                semesterStartsOn: semesterStartsOn,
                semesterEndsOn: semesterEndsOn,
                notes: notes,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CourseRecordsTable, CourseRecord>(table),
                  $$CourseRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({courseScheduleRuleRecordsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (courseScheduleRuleRecordsRefs) db.courseScheduleRuleRecords,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (courseScheduleRuleRecordsRefs)
                    await $_getPrefetchedData<
                      CourseRecord,
                      $CourseRecordsTable,
                      CourseScheduleRuleRecord
                    >(
                      currentTable: table,
                      referencedTable: $$CourseRecordsTableReferences
                          ._courseScheduleRuleRecordsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CourseRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).courseScheduleRuleRecordsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.courseId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CourseRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CourseRecordsTable,
      CourseRecord,
      $$CourseRecordsTableFilterComposer,
      $$CourseRecordsTableOrderingComposer,
      $$CourseRecordsTableAnnotationComposer,
      $$CourseRecordsTableCreateCompanionBuilder,
      $$CourseRecordsTableUpdateCompanionBuilder,
      (CourseRecord, $$CourseRecordsTableReferences),
      CourseRecord,
      PrefetchHooks Function({bool courseScheduleRuleRecordsRefs})
    >;
typedef $$CourseScheduleRuleRecordsTableCreateCompanionBuilder =
    CourseScheduleRuleRecordsCompanion Function({
      required String id,
      required String courseId,
      required String userId,
      required int weekday,
      required String weekRuleType,
      Value<int?> startWeek,
      Value<int?> endWeek,
      Value<int?> intervalWeeks,
      Value<String> weekNumbersJson,
      Value<String?> scheduleTemplateId,
      Value<String> sectionIdsJson,
      required int startsAtMinute,
      required int endsAtMinute,
      Value<int?> remindBeforeMinutes,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$CourseScheduleRuleRecordsTableUpdateCompanionBuilder =
    CourseScheduleRuleRecordsCompanion Function({
      Value<String> id,
      Value<String> courseId,
      Value<String> userId,
      Value<int> weekday,
      Value<String> weekRuleType,
      Value<int?> startWeek,
      Value<int?> endWeek,
      Value<int?> intervalWeeks,
      Value<String> weekNumbersJson,
      Value<String?> scheduleTemplateId,
      Value<String> sectionIdsJson,
      Value<int> startsAtMinute,
      Value<int> endsAtMinute,
      Value<int?> remindBeforeMinutes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$CourseScheduleRuleRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CourseScheduleRuleRecordsTable,
          CourseScheduleRuleRecord
        > {
  $$CourseScheduleRuleRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CourseRecordsTable _courseIdTable(_$AppDatabase db) =>
      db.courseRecords.createAlias(
        'course_schedule_rule_records__course_id__course_records__id',
      );

  $$CourseRecordsTableProcessedTableManager get courseId {
    final $_column = $_itemColumn<String>('course_id')!;

    final manager = $$CourseRecordsTableTableManager(
      $_db,
      $_db.courseRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_courseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CourseScheduleRuleRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $CourseScheduleRuleRecordsTable> {
  $$CourseScheduleRuleRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekRuleType => $composableBuilder(
    column: $table.weekRuleType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startWeek => $composableBuilder(
    column: $table.startWeek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endWeek => $composableBuilder(
    column: $table.endWeek,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalWeeks => $composableBuilder(
    column: $table.intervalWeeks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weekNumbersJson => $composableBuilder(
    column: $table.weekNumbersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleTemplateId => $composableBuilder(
    column: $table.scheduleTemplateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sectionIdsJson => $composableBuilder(
    column: $table.sectionIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMinute => $composableBuilder(
    column: $table.startsAtMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMinute => $composableBuilder(
    column: $table.endsAtMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CourseRecordsTableFilterComposer get courseId {
    final $$CourseRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.courseId,
      referencedTable: $db.courseRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRecordsTableFilterComposer(
            $db: $db,
            $table: $db.courseRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseScheduleRuleRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $CourseScheduleRuleRecordsTable> {
  $$CourseScheduleRuleRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekday => $composableBuilder(
    column: $table.weekday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekRuleType => $composableBuilder(
    column: $table.weekRuleType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startWeek => $composableBuilder(
    column: $table.startWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endWeek => $composableBuilder(
    column: $table.endWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalWeeks => $composableBuilder(
    column: $table.intervalWeeks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weekNumbersJson => $composableBuilder(
    column: $table.weekNumbersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleTemplateId => $composableBuilder(
    column: $table.scheduleTemplateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sectionIdsJson => $composableBuilder(
    column: $table.sectionIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMinute => $composableBuilder(
    column: $table.startsAtMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMinute => $composableBuilder(
    column: $table.endsAtMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CourseRecordsTableOrderingComposer get courseId {
    final $$CourseRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.courseId,
      referencedTable: $db.courseRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.courseRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseScheduleRuleRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CourseScheduleRuleRecordsTable> {
  $$CourseScheduleRuleRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get weekday =>
      $composableBuilder(column: $table.weekday, builder: (column) => column);

  GeneratedColumn<String> get weekRuleType => $composableBuilder(
    column: $table.weekRuleType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startWeek =>
      $composableBuilder(column: $table.startWeek, builder: (column) => column);

  GeneratedColumn<int> get endWeek =>
      $composableBuilder(column: $table.endWeek, builder: (column) => column);

  GeneratedColumn<int> get intervalWeeks => $composableBuilder(
    column: $table.intervalWeeks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weekNumbersJson => $composableBuilder(
    column: $table.weekNumbersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scheduleTemplateId => $composableBuilder(
    column: $table.scheduleTemplateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sectionIdsJson => $composableBuilder(
    column: $table.sectionIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startsAtMinute => $composableBuilder(
    column: $table.startsAtMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMinute => $composableBuilder(
    column: $table.endsAtMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$CourseRecordsTableAnnotationComposer get courseId {
    final $$CourseRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.courseId,
      referencedTable: $db.courseRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CourseRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.courseRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CourseScheduleRuleRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CourseScheduleRuleRecordsTable,
          CourseScheduleRuleRecord,
          $$CourseScheduleRuleRecordsTableFilterComposer,
          $$CourseScheduleRuleRecordsTableOrderingComposer,
          $$CourseScheduleRuleRecordsTableAnnotationComposer,
          $$CourseScheduleRuleRecordsTableCreateCompanionBuilder,
          $$CourseScheduleRuleRecordsTableUpdateCompanionBuilder,
          (
            CourseScheduleRuleRecord,
            $$CourseScheduleRuleRecordsTableReferences,
          ),
          CourseScheduleRuleRecord,
          PrefetchHooks Function({bool courseId})
        > {
  $$CourseScheduleRuleRecordsTableTableManager(
    _$AppDatabase db,
    $CourseScheduleRuleRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseScheduleRuleRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CourseScheduleRuleRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CourseScheduleRuleRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> courseId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> weekday = const Value.absent(),
                Value<String> weekRuleType = const Value.absent(),
                Value<int?> startWeek = const Value.absent(),
                Value<int?> endWeek = const Value.absent(),
                Value<int?> intervalWeeks = const Value.absent(),
                Value<String> weekNumbersJson = const Value.absent(),
                Value<String?> scheduleTemplateId = const Value.absent(),
                Value<String> sectionIdsJson = const Value.absent(),
                Value<int> startsAtMinute = const Value.absent(),
                Value<int> endsAtMinute = const Value.absent(),
                Value<int?> remindBeforeMinutes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CourseScheduleRuleRecordsCompanion(
                id: id,
                courseId: courseId,
                userId: userId,
                weekday: weekday,
                weekRuleType: weekRuleType,
                startWeek: startWeek,
                endWeek: endWeek,
                intervalWeeks: intervalWeeks,
                weekNumbersJson: weekNumbersJson,
                scheduleTemplateId: scheduleTemplateId,
                sectionIdsJson: sectionIdsJson,
                startsAtMinute: startsAtMinute,
                endsAtMinute: endsAtMinute,
                remindBeforeMinutes: remindBeforeMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String courseId,
                required String userId,
                required int weekday,
                required String weekRuleType,
                Value<int?> startWeek = const Value.absent(),
                Value<int?> endWeek = const Value.absent(),
                Value<int?> intervalWeeks = const Value.absent(),
                Value<String> weekNumbersJson = const Value.absent(),
                Value<String?> scheduleTemplateId = const Value.absent(),
                Value<String> sectionIdsJson = const Value.absent(),
                required int startsAtMinute,
                required int endsAtMinute,
                Value<int?> remindBeforeMinutes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CourseScheduleRuleRecordsCompanion.insert(
                id: id,
                courseId: courseId,
                userId: userId,
                weekday: weekday,
                weekRuleType: weekRuleType,
                startWeek: startWeek,
                endWeek: endWeek,
                intervalWeeks: intervalWeeks,
                weekNumbersJson: weekNumbersJson,
                scheduleTemplateId: scheduleTemplateId,
                sectionIdsJson: sectionIdsJson,
                startsAtMinute: startsAtMinute,
                endsAtMinute: endsAtMinute,
                remindBeforeMinutes: remindBeforeMinutes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $CourseScheduleRuleRecordsTable,
                    CourseScheduleRuleRecord
                  >(table),
                  $$CourseScheduleRuleRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({courseId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (courseId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.courseId,
                                referencedTable:
                                    $$CourseScheduleRuleRecordsTableReferences
                                        ._courseIdTable(db),
                                referencedColumn:
                                    $$CourseScheduleRuleRecordsTableReferences
                                        ._courseIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CourseScheduleRuleRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CourseScheduleRuleRecordsTable,
      CourseScheduleRuleRecord,
      $$CourseScheduleRuleRecordsTableFilterComposer,
      $$CourseScheduleRuleRecordsTableOrderingComposer,
      $$CourseScheduleRuleRecordsTableAnnotationComposer,
      $$CourseScheduleRuleRecordsTableCreateCompanionBuilder,
      $$CourseScheduleRuleRecordsTableUpdateCompanionBuilder,
      (CourseScheduleRuleRecord, $$CourseScheduleRuleRecordsTableReferences),
      CourseScheduleRuleRecord,
      PrefetchHooks Function({bool courseId})
    >;
typedef $$ScheduleTemplateRecordsTableCreateCompanionBuilder =
    ScheduleTemplateRecordsCompanion Function({
      required String id,
      required String userId,
      required String name,
      Value<String> timezone,
      Value<bool> isDefault,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ScheduleTemplateRecordsTableUpdateCompanionBuilder =
    ScheduleTemplateRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<String> timezone,
      Value<bool> isDefault,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$ScheduleTemplateRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ScheduleTemplateRecordsTable,
          ScheduleTemplateRecord
        > {
  $$ScheduleTemplateRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $ScheduleTemplateSegmentRecordsTable,
    List<ScheduleTemplateSegmentRecord>
  >
  _scheduleTemplateSegmentRecordsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.scheduleTemplateSegmentRecords,
    aliasName:
        'schedule_template_records__id__schedule_template_segment_records__template_id',
  );

  $$ScheduleTemplateSegmentRecordsTableProcessedTableManager
  get scheduleTemplateSegmentRecordsRefs {
    final manager = $$ScheduleTemplateSegmentRecordsTableTableManager(
      $_db,
      $_db.scheduleTemplateSegmentRecords,
    ).filter((f) => f.templateId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleTemplateSegmentRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ScheduleTemplateRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleTemplateRecordsTable> {
  $$ScheduleTemplateRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> scheduleTemplateSegmentRecordsRefs(
    Expression<bool> Function(
      $$ScheduleTemplateSegmentRecordsTableFilterComposer f,
    )
    f,
  ) {
    final $$ScheduleTemplateSegmentRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.scheduleTemplateSegmentRecords,
          getReferencedColumn: (t) => t.templateId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplateSegmentRecordsTableFilterComposer(
                $db: $db,
                $table: $db.scheduleTemplateSegmentRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ScheduleTemplateRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleTemplateRecordsTable> {
  $$ScheduleTemplateRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScheduleTemplateRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleTemplateRecordsTable> {
  $$ScheduleTemplateRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> scheduleTemplateSegmentRecordsRefs<T extends Object>(
    Expression<T> Function(
      $$ScheduleTemplateSegmentRecordsTableAnnotationComposer a,
    )
    f,
  ) {
    final $$ScheduleTemplateSegmentRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.scheduleTemplateSegmentRecords,
          getReferencedColumn: (t) => t.templateId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplateSegmentRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleTemplateSegmentRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ScheduleTemplateRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleTemplateRecordsTable,
          ScheduleTemplateRecord,
          $$ScheduleTemplateRecordsTableFilterComposer,
          $$ScheduleTemplateRecordsTableOrderingComposer,
          $$ScheduleTemplateRecordsTableAnnotationComposer,
          $$ScheduleTemplateRecordsTableCreateCompanionBuilder,
          $$ScheduleTemplateRecordsTableUpdateCompanionBuilder,
          (ScheduleTemplateRecord, $$ScheduleTemplateRecordsTableReferences),
          ScheduleTemplateRecord,
          PrefetchHooks Function({bool scheduleTemplateSegmentRecordsRefs})
        > {
  $$ScheduleTemplateRecordsTableTableManager(
    _$AppDatabase db,
    $ScheduleTemplateRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduleTemplateRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ScheduleTemplateRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ScheduleTemplateRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleTemplateRecordsCompanion(
                id: id,
                userId: userId,
                name: name,
                timezone: timezone,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                Value<String> timezone = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleTemplateRecordsCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                timezone: timezone,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ScheduleTemplateRecordsTable,
                    ScheduleTemplateRecord
                  >(table),
                  $$ScheduleTemplateRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({scheduleTemplateSegmentRecordsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (scheduleTemplateSegmentRecordsRefs)
                      db.scheduleTemplateSegmentRecords,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (scheduleTemplateSegmentRecordsRefs)
                        await $_getPrefetchedData<
                          ScheduleTemplateRecord,
                          $ScheduleTemplateRecordsTable,
                          ScheduleTemplateSegmentRecord
                        >(
                          currentTable: table,
                          referencedTable:
                              $$ScheduleTemplateRecordsTableReferences
                                  ._scheduleTemplateSegmentRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScheduleTemplateRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleTemplateSegmentRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.templateId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ScheduleTemplateRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleTemplateRecordsTable,
      ScheduleTemplateRecord,
      $$ScheduleTemplateRecordsTableFilterComposer,
      $$ScheduleTemplateRecordsTableOrderingComposer,
      $$ScheduleTemplateRecordsTableAnnotationComposer,
      $$ScheduleTemplateRecordsTableCreateCompanionBuilder,
      $$ScheduleTemplateRecordsTableUpdateCompanionBuilder,
      (ScheduleTemplateRecord, $$ScheduleTemplateRecordsTableReferences),
      ScheduleTemplateRecord,
      PrefetchHooks Function({bool scheduleTemplateSegmentRecordsRefs})
    >;
typedef $$ScheduleTemplateSegmentRecordsTableCreateCompanionBuilder =
    ScheduleTemplateSegmentRecordsCompanion Function({
      required String id,
      required String templateId,
      required String userId,
      required String name,
      required int startsAtMinute,
      required int endsAtMinute,
      Value<String> segmentType,
      Value<int> sortOrder,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ScheduleTemplateSegmentRecordsTableUpdateCompanionBuilder =
    ScheduleTemplateSegmentRecordsCompanion Function({
      Value<String> id,
      Value<String> templateId,
      Value<String> userId,
      Value<String> name,
      Value<int> startsAtMinute,
      Value<int> endsAtMinute,
      Value<String> segmentType,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$ScheduleTemplateSegmentRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ScheduleTemplateSegmentRecordsTable,
          ScheduleTemplateSegmentRecord
        > {
  $$ScheduleTemplateSegmentRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ScheduleTemplateRecordsTable _templateIdTable(
    _$AppDatabase db,
  ) => db.scheduleTemplateRecords.createAlias(
    'schedule_template_segment_records__template_id__schedule_template_records__id',
  );

  $$ScheduleTemplateRecordsTableProcessedTableManager get templateId {
    final $_column = $_itemColumn<String>('template_id')!;

    final manager = $$ScheduleTemplateRecordsTableTableManager(
      $_db,
      $_db.scheduleTemplateRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_templateIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ScheduleTemplateSegmentRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleTemplateSegmentRecordsTable> {
  $$ScheduleTemplateSegmentRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMinute => $composableBuilder(
    column: $table.startsAtMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMinute => $composableBuilder(
    column: $table.endsAtMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get segmentType => $composableBuilder(
    column: $table.segmentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ScheduleTemplateRecordsTableFilterComposer get templateId {
    final $$ScheduleTemplateRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.templateId,
          referencedTable: $db.scheduleTemplateRecords,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplateRecordsTableFilterComposer(
                $db: $db,
                $table: $db.scheduleTemplateRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ScheduleTemplateSegmentRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleTemplateSegmentRecordsTable> {
  $$ScheduleTemplateSegmentRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMinute => $composableBuilder(
    column: $table.startsAtMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMinute => $composableBuilder(
    column: $table.endsAtMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get segmentType => $composableBuilder(
    column: $table.segmentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ScheduleTemplateRecordsTableOrderingComposer get templateId {
    final $$ScheduleTemplateRecordsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.templateId,
          referencedTable: $db.scheduleTemplateRecords,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplateRecordsTableOrderingComposer(
                $db: $db,
                $table: $db.scheduleTemplateRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ScheduleTemplateSegmentRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleTemplateSegmentRecordsTable> {
  $$ScheduleTemplateSegmentRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startsAtMinute => $composableBuilder(
    column: $table.startsAtMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMinute => $composableBuilder(
    column: $table.endsAtMinute,
    builder: (column) => column,
  );

  GeneratedColumn<String> get segmentType => $composableBuilder(
    column: $table.segmentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ScheduleTemplateRecordsTableAnnotationComposer get templateId {
    final $$ScheduleTemplateRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.templateId,
          referencedTable: $db.scheduleTemplateRecords,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleTemplateRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleTemplateRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ScheduleTemplateSegmentRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleTemplateSegmentRecordsTable,
          ScheduleTemplateSegmentRecord,
          $$ScheduleTemplateSegmentRecordsTableFilterComposer,
          $$ScheduleTemplateSegmentRecordsTableOrderingComposer,
          $$ScheduleTemplateSegmentRecordsTableAnnotationComposer,
          $$ScheduleTemplateSegmentRecordsTableCreateCompanionBuilder,
          $$ScheduleTemplateSegmentRecordsTableUpdateCompanionBuilder,
          (
            ScheduleTemplateSegmentRecord,
            $$ScheduleTemplateSegmentRecordsTableReferences,
          ),
          ScheduleTemplateSegmentRecord,
          PrefetchHooks Function({bool templateId})
        > {
  $$ScheduleTemplateSegmentRecordsTableTableManager(
    _$AppDatabase db,
    $ScheduleTemplateSegmentRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduleTemplateSegmentRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ScheduleTemplateSegmentRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ScheduleTemplateSegmentRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> templateId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> startsAtMinute = const Value.absent(),
                Value<int> endsAtMinute = const Value.absent(),
                Value<String> segmentType = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleTemplateSegmentRecordsCompanion(
                id: id,
                templateId: templateId,
                userId: userId,
                name: name,
                startsAtMinute: startsAtMinute,
                endsAtMinute: endsAtMinute,
                segmentType: segmentType,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String templateId,
                required String userId,
                required String name,
                required int startsAtMinute,
                required int endsAtMinute,
                Value<String> segmentType = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScheduleTemplateSegmentRecordsCompanion.insert(
                id: id,
                templateId: templateId,
                userId: userId,
                name: name,
                startsAtMinute: startsAtMinute,
                endsAtMinute: endsAtMinute,
                segmentType: segmentType,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ScheduleTemplateSegmentRecordsTable,
                    ScheduleTemplateSegmentRecord
                  >(table),
                  $$ScheduleTemplateSegmentRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({templateId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (templateId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.templateId,
                                referencedTable:
                                    $$ScheduleTemplateSegmentRecordsTableReferences
                                        ._templateIdTable(db),
                                referencedColumn:
                                    $$ScheduleTemplateSegmentRecordsTableReferences
                                        ._templateIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ScheduleTemplateSegmentRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleTemplateSegmentRecordsTable,
      ScheduleTemplateSegmentRecord,
      $$ScheduleTemplateSegmentRecordsTableFilterComposer,
      $$ScheduleTemplateSegmentRecordsTableOrderingComposer,
      $$ScheduleTemplateSegmentRecordsTableAnnotationComposer,
      $$ScheduleTemplateSegmentRecordsTableCreateCompanionBuilder,
      $$ScheduleTemplateSegmentRecordsTableUpdateCompanionBuilder,
      (
        ScheduleTemplateSegmentRecord,
        $$ScheduleTemplateSegmentRecordsTableReferences,
      ),
      ScheduleTemplateSegmentRecord,
      PrefetchHooks Function({bool templateId})
    >;
typedef $$SemesterRecordsTableCreateCompanionBuilder =
    SemesterRecordsCompanion Function({
      required String id,
      required String userId,
      required String name,
      required DateTime firstWeekStartDate,
      required int totalWeeks,
      Value<String?> scheduleTemplateId,
      Value<bool> isCurrent,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$SemesterRecordsTableUpdateCompanionBuilder =
    SemesterRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> name,
      Value<DateTime> firstWeekStartDate,
      Value<int> totalWeeks,
      Value<String?> scheduleTemplateId,
      Value<bool> isCurrent,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$SemesterRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $SemesterRecordsTable> {
  $$SemesterRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstWeekStartDate => $composableBuilder(
    column: $table.firstWeekStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalWeeks => $composableBuilder(
    column: $table.totalWeeks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleTemplateId => $composableBuilder(
    column: $table.scheduleTemplateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SemesterRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SemesterRecordsTable> {
  $$SemesterRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstWeekStartDate => $composableBuilder(
    column: $table.firstWeekStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalWeeks => $composableBuilder(
    column: $table.totalWeeks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleTemplateId => $composableBuilder(
    column: $table.scheduleTemplateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SemesterRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SemesterRecordsTable> {
  $$SemesterRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get firstWeekStartDate => $composableBuilder(
    column: $table.firstWeekStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalWeeks => $composableBuilder(
    column: $table.totalWeeks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scheduleTemplateId => $composableBuilder(
    column: $table.scheduleTemplateId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SemesterRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SemesterRecordsTable,
          SemesterRecord,
          $$SemesterRecordsTableFilterComposer,
          $$SemesterRecordsTableOrderingComposer,
          $$SemesterRecordsTableAnnotationComposer,
          $$SemesterRecordsTableCreateCompanionBuilder,
          $$SemesterRecordsTableUpdateCompanionBuilder,
          (
            SemesterRecord,
            BaseReferences<
              _$AppDatabase,
              $SemesterRecordsTable,
              SemesterRecord
            >,
          ),
          SemesterRecord,
          PrefetchHooks Function()
        > {
  $$SemesterRecordsTableTableManager(
    _$AppDatabase db,
    $SemesterRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SemesterRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SemesterRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SemesterRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> firstWeekStartDate = const Value.absent(),
                Value<int> totalWeeks = const Value.absent(),
                Value<String?> scheduleTemplateId = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SemesterRecordsCompanion(
                id: id,
                userId: userId,
                name: name,
                firstWeekStartDate: firstWeekStartDate,
                totalWeeks: totalWeeks,
                scheduleTemplateId: scheduleTemplateId,
                isCurrent: isCurrent,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String name,
                required DateTime firstWeekStartDate,
                required int totalWeeks,
                Value<String?> scheduleTemplateId = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SemesterRecordsCompanion.insert(
                id: id,
                userId: userId,
                name: name,
                firstWeekStartDate: firstWeekStartDate,
                totalWeeks: totalWeeks,
                scheduleTemplateId: scheduleTemplateId,
                isCurrent: isCurrent,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SemesterRecordsTable, SemesterRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SemesterRecordsTable,
                    SemesterRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SemesterRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SemesterRecordsTable,
      SemesterRecord,
      $$SemesterRecordsTableFilterComposer,
      $$SemesterRecordsTableOrderingComposer,
      $$SemesterRecordsTableAnnotationComposer,
      $$SemesterRecordsTableCreateCompanionBuilder,
      $$SemesterRecordsTableUpdateCompanionBuilder,
      (
        SemesterRecord,
        BaseReferences<_$AppDatabase, $SemesterRecordsTable, SemesterRecord>,
      ),
      SemesterRecord,
      PrefetchHooks Function()
    >;
typedef $$DailyItemOverrideRecordsTableCreateCompanionBuilder =
    DailyItemOverrideRecordsCompanion Function({
      required String id,
      required String userId,
      required String itemType,
      required String itemId,
      required String localDate,
      required String action,
      Value<int?> plannedStartMinute,
      Value<int?> plannedEndMinute,
      Value<int?> reminderMinuteOfDay,
      Value<int?> targetDurationSeconds,
      Value<String?> temporaryClassroom,
      Value<String?> notes,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$DailyItemOverrideRecordsTableUpdateCompanionBuilder =
    DailyItemOverrideRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> itemType,
      Value<String> itemId,
      Value<String> localDate,
      Value<String> action,
      Value<int?> plannedStartMinute,
      Value<int?> plannedEndMinute,
      Value<int?> reminderMinuteOfDay,
      Value<int?> targetDurationSeconds,
      Value<String?> temporaryClassroom,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$DailyItemOverrideRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyItemOverrideRecordsTable> {
  $$DailyItemOverrideRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedStartMinute => $composableBuilder(
    column: $table.plannedStartMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedEndMinute => $composableBuilder(
    column: $table.plannedEndMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderMinuteOfDay => $composableBuilder(
    column: $table.reminderMinuteOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetDurationSeconds => $composableBuilder(
    column: $table.targetDurationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get temporaryClassroom => $composableBuilder(
    column: $table.temporaryClassroom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyItemOverrideRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyItemOverrideRecordsTable> {
  $$DailyItemOverrideRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedStartMinute => $composableBuilder(
    column: $table.plannedStartMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedEndMinute => $composableBuilder(
    column: $table.plannedEndMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderMinuteOfDay => $composableBuilder(
    column: $table.reminderMinuteOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetDurationSeconds => $composableBuilder(
    column: $table.targetDurationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get temporaryClassroom => $composableBuilder(
    column: $table.temporaryClassroom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyItemOverrideRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyItemOverrideRecordsTable> {
  $$DailyItemOverrideRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get plannedStartMinute => $composableBuilder(
    column: $table.plannedStartMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedEndMinute => $composableBuilder(
    column: $table.plannedEndMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderMinuteOfDay => $composableBuilder(
    column: $table.reminderMinuteOfDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetDurationSeconds => $composableBuilder(
    column: $table.targetDurationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get temporaryClassroom => $composableBuilder(
    column: $table.temporaryClassroom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$DailyItemOverrideRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyItemOverrideRecordsTable,
          DailyItemOverrideRecord,
          $$DailyItemOverrideRecordsTableFilterComposer,
          $$DailyItemOverrideRecordsTableOrderingComposer,
          $$DailyItemOverrideRecordsTableAnnotationComposer,
          $$DailyItemOverrideRecordsTableCreateCompanionBuilder,
          $$DailyItemOverrideRecordsTableUpdateCompanionBuilder,
          (
            DailyItemOverrideRecord,
            BaseReferences<
              _$AppDatabase,
              $DailyItemOverrideRecordsTable,
              DailyItemOverrideRecord
            >,
          ),
          DailyItemOverrideRecord,
          PrefetchHooks Function()
        > {
  $$DailyItemOverrideRecordsTableTableManager(
    _$AppDatabase db,
    $DailyItemOverrideRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyItemOverrideRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DailyItemOverrideRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DailyItemOverrideRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> itemType = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<int?> plannedStartMinute = const Value.absent(),
                Value<int?> plannedEndMinute = const Value.absent(),
                Value<int?> reminderMinuteOfDay = const Value.absent(),
                Value<int?> targetDurationSeconds = const Value.absent(),
                Value<String?> temporaryClassroom = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyItemOverrideRecordsCompanion(
                id: id,
                userId: userId,
                itemType: itemType,
                itemId: itemId,
                localDate: localDate,
                action: action,
                plannedStartMinute: plannedStartMinute,
                plannedEndMinute: plannedEndMinute,
                reminderMinuteOfDay: reminderMinuteOfDay,
                targetDurationSeconds: targetDurationSeconds,
                temporaryClassroom: temporaryClassroom,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String itemType,
                required String itemId,
                required String localDate,
                required String action,
                Value<int?> plannedStartMinute = const Value.absent(),
                Value<int?> plannedEndMinute = const Value.absent(),
                Value<int?> reminderMinuteOfDay = const Value.absent(),
                Value<int?> targetDurationSeconds = const Value.absent(),
                Value<String?> temporaryClassroom = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyItemOverrideRecordsCompanion.insert(
                id: id,
                userId: userId,
                itemType: itemType,
                itemId: itemId,
                localDate: localDate,
                action: action,
                plannedStartMinute: plannedStartMinute,
                plannedEndMinute: plannedEndMinute,
                reminderMinuteOfDay: reminderMinuteOfDay,
                targetDurationSeconds: targetDurationSeconds,
                temporaryClassroom: temporaryClassroom,
                notes: notes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $DailyItemOverrideRecordsTable,
                    DailyItemOverrideRecord
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DailyItemOverrideRecordsTable,
                    DailyItemOverrideRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyItemOverrideRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyItemOverrideRecordsTable,
      DailyItemOverrideRecord,
      $$DailyItemOverrideRecordsTableFilterComposer,
      $$DailyItemOverrideRecordsTableOrderingComposer,
      $$DailyItemOverrideRecordsTableAnnotationComposer,
      $$DailyItemOverrideRecordsTableCreateCompanionBuilder,
      $$DailyItemOverrideRecordsTableUpdateCompanionBuilder,
      (
        DailyItemOverrideRecord,
        BaseReferences<
          _$AppDatabase,
          $DailyItemOverrideRecordsTable,
          DailyItemOverrideRecord
        >,
      ),
      DailyItemOverrideRecord,
      PrefetchHooks Function()
    >;
typedef $$ReminderRuleRecordsTableCreateCompanionBuilder =
    ReminderRuleRecordsCompanion Function({
      required String id,
      required String userId,
      required String ownerType,
      required String ownerId,
      required String reminderKind,
      Value<bool> enabled,
      Value<int?> scheduledMinuteOfDay,
      Value<int?> remindBeforeMinutes,
      Value<String?> localDate,
      Value<String> timezone,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$ReminderRuleRecordsTableUpdateCompanionBuilder =
    ReminderRuleRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> ownerType,
      Value<String> ownerId,
      Value<String> reminderKind,
      Value<bool> enabled,
      Value<int?> scheduledMinuteOfDay,
      Value<int?> remindBeforeMinutes,
      Value<String?> localDate,
      Value<String> timezone,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$ReminderRuleRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ReminderRuleRecordsTable> {
  $$ReminderRuleRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reminderKind => $composableBuilder(
    column: $table.reminderKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scheduledMinuteOfDay => $composableBuilder(
    column: $table.scheduledMinuteOfDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReminderRuleRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReminderRuleRecordsTable> {
  $$ReminderRuleRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminderKind => $composableBuilder(
    column: $table.reminderKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scheduledMinuteOfDay => $composableBuilder(
    column: $table.scheduledMinuteOfDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReminderRuleRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReminderRuleRecordsTable> {
  $$ReminderRuleRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get reminderKind => $composableBuilder(
    column: $table.reminderKind,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get scheduledMinuteOfDay => $composableBuilder(
    column: $table.scheduledMinuteOfDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remindBeforeMinutes => $composableBuilder(
    column: $table.remindBeforeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ReminderRuleRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReminderRuleRecordsTable,
          ReminderRuleRecord,
          $$ReminderRuleRecordsTableFilterComposer,
          $$ReminderRuleRecordsTableOrderingComposer,
          $$ReminderRuleRecordsTableAnnotationComposer,
          $$ReminderRuleRecordsTableCreateCompanionBuilder,
          $$ReminderRuleRecordsTableUpdateCompanionBuilder,
          (
            ReminderRuleRecord,
            BaseReferences<
              _$AppDatabase,
              $ReminderRuleRecordsTable,
              ReminderRuleRecord
            >,
          ),
          ReminderRuleRecord,
          PrefetchHooks Function()
        > {
  $$ReminderRuleRecordsTableTableManager(
    _$AppDatabase db,
    $ReminderRuleRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReminderRuleRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReminderRuleRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReminderRuleRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> ownerType = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> reminderKind = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int?> scheduledMinuteOfDay = const Value.absent(),
                Value<int?> remindBeforeMinutes = const Value.absent(),
                Value<String?> localDate = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReminderRuleRecordsCompanion(
                id: id,
                userId: userId,
                ownerType: ownerType,
                ownerId: ownerId,
                reminderKind: reminderKind,
                enabled: enabled,
                scheduledMinuteOfDay: scheduledMinuteOfDay,
                remindBeforeMinutes: remindBeforeMinutes,
                localDate: localDate,
                timezone: timezone,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String ownerType,
                required String ownerId,
                required String reminderKind,
                Value<bool> enabled = const Value.absent(),
                Value<int?> scheduledMinuteOfDay = const Value.absent(),
                Value<int?> remindBeforeMinutes = const Value.absent(),
                Value<String?> localDate = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReminderRuleRecordsCompanion.insert(
                id: id,
                userId: userId,
                ownerType: ownerType,
                ownerId: ownerId,
                reminderKind: reminderKind,
                enabled: enabled,
                scheduledMinuteOfDay: scheduledMinuteOfDay,
                remindBeforeMinutes: remindBeforeMinutes,
                localDate: localDate,
                timezone: timezone,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReminderRuleRecordsTable, ReminderRuleRecord>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ReminderRuleRecordsTable,
                    ReminderRuleRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReminderRuleRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReminderRuleRecordsTable,
      ReminderRuleRecord,
      $$ReminderRuleRecordsTableFilterComposer,
      $$ReminderRuleRecordsTableOrderingComposer,
      $$ReminderRuleRecordsTableAnnotationComposer,
      $$ReminderRuleRecordsTableCreateCompanionBuilder,
      $$ReminderRuleRecordsTableUpdateCompanionBuilder,
      (
        ReminderRuleRecord,
        BaseReferences<
          _$AppDatabase,
          $ReminderRuleRecordsTable,
          ReminderRuleRecord
        >,
      ),
      ReminderRuleRecord,
      PrefetchHooks Function()
    >;
typedef $$AlarmRuleRecordsTableCreateCompanionBuilder =
    AlarmRuleRecordsCompanion Function({
      required String id,
      required String userId,
      required String ownerType,
      required String ownerId,
      Value<bool> enabled,
      Value<String> behavior,
      Value<String?> soundName,
      Value<int?> snoozeMinutes,
      Value<int?> repeatIntervalMinutes,
      Value<int?> maxRingSeconds,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$AlarmRuleRecordsTableUpdateCompanionBuilder =
    AlarmRuleRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> ownerType,
      Value<String> ownerId,
      Value<bool> enabled,
      Value<String> behavior,
      Value<String?> soundName,
      Value<int?> snoozeMinutes,
      Value<int?> repeatIntervalMinutes,
      Value<int?> maxRingSeconds,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$AlarmRuleRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $AlarmRuleRecordsTable> {
  $$AlarmRuleRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get behavior => $composableBuilder(
    column: $table.behavior,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get soundName => $composableBuilder(
    column: $table.soundName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snoozeMinutes => $composableBuilder(
    column: $table.snoozeMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeatIntervalMinutes => $composableBuilder(
    column: $table.repeatIntervalMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxRingSeconds => $composableBuilder(
    column: $table.maxRingSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlarmRuleRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlarmRuleRecordsTable> {
  $$AlarmRuleRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get behavior => $composableBuilder(
    column: $table.behavior,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get soundName => $composableBuilder(
    column: $table.soundName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snoozeMinutes => $composableBuilder(
    column: $table.snoozeMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeatIntervalMinutes => $composableBuilder(
    column: $table.repeatIntervalMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxRingSeconds => $composableBuilder(
    column: $table.maxRingSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlarmRuleRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlarmRuleRecordsTable> {
  $$AlarmRuleRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get behavior =>
      $composableBuilder(column: $table.behavior, builder: (column) => column);

  GeneratedColumn<String> get soundName =>
      $composableBuilder(column: $table.soundName, builder: (column) => column);

  GeneratedColumn<int> get snoozeMinutes => $composableBuilder(
    column: $table.snoozeMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repeatIntervalMinutes => $composableBuilder(
    column: $table.repeatIntervalMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxRingSeconds => $composableBuilder(
    column: $table.maxRingSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$AlarmRuleRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlarmRuleRecordsTable,
          AlarmRuleRecord,
          $$AlarmRuleRecordsTableFilterComposer,
          $$AlarmRuleRecordsTableOrderingComposer,
          $$AlarmRuleRecordsTableAnnotationComposer,
          $$AlarmRuleRecordsTableCreateCompanionBuilder,
          $$AlarmRuleRecordsTableUpdateCompanionBuilder,
          (
            AlarmRuleRecord,
            BaseReferences<
              _$AppDatabase,
              $AlarmRuleRecordsTable,
              AlarmRuleRecord
            >,
          ),
          AlarmRuleRecord,
          PrefetchHooks Function()
        > {
  $$AlarmRuleRecordsTableTableManager(
    _$AppDatabase db,
    $AlarmRuleRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmRuleRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmRuleRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmRuleRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> ownerType = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> behavior = const Value.absent(),
                Value<String?> soundName = const Value.absent(),
                Value<int?> snoozeMinutes = const Value.absent(),
                Value<int?> repeatIntervalMinutes = const Value.absent(),
                Value<int?> maxRingSeconds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlarmRuleRecordsCompanion(
                id: id,
                userId: userId,
                ownerType: ownerType,
                ownerId: ownerId,
                enabled: enabled,
                behavior: behavior,
                soundName: soundName,
                snoozeMinutes: snoozeMinutes,
                repeatIntervalMinutes: repeatIntervalMinutes,
                maxRingSeconds: maxRingSeconds,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String ownerType,
                required String ownerId,
                Value<bool> enabled = const Value.absent(),
                Value<String> behavior = const Value.absent(),
                Value<String?> soundName = const Value.absent(),
                Value<int?> snoozeMinutes = const Value.absent(),
                Value<int?> repeatIntervalMinutes = const Value.absent(),
                Value<int?> maxRingSeconds = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlarmRuleRecordsCompanion.insert(
                id: id,
                userId: userId,
                ownerType: ownerType,
                ownerId: ownerId,
                enabled: enabled,
                behavior: behavior,
                soundName: soundName,
                snoozeMinutes: snoozeMinutes,
                repeatIntervalMinutes: repeatIntervalMinutes,
                maxRingSeconds: maxRingSeconds,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AlarmRuleRecordsTable, AlarmRuleRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AlarmRuleRecordsTable,
                    AlarmRuleRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlarmRuleRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlarmRuleRecordsTable,
      AlarmRuleRecord,
      $$AlarmRuleRecordsTableFilterComposer,
      $$AlarmRuleRecordsTableOrderingComposer,
      $$AlarmRuleRecordsTableAnnotationComposer,
      $$AlarmRuleRecordsTableCreateCompanionBuilder,
      $$AlarmRuleRecordsTableUpdateCompanionBuilder,
      (
        AlarmRuleRecord,
        BaseReferences<_$AppDatabase, $AlarmRuleRecordsTable, AlarmRuleRecord>,
      ),
      AlarmRuleRecord,
      PrefetchHooks Function()
    >;
typedef $$AdHocTimerRecordsTableCreateCompanionBuilder =
    AdHocTimerRecordsCompanion Function({
      required String id,
      required String userId,
      required String title,
      Value<String?> tagId,
      required int colorValue,
      Value<String?> notes,
      required DateTime startedAt,
      Value<String> timerStatus,
      Value<int> accumulatedDurationSeconds,
      Value<DateTime?> currentStartedAt,
      Value<DateTime?> endedAt,
      Value<DateTime?> completedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$AdHocTimerRecordsTableUpdateCompanionBuilder =
    AdHocTimerRecordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> title,
      Value<String?> tagId,
      Value<int> colorValue,
      Value<String?> notes,
      Value<DateTime> startedAt,
      Value<String> timerStatus,
      Value<int> accumulatedDurationSeconds,
      Value<DateTime?> currentStartedAt,
      Value<DateTime?> endedAt,
      Value<DateTime?> completedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$AdHocTimerRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $AdHocTimerRecordsTable> {
  $$AdHocTimerRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timerStatus => $composableBuilder(
    column: $table.timerStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accumulatedDurationSeconds => $composableBuilder(
    column: $table.accumulatedDurationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get currentStartedAt => $composableBuilder(
    column: $table.currentStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AdHocTimerRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $AdHocTimerRecordsTable> {
  $$AdHocTimerRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timerStatus => $composableBuilder(
    column: $table.timerStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accumulatedDurationSeconds => $composableBuilder(
    column: $table.accumulatedDurationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get currentStartedAt => $composableBuilder(
    column: $table.currentStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AdHocTimerRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AdHocTimerRecordsTable> {
  $$AdHocTimerRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get timerStatus => $composableBuilder(
    column: $table.timerStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accumulatedDurationSeconds => $composableBuilder(
    column: $table.accumulatedDurationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get currentStartedAt => $composableBuilder(
    column: $table.currentStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$AdHocTimerRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AdHocTimerRecordsTable,
          AdHocTimerRecord,
          $$AdHocTimerRecordsTableFilterComposer,
          $$AdHocTimerRecordsTableOrderingComposer,
          $$AdHocTimerRecordsTableAnnotationComposer,
          $$AdHocTimerRecordsTableCreateCompanionBuilder,
          $$AdHocTimerRecordsTableUpdateCompanionBuilder,
          (
            AdHocTimerRecord,
            BaseReferences<
              _$AppDatabase,
              $AdHocTimerRecordsTable,
              AdHocTimerRecord
            >,
          ),
          AdHocTimerRecord,
          PrefetchHooks Function()
        > {
  $$AdHocTimerRecordsTableTableManager(
    _$AppDatabase db,
    $AdHocTimerRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AdHocTimerRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AdHocTimerRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AdHocTimerRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> tagId = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<String> timerStatus = const Value.absent(),
                Value<int> accumulatedDurationSeconds = const Value.absent(),
                Value<DateTime?> currentStartedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AdHocTimerRecordsCompanion(
                id: id,
                userId: userId,
                title: title,
                tagId: tagId,
                colorValue: colorValue,
                notes: notes,
                startedAt: startedAt,
                timerStatus: timerStatus,
                accumulatedDurationSeconds: accumulatedDurationSeconds,
                currentStartedAt: currentStartedAt,
                endedAt: endedAt,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String title,
                Value<String?> tagId = const Value.absent(),
                required int colorValue,
                Value<String?> notes = const Value.absent(),
                required DateTime startedAt,
                Value<String> timerStatus = const Value.absent(),
                Value<int> accumulatedDurationSeconds = const Value.absent(),
                Value<DateTime?> currentStartedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AdHocTimerRecordsCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                tagId: tagId,
                colorValue: colorValue,
                notes: notes,
                startedAt: startedAt,
                timerStatus: timerStatus,
                accumulatedDurationSeconds: accumulatedDurationSeconds,
                currentStartedAt: currentStartedAt,
                endedAt: endedAt,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AdHocTimerRecordsTable, AdHocTimerRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AdHocTimerRecordsTable,
                    AdHocTimerRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AdHocTimerRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AdHocTimerRecordsTable,
      AdHocTimerRecord,
      $$AdHocTimerRecordsTableFilterComposer,
      $$AdHocTimerRecordsTableOrderingComposer,
      $$AdHocTimerRecordsTableAnnotationComposer,
      $$AdHocTimerRecordsTableCreateCompanionBuilder,
      $$AdHocTimerRecordsTableUpdateCompanionBuilder,
      (
        AdHocTimerRecord,
        BaseReferences<
          _$AppDatabase,
          $AdHocTimerRecordsTable,
          AdHocTimerRecord
        >,
      ),
      AdHocTimerRecord,
      PrefetchHooks Function()
    >;
typedef $$AdHocTimerIntervalRecordsTableCreateCompanionBuilder =
    AdHocTimerIntervalRecordsCompanion Function({
      required String id,
      required String timerId,
      required String userId,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int> durationSeconds,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$AdHocTimerIntervalRecordsTableUpdateCompanionBuilder =
    AdHocTimerIntervalRecordsCompanion Function({
      Value<String> id,
      Value<String> timerId,
      Value<String> userId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> durationSeconds,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$AdHocTimerIntervalRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $AdHocTimerIntervalRecordsTable> {
  $$AdHocTimerIntervalRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timerId => $composableBuilder(
    column: $table.timerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AdHocTimerIntervalRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $AdHocTimerIntervalRecordsTable> {
  $$AdHocTimerIntervalRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timerId => $composableBuilder(
    column: $table.timerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AdHocTimerIntervalRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AdHocTimerIntervalRecordsTable> {
  $$AdHocTimerIntervalRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get timerId =>
      $composableBuilder(column: $table.timerId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AdHocTimerIntervalRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AdHocTimerIntervalRecordsTable,
          AdHocTimerIntervalRecord,
          $$AdHocTimerIntervalRecordsTableFilterComposer,
          $$AdHocTimerIntervalRecordsTableOrderingComposer,
          $$AdHocTimerIntervalRecordsTableAnnotationComposer,
          $$AdHocTimerIntervalRecordsTableCreateCompanionBuilder,
          $$AdHocTimerIntervalRecordsTableUpdateCompanionBuilder,
          (
            AdHocTimerIntervalRecord,
            BaseReferences<
              _$AppDatabase,
              $AdHocTimerIntervalRecordsTable,
              AdHocTimerIntervalRecord
            >,
          ),
          AdHocTimerIntervalRecord,
          PrefetchHooks Function()
        > {
  $$AdHocTimerIntervalRecordsTableTableManager(
    _$AppDatabase db,
    $AdHocTimerIntervalRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AdHocTimerIntervalRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AdHocTimerIntervalRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AdHocTimerIntervalRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> timerId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AdHocTimerIntervalRecordsCompanion(
                id: id,
                timerId: timerId,
                userId: userId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String timerId,
                required String userId,
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => AdHocTimerIntervalRecordsCompanion.insert(
                id: id,
                timerId: timerId,
                userId: userId,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $AdHocTimerIntervalRecordsTable,
                    AdHocTimerIntervalRecord
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AdHocTimerIntervalRecordsTable,
                    AdHocTimerIntervalRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AdHocTimerIntervalRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AdHocTimerIntervalRecordsTable,
      AdHocTimerIntervalRecord,
      $$AdHocTimerIntervalRecordsTableFilterComposer,
      $$AdHocTimerIntervalRecordsTableOrderingComposer,
      $$AdHocTimerIntervalRecordsTableAnnotationComposer,
      $$AdHocTimerIntervalRecordsTableCreateCompanionBuilder,
      $$AdHocTimerIntervalRecordsTableUpdateCompanionBuilder,
      (
        AdHocTimerIntervalRecord,
        BaseReferences<
          _$AppDatabase,
          $AdHocTimerIntervalRecordsTable,
          AdHocTimerIntervalRecord
        >,
      ),
      AdHocTimerIntervalRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalTasksTableTableManager get localTasks =>
      $$LocalTasksTableTableManager(_db, _db.localTasks);
  $$LongTermTaskRecordsTableTableManager get longTermTaskRecords =>
      $$LongTermTaskRecordsTableTableManager(_db, _db.longTermTaskRecords);
  $$TaskScheduleRecordsTableTableManager get taskScheduleRecords =>
      $$TaskScheduleRecordsTableTableManager(_db, _db.taskScheduleRecords);
  $$OneTimeReminderRecordsTableTableManager get oneTimeReminderRecords =>
      $$OneTimeReminderRecordsTableTableManager(
        _db,
        _db.oneTimeReminderRecords,
      );
  $$TaskCompletionRecordsTableTableManager get taskCompletionRecords =>
      $$TaskCompletionRecordsTableTableManager(_db, _db.taskCompletionRecords);
  $$TimerSessionRecordsTableTableManager get timerSessionRecords =>
      $$TimerSessionRecordsTableTableManager(_db, _db.timerSessionRecords);
  $$TaskRevisionRecordsTableTableManager get taskRevisionRecords =>
      $$TaskRevisionRecordsTableTableManager(_db, _db.taskRevisionRecords);
  $$SyncOperationsTableTableManager get syncOperations =>
      $$SyncOperationsTableTableManager(_db, _db.syncOperations);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$TagRecordsTableTableManager get tagRecords =>
      $$TagRecordsTableTableManager(_db, _db.tagRecords);
  $$TagRevisionRecordsTableTableManager get tagRevisionRecords =>
      $$TagRevisionRecordsTableTableManager(_db, _db.tagRevisionRecords);
  $$PlanRecordsTableTableManager get planRecords =>
      $$PlanRecordsTableTableManager(_db, _db.planRecords);
  $$PlanTaskRecordsTableTableManager get planTaskRecords =>
      $$PlanTaskRecordsTableTableManager(_db, _db.planTaskRecords);
  $$ReviewRecordsTableTableManager get reviewRecords =>
      $$ReviewRecordsTableTableManager(_db, _db.reviewRecords);
  $$CourseRecordsTableTableManager get courseRecords =>
      $$CourseRecordsTableTableManager(_db, _db.courseRecords);
  $$CourseScheduleRuleRecordsTableTableManager get courseScheduleRuleRecords =>
      $$CourseScheduleRuleRecordsTableTableManager(
        _db,
        _db.courseScheduleRuleRecords,
      );
  $$ScheduleTemplateRecordsTableTableManager get scheduleTemplateRecords =>
      $$ScheduleTemplateRecordsTableTableManager(
        _db,
        _db.scheduleTemplateRecords,
      );
  $$ScheduleTemplateSegmentRecordsTableTableManager
  get scheduleTemplateSegmentRecords =>
      $$ScheduleTemplateSegmentRecordsTableTableManager(
        _db,
        _db.scheduleTemplateSegmentRecords,
      );
  $$SemesterRecordsTableTableManager get semesterRecords =>
      $$SemesterRecordsTableTableManager(_db, _db.semesterRecords);
  $$DailyItemOverrideRecordsTableTableManager get dailyItemOverrideRecords =>
      $$DailyItemOverrideRecordsTableTableManager(
        _db,
        _db.dailyItemOverrideRecords,
      );
  $$ReminderRuleRecordsTableTableManager get reminderRuleRecords =>
      $$ReminderRuleRecordsTableTableManager(_db, _db.reminderRuleRecords);
  $$AlarmRuleRecordsTableTableManager get alarmRuleRecords =>
      $$AlarmRuleRecordsTableTableManager(_db, _db.alarmRuleRecords);
  $$AdHocTimerRecordsTableTableManager get adHocTimerRecords =>
      $$AdHocTimerRecordsTableTableManager(_db, _db.adHocTimerRecords);
  $$AdHocTimerIntervalRecordsTableTableManager get adHocTimerIntervalRecords =>
      $$AdHocTimerIntervalRecordsTableTableManager(
        _db,
        _db.adHocTimerIntervalRecords,
      );
}
