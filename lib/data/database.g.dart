// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PersonsTable extends Persons with TableInfo<$PersonsTable, Person> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _givenNamesMeta = const VerificationMeta(
    'givenNames',
  );
  @override
  late final GeneratedColumn<String> givenNames = GeneratedColumn<String>(
    'given_names',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _surnameMeta = const VerificationMeta(
    'surname',
  );
  @override
  late final GeneratedColumn<String> surname = GeneratedColumn<String>(
    'surname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthSurnameMeta = const VerificationMeta(
    'birthSurname',
  );
  @override
  late final GeneratedColumn<String> birthSurname = GeneratedColumn<String>(
    'birth_surname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bioMeta = const VerificationMeta('bio');
  @override
  late final GeneratedColumn<String> bio = GeneratedColumn<String>(
    'bio',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bioSourceMeta = const VerificationMeta(
    'bioSource',
  );
  @override
  late final GeneratedColumn<String> bioSource = GeneratedColumn<String>(
    'bio_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isLivingMeta = const VerificationMeta(
    'isLiving',
  );
  @override
  late final GeneratedColumn<bool> isLiving = GeneratedColumn<bool>(
    'is_living',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_living" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    givenNames,
    surname,
    birthSurname,
    bio,
    bioSource,
    isLiving,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'persons';
  @override
  VerificationContext validateIntegrity(
    Insertable<Person> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('given_names')) {
      context.handle(
        _givenNamesMeta,
        givenNames.isAcceptableOrUnknown(data['given_names']!, _givenNamesMeta),
      );
    }
    if (data.containsKey('surname')) {
      context.handle(
        _surnameMeta,
        surname.isAcceptableOrUnknown(data['surname']!, _surnameMeta),
      );
    }
    if (data.containsKey('birth_surname')) {
      context.handle(
        _birthSurnameMeta,
        birthSurname.isAcceptableOrUnknown(
          data['birth_surname']!,
          _birthSurnameMeta,
        ),
      );
    }
    if (data.containsKey('bio')) {
      context.handle(
        _bioMeta,
        bio.isAcceptableOrUnknown(data['bio']!, _bioMeta),
      );
    }
    if (data.containsKey('bio_source')) {
      context.handle(
        _bioSourceMeta,
        bioSource.isAcceptableOrUnknown(data['bio_source']!, _bioSourceMeta),
      );
    }
    if (data.containsKey('is_living')) {
      context.handle(
        _isLivingMeta,
        isLiving.isAcceptableOrUnknown(data['is_living']!, _isLivingMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Person map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Person(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      givenNames: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}given_names'],
      ),
      surname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}surname'],
      ),
      birthSurname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}birth_surname'],
      ),
      bio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bio'],
      ),
      bioSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bio_source'],
      ),
      isLiving: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_living'],
      )!,
    );
  }

  @override
  $PersonsTable createAlias(String alias) {
    return $PersonsTable(attachedDatabase, alias);
  }
}

class Person extends DataClass implements Insertable<Person> {
  final int id;
  final String? givenNames;
  final String? surname;

  /// FR-005: surname at birth, next to the married one.
  final String? birthSurname;

  /// "Kim była" — free text with one source line for the whole text (FR-001 cost decision).
  final String? bio;
  final String? bioSource;
  final bool isLiving;
  const Person({
    required this.id,
    this.givenNames,
    this.surname,
    this.birthSurname,
    this.bio,
    this.bioSource,
    required this.isLiving,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || givenNames != null) {
      map['given_names'] = Variable<String>(givenNames);
    }
    if (!nullToAbsent || surname != null) {
      map['surname'] = Variable<String>(surname);
    }
    if (!nullToAbsent || birthSurname != null) {
      map['birth_surname'] = Variable<String>(birthSurname);
    }
    if (!nullToAbsent || bio != null) {
      map['bio'] = Variable<String>(bio);
    }
    if (!nullToAbsent || bioSource != null) {
      map['bio_source'] = Variable<String>(bioSource);
    }
    map['is_living'] = Variable<bool>(isLiving);
    return map;
  }

  PersonsCompanion toCompanion(bool nullToAbsent) {
    return PersonsCompanion(
      id: Value(id),
      givenNames: givenNames == null && nullToAbsent
          ? const Value.absent()
          : Value(givenNames),
      surname: surname == null && nullToAbsent
          ? const Value.absent()
          : Value(surname),
      birthSurname: birthSurname == null && nullToAbsent
          ? const Value.absent()
          : Value(birthSurname),
      bio: bio == null && nullToAbsent ? const Value.absent() : Value(bio),
      bioSource: bioSource == null && nullToAbsent
          ? const Value.absent()
          : Value(bioSource),
      isLiving: Value(isLiving),
    );
  }

  factory Person.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Person(
      id: serializer.fromJson<int>(json['id']),
      givenNames: serializer.fromJson<String?>(json['givenNames']),
      surname: serializer.fromJson<String?>(json['surname']),
      birthSurname: serializer.fromJson<String?>(json['birthSurname']),
      bio: serializer.fromJson<String?>(json['bio']),
      bioSource: serializer.fromJson<String?>(json['bioSource']),
      isLiving: serializer.fromJson<bool>(json['isLiving']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'givenNames': serializer.toJson<String?>(givenNames),
      'surname': serializer.toJson<String?>(surname),
      'birthSurname': serializer.toJson<String?>(birthSurname),
      'bio': serializer.toJson<String?>(bio),
      'bioSource': serializer.toJson<String?>(bioSource),
      'isLiving': serializer.toJson<bool>(isLiving),
    };
  }

  Person copyWith({
    int? id,
    Value<String?> givenNames = const Value.absent(),
    Value<String?> surname = const Value.absent(),
    Value<String?> birthSurname = const Value.absent(),
    Value<String?> bio = const Value.absent(),
    Value<String?> bioSource = const Value.absent(),
    bool? isLiving,
  }) => Person(
    id: id ?? this.id,
    givenNames: givenNames.present ? givenNames.value : this.givenNames,
    surname: surname.present ? surname.value : this.surname,
    birthSurname: birthSurname.present ? birthSurname.value : this.birthSurname,
    bio: bio.present ? bio.value : this.bio,
    bioSource: bioSource.present ? bioSource.value : this.bioSource,
    isLiving: isLiving ?? this.isLiving,
  );
  Person copyWithCompanion(PersonsCompanion data) {
    return Person(
      id: data.id.present ? data.id.value : this.id,
      givenNames: data.givenNames.present
          ? data.givenNames.value
          : this.givenNames,
      surname: data.surname.present ? data.surname.value : this.surname,
      birthSurname: data.birthSurname.present
          ? data.birthSurname.value
          : this.birthSurname,
      bio: data.bio.present ? data.bio.value : this.bio,
      bioSource: data.bioSource.present ? data.bioSource.value : this.bioSource,
      isLiving: data.isLiving.present ? data.isLiving.value : this.isLiving,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Person(')
          ..write('id: $id, ')
          ..write('givenNames: $givenNames, ')
          ..write('surname: $surname, ')
          ..write('birthSurname: $birthSurname, ')
          ..write('bio: $bio, ')
          ..write('bioSource: $bioSource, ')
          ..write('isLiving: $isLiving')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    givenNames,
    surname,
    birthSurname,
    bio,
    bioSource,
    isLiving,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Person &&
          other.id == this.id &&
          other.givenNames == this.givenNames &&
          other.surname == this.surname &&
          other.birthSurname == this.birthSurname &&
          other.bio == this.bio &&
          other.bioSource == this.bioSource &&
          other.isLiving == this.isLiving);
}

class PersonsCompanion extends UpdateCompanion<Person> {
  final Value<int> id;
  final Value<String?> givenNames;
  final Value<String?> surname;
  final Value<String?> birthSurname;
  final Value<String?> bio;
  final Value<String?> bioSource;
  final Value<bool> isLiving;
  const PersonsCompanion({
    this.id = const Value.absent(),
    this.givenNames = const Value.absent(),
    this.surname = const Value.absent(),
    this.birthSurname = const Value.absent(),
    this.bio = const Value.absent(),
    this.bioSource = const Value.absent(),
    this.isLiving = const Value.absent(),
  });
  PersonsCompanion.insert({
    this.id = const Value.absent(),
    this.givenNames = const Value.absent(),
    this.surname = const Value.absent(),
    this.birthSurname = const Value.absent(),
    this.bio = const Value.absent(),
    this.bioSource = const Value.absent(),
    this.isLiving = const Value.absent(),
  });
  static Insertable<Person> custom({
    Expression<int>? id,
    Expression<String>? givenNames,
    Expression<String>? surname,
    Expression<String>? birthSurname,
    Expression<String>? bio,
    Expression<String>? bioSource,
    Expression<bool>? isLiving,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (givenNames != null) 'given_names': givenNames,
      if (surname != null) 'surname': surname,
      if (birthSurname != null) 'birth_surname': birthSurname,
      if (bio != null) 'bio': bio,
      if (bioSource != null) 'bio_source': bioSource,
      if (isLiving != null) 'is_living': isLiving,
    });
  }

  PersonsCompanion copyWith({
    Value<int>? id,
    Value<String?>? givenNames,
    Value<String?>? surname,
    Value<String?>? birthSurname,
    Value<String?>? bio,
    Value<String?>? bioSource,
    Value<bool>? isLiving,
  }) {
    return PersonsCompanion(
      id: id ?? this.id,
      givenNames: givenNames ?? this.givenNames,
      surname: surname ?? this.surname,
      birthSurname: birthSurname ?? this.birthSurname,
      bio: bio ?? this.bio,
      bioSource: bioSource ?? this.bioSource,
      isLiving: isLiving ?? this.isLiving,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (givenNames.present) {
      map['given_names'] = Variable<String>(givenNames.value);
    }
    if (surname.present) {
      map['surname'] = Variable<String>(surname.value);
    }
    if (birthSurname.present) {
      map['birth_surname'] = Variable<String>(birthSurname.value);
    }
    if (bio.present) {
      map['bio'] = Variable<String>(bio.value);
    }
    if (bioSource.present) {
      map['bio_source'] = Variable<String>(bioSource.value);
    }
    if (isLiving.present) {
      map['is_living'] = Variable<bool>(isLiving.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonsCompanion(')
          ..write('id: $id, ')
          ..write('givenNames: $givenNames, ')
          ..write('surname: $surname, ')
          ..write('birthSurname: $birthSurname, ')
          ..write('bio: $bio, ')
          ..write('bioSource: $bioSource, ')
          ..write('isLiving: $isLiving')
          ..write(')'))
        .toString();
  }
}

class $FamiliesTable extends Families with TableInfo<$FamiliesTable, Family> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FamiliesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'families';
  @override
  VerificationContext validateIntegrity(
    Insertable<Family> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Family map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Family(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
    );
  }

  @override
  $FamiliesTable createAlias(String alias) {
    return $FamiliesTable(attachedDatabase, alias);
  }
}

class Family extends DataClass implements Insertable<Family> {
  final int id;
  const Family({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  FamiliesCompanion toCompanion(bool nullToAbsent) {
    return FamiliesCompanion(id: Value(id));
  }

  factory Family.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Family(id: serializer.fromJson<int>(json['id']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'id': serializer.toJson<int>(id)};
  }

  Family copyWith({int? id}) => Family(id: id ?? this.id);
  Family copyWithCompanion(FamiliesCompanion data) {
    return Family(id: data.id.present ? data.id.value : this.id);
  }

  @override
  String toString() {
    return (StringBuffer('Family(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Family && other.id == this.id);
}

class FamiliesCompanion extends UpdateCompanion<Family> {
  final Value<int> id;
  const FamiliesCompanion({this.id = const Value.absent()});
  FamiliesCompanion.insert({this.id = const Value.absent()});
  static Insertable<Family> custom({Expression<int>? id}) {
    return RawValuesInsertable({if (id != null) 'id': id});
  }

  FamiliesCompanion copyWith({Value<int>? id}) {
    return FamiliesCompanion(id: id ?? this.id);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FamiliesCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

class $FamilyPartnersTable extends FamilyPartners
    with TableInfo<$FamilyPartnersTable, FamilyPartner> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FamilyPartnersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _familyIdMeta = const VerificationMeta(
    'familyId',
  );
  @override
  late final GeneratedColumn<int> familyId = GeneratedColumn<int>(
    'family_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES families (id)',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [familyId, personId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'family_partners';
  @override
  VerificationContext validateIntegrity(
    Insertable<FamilyPartner> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('family_id')) {
      context.handle(
        _familyIdMeta,
        familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_familyIdMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {familyId, personId};
  @override
  FamilyPartner map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FamilyPartner(
      familyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}family_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
    );
  }

  @override
  $FamilyPartnersTable createAlias(String alias) {
    return $FamilyPartnersTable(attachedDatabase, alias);
  }
}

class FamilyPartner extends DataClass implements Insertable<FamilyPartner> {
  final int familyId;
  final int personId;
  const FamilyPartner({required this.familyId, required this.personId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['family_id'] = Variable<int>(familyId);
    map['person_id'] = Variable<int>(personId);
    return map;
  }

  FamilyPartnersCompanion toCompanion(bool nullToAbsent) {
    return FamilyPartnersCompanion(
      familyId: Value(familyId),
      personId: Value(personId),
    );
  }

  factory FamilyPartner.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FamilyPartner(
      familyId: serializer.fromJson<int>(json['familyId']),
      personId: serializer.fromJson<int>(json['personId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'familyId': serializer.toJson<int>(familyId),
      'personId': serializer.toJson<int>(personId),
    };
  }

  FamilyPartner copyWith({int? familyId, int? personId}) => FamilyPartner(
    familyId: familyId ?? this.familyId,
    personId: personId ?? this.personId,
  );
  FamilyPartner copyWithCompanion(FamilyPartnersCompanion data) {
    return FamilyPartner(
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      personId: data.personId.present ? data.personId.value : this.personId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FamilyPartner(')
          ..write('familyId: $familyId, ')
          ..write('personId: $personId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(familyId, personId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FamilyPartner &&
          other.familyId == this.familyId &&
          other.personId == this.personId);
}

class FamilyPartnersCompanion extends UpdateCompanion<FamilyPartner> {
  final Value<int> familyId;
  final Value<int> personId;
  final Value<int> rowid;
  const FamilyPartnersCompanion({
    this.familyId = const Value.absent(),
    this.personId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FamilyPartnersCompanion.insert({
    required int familyId,
    required int personId,
    this.rowid = const Value.absent(),
  }) : familyId = Value(familyId),
       personId = Value(personId);
  static Insertable<FamilyPartner> custom({
    Expression<int>? familyId,
    Expression<int>? personId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (familyId != null) 'family_id': familyId,
      if (personId != null) 'person_id': personId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FamilyPartnersCompanion copyWith({
    Value<int>? familyId,
    Value<int>? personId,
    Value<int>? rowid,
  }) {
    return FamilyPartnersCompanion(
      familyId: familyId ?? this.familyId,
      personId: personId ?? this.personId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (familyId.present) {
      map['family_id'] = Variable<int>(familyId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FamilyPartnersCompanion(')
          ..write('familyId: $familyId, ')
          ..write('personId: $personId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FamilyChildrenTable extends FamilyChildren
    with TableInfo<$FamilyChildrenTable, FamilyChildrenData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FamilyChildrenTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _familyIdMeta = const VerificationMeta(
    'familyId',
  );
  @override
  late final GeneratedColumn<int> familyId = GeneratedColumn<int>(
    'family_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES families (id)',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [familyId, personId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'family_children';
  @override
  VerificationContext validateIntegrity(
    Insertable<FamilyChildrenData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('family_id')) {
      context.handle(
        _familyIdMeta,
        familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_familyIdMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {familyId, personId};
  @override
  FamilyChildrenData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FamilyChildrenData(
      familyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}family_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
    );
  }

  @override
  $FamilyChildrenTable createAlias(String alias) {
    return $FamilyChildrenTable(attachedDatabase, alias);
  }
}

class FamilyChildrenData extends DataClass
    implements Insertable<FamilyChildrenData> {
  final int familyId;
  final int personId;
  const FamilyChildrenData({required this.familyId, required this.personId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['family_id'] = Variable<int>(familyId);
    map['person_id'] = Variable<int>(personId);
    return map;
  }

  FamilyChildrenCompanion toCompanion(bool nullToAbsent) {
    return FamilyChildrenCompanion(
      familyId: Value(familyId),
      personId: Value(personId),
    );
  }

  factory FamilyChildrenData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FamilyChildrenData(
      familyId: serializer.fromJson<int>(json['familyId']),
      personId: serializer.fromJson<int>(json['personId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'familyId': serializer.toJson<int>(familyId),
      'personId': serializer.toJson<int>(personId),
    };
  }

  FamilyChildrenData copyWith({int? familyId, int? personId}) =>
      FamilyChildrenData(
        familyId: familyId ?? this.familyId,
        personId: personId ?? this.personId,
      );
  FamilyChildrenData copyWithCompanion(FamilyChildrenCompanion data) {
    return FamilyChildrenData(
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      personId: data.personId.present ? data.personId.value : this.personId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FamilyChildrenData(')
          ..write('familyId: $familyId, ')
          ..write('personId: $personId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(familyId, personId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FamilyChildrenData &&
          other.familyId == this.familyId &&
          other.personId == this.personId);
}

class FamilyChildrenCompanion extends UpdateCompanion<FamilyChildrenData> {
  final Value<int> familyId;
  final Value<int> personId;
  final Value<int> rowid;
  const FamilyChildrenCompanion({
    this.familyId = const Value.absent(),
    this.personId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FamilyChildrenCompanion.insert({
    required int familyId,
    required int personId,
    this.rowid = const Value.absent(),
  }) : familyId = Value(familyId),
       personId = Value(personId);
  static Insertable<FamilyChildrenData> custom({
    Expression<int>? familyId,
    Expression<int>? personId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (familyId != null) 'family_id': familyId,
      if (personId != null) 'person_id': personId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FamilyChildrenCompanion copyWith({
    Value<int>? familyId,
    Value<int>? personId,
    Value<int>? rowid,
  }) {
    return FamilyChildrenCompanion(
      familyId: familyId ?? this.familyId,
      personId: personId ?? this.personId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (familyId.present) {
      map['family_id'] = Variable<int>(familyId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FamilyChildrenCompanion(')
          ..write('familyId: $familyId, ')
          ..write('personId: $personId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<EventType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EventType>($EventsTable.$convertertype);
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id)',
    ),
  );
  static const VerificationMeta _familyIdMeta = const VerificationMeta(
    'familyId',
  );
  @override
  late final GeneratedColumn<int> familyId = GeneratedColumn<int>(
    'family_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES families (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateQualifier?, String>
  qualifier = GeneratedColumn<String>(
    'qualifier',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<DateQualifier?>($EventsTable.$converterqualifiern);
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<int> month = GeneratedColumn<int>(
    'month',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<int> day = GeneratedColumn<int>(
    'day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearToMeta = const VerificationMeta('yearTo');
  @override
  late final GeneratedColumn<int> yearTo = GeneratedColumn<int>(
    'year_to',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _monthToMeta = const VerificationMeta(
    'monthTo',
  );
  @override
  late final GeneratedColumn<int> monthTo = GeneratedColumn<int>(
    'month_to',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayToMeta = const VerificationMeta('dayTo');
  @override
  late final GeneratedColumn<int> dayTo = GeneratedColumn<int>(
    'day_to',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placeMeta = const VerificationMeta('place');
  @override
  late final GeneratedColumn<String> place = GeneratedColumn<String>(
    'place',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    personId,
    familyId,
    qualifier,
    year,
    month,
    day,
    yearTo,
    monthTo,
    dayTo,
    place,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('family_id')) {
      context.handle(
        _familyIdMeta,
        familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('month')) {
      context.handle(
        _monthMeta,
        month.isAcceptableOrUnknown(data['month']!, _monthMeta),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    }
    if (data.containsKey('year_to')) {
      context.handle(
        _yearToMeta,
        yearTo.isAcceptableOrUnknown(data['year_to']!, _yearToMeta),
      );
    }
    if (data.containsKey('month_to')) {
      context.handle(
        _monthToMeta,
        monthTo.isAcceptableOrUnknown(data['month_to']!, _monthToMeta),
      );
    }
    if (data.containsKey('day_to')) {
      context.handle(
        _dayToMeta,
        dayTo.isAcceptableOrUnknown(data['day_to']!, _dayToMeta),
      );
    }
    if (data.containsKey('place')) {
      context.handle(
        _placeMeta,
        place.isAcceptableOrUnknown(data['place']!, _placeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: $EventsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      familyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}family_id'],
      ),
      qualifier: $EventsTable.$converterqualifiern.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}qualifier'],
        ),
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      month: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}month'],
      ),
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day'],
      ),
      yearTo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year_to'],
      ),
      monthTo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}month_to'],
      ),
      dayTo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_to'],
      ),
      place: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place'],
      ),
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EventType, String, String> $convertertype =
      const EnumNameConverter<EventType>(EventType.values);
  static JsonTypeConverter2<DateQualifier, String, String> $converterqualifier =
      const EnumNameConverter<DateQualifier>(DateQualifier.values);
  static JsonTypeConverter2<DateQualifier?, String?, String?>
  $converterqualifiern = JsonTypeConverter2.asNullable($converterqualifier);
}

class Event extends DataClass implements Insertable<Event> {
  final int id;
  final EventType type;
  final int? personId;
  final int? familyId;

  /// Null while the date is not known at all.
  final DateQualifier? qualifier;
  final int? year;
  final int? month;
  final int? day;
  final int? yearTo;
  final int? monthTo;
  final int? dayTo;
  final String? place;
  const Event({
    required this.id,
    required this.type,
    this.personId,
    this.familyId,
    this.qualifier,
    this.year,
    this.month,
    this.day,
    this.yearTo,
    this.monthTo,
    this.dayTo,
    this.place,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['type'] = Variable<String>($EventsTable.$convertertype.toSql(type));
    }
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    if (!nullToAbsent || familyId != null) {
      map['family_id'] = Variable<int>(familyId);
    }
    if (!nullToAbsent || qualifier != null) {
      map['qualifier'] = Variable<String>(
        $EventsTable.$converterqualifiern.toSql(qualifier),
      );
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || month != null) {
      map['month'] = Variable<int>(month);
    }
    if (!nullToAbsent || day != null) {
      map['day'] = Variable<int>(day);
    }
    if (!nullToAbsent || yearTo != null) {
      map['year_to'] = Variable<int>(yearTo);
    }
    if (!nullToAbsent || monthTo != null) {
      map['month_to'] = Variable<int>(monthTo);
    }
    if (!nullToAbsent || dayTo != null) {
      map['day_to'] = Variable<int>(dayTo);
    }
    if (!nullToAbsent || place != null) {
      map['place'] = Variable<String>(place);
    }
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      type: Value(type),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      familyId: familyId == null && nullToAbsent
          ? const Value.absent()
          : Value(familyId),
      qualifier: qualifier == null && nullToAbsent
          ? const Value.absent()
          : Value(qualifier),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      month: month == null && nullToAbsent
          ? const Value.absent()
          : Value(month),
      day: day == null && nullToAbsent ? const Value.absent() : Value(day),
      yearTo: yearTo == null && nullToAbsent
          ? const Value.absent()
          : Value(yearTo),
      monthTo: monthTo == null && nullToAbsent
          ? const Value.absent()
          : Value(monthTo),
      dayTo: dayTo == null && nullToAbsent
          ? const Value.absent()
          : Value(dayTo),
      place: place == null && nullToAbsent
          ? const Value.absent()
          : Value(place),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<int>(json['id']),
      type: $EventsTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      personId: serializer.fromJson<int?>(json['personId']),
      familyId: serializer.fromJson<int?>(json['familyId']),
      qualifier: $EventsTable.$converterqualifiern.fromJson(
        serializer.fromJson<String?>(json['qualifier']),
      ),
      year: serializer.fromJson<int?>(json['year']),
      month: serializer.fromJson<int?>(json['month']),
      day: serializer.fromJson<int?>(json['day']),
      yearTo: serializer.fromJson<int?>(json['yearTo']),
      monthTo: serializer.fromJson<int?>(json['monthTo']),
      dayTo: serializer.fromJson<int?>(json['dayTo']),
      place: serializer.fromJson<String?>(json['place']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(
        $EventsTable.$convertertype.toJson(type),
      ),
      'personId': serializer.toJson<int?>(personId),
      'familyId': serializer.toJson<int?>(familyId),
      'qualifier': serializer.toJson<String?>(
        $EventsTable.$converterqualifiern.toJson(qualifier),
      ),
      'year': serializer.toJson<int?>(year),
      'month': serializer.toJson<int?>(month),
      'day': serializer.toJson<int?>(day),
      'yearTo': serializer.toJson<int?>(yearTo),
      'monthTo': serializer.toJson<int?>(monthTo),
      'dayTo': serializer.toJson<int?>(dayTo),
      'place': serializer.toJson<String?>(place),
    };
  }

  Event copyWith({
    int? id,
    EventType? type,
    Value<int?> personId = const Value.absent(),
    Value<int?> familyId = const Value.absent(),
    Value<DateQualifier?> qualifier = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<int?> month = const Value.absent(),
    Value<int?> day = const Value.absent(),
    Value<int?> yearTo = const Value.absent(),
    Value<int?> monthTo = const Value.absent(),
    Value<int?> dayTo = const Value.absent(),
    Value<String?> place = const Value.absent(),
  }) => Event(
    id: id ?? this.id,
    type: type ?? this.type,
    personId: personId.present ? personId.value : this.personId,
    familyId: familyId.present ? familyId.value : this.familyId,
    qualifier: qualifier.present ? qualifier.value : this.qualifier,
    year: year.present ? year.value : this.year,
    month: month.present ? month.value : this.month,
    day: day.present ? day.value : this.day,
    yearTo: yearTo.present ? yearTo.value : this.yearTo,
    monthTo: monthTo.present ? monthTo.value : this.monthTo,
    dayTo: dayTo.present ? dayTo.value : this.dayTo,
    place: place.present ? place.value : this.place,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      personId: data.personId.present ? data.personId.value : this.personId,
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      qualifier: data.qualifier.present ? data.qualifier.value : this.qualifier,
      year: data.year.present ? data.year.value : this.year,
      month: data.month.present ? data.month.value : this.month,
      day: data.day.present ? data.day.value : this.day,
      yearTo: data.yearTo.present ? data.yearTo.value : this.yearTo,
      monthTo: data.monthTo.present ? data.monthTo.value : this.monthTo,
      dayTo: data.dayTo.present ? data.dayTo.value : this.dayTo,
      place: data.place.present ? data.place.value : this.place,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('personId: $personId, ')
          ..write('familyId: $familyId, ')
          ..write('qualifier: $qualifier, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('day: $day, ')
          ..write('yearTo: $yearTo, ')
          ..write('monthTo: $monthTo, ')
          ..write('dayTo: $dayTo, ')
          ..write('place: $place')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    personId,
    familyId,
    qualifier,
    year,
    month,
    day,
    yearTo,
    monthTo,
    dayTo,
    place,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.type == this.type &&
          other.personId == this.personId &&
          other.familyId == this.familyId &&
          other.qualifier == this.qualifier &&
          other.year == this.year &&
          other.month == this.month &&
          other.day == this.day &&
          other.yearTo == this.yearTo &&
          other.monthTo == this.monthTo &&
          other.dayTo == this.dayTo &&
          other.place == this.place);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<int> id;
  final Value<EventType> type;
  final Value<int?> personId;
  final Value<int?> familyId;
  final Value<DateQualifier?> qualifier;
  final Value<int?> year;
  final Value<int?> month;
  final Value<int?> day;
  final Value<int?> yearTo;
  final Value<int?> monthTo;
  final Value<int?> dayTo;
  final Value<String?> place;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.personId = const Value.absent(),
    this.familyId = const Value.absent(),
    this.qualifier = const Value.absent(),
    this.year = const Value.absent(),
    this.month = const Value.absent(),
    this.day = const Value.absent(),
    this.yearTo = const Value.absent(),
    this.monthTo = const Value.absent(),
    this.dayTo = const Value.absent(),
    this.place = const Value.absent(),
  });
  EventsCompanion.insert({
    this.id = const Value.absent(),
    required EventType type,
    this.personId = const Value.absent(),
    this.familyId = const Value.absent(),
    this.qualifier = const Value.absent(),
    this.year = const Value.absent(),
    this.month = const Value.absent(),
    this.day = const Value.absent(),
    this.yearTo = const Value.absent(),
    this.monthTo = const Value.absent(),
    this.dayTo = const Value.absent(),
    this.place = const Value.absent(),
  }) : type = Value(type);
  static Insertable<Event> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<int>? personId,
    Expression<int>? familyId,
    Expression<String>? qualifier,
    Expression<int>? year,
    Expression<int>? month,
    Expression<int>? day,
    Expression<int>? yearTo,
    Expression<int>? monthTo,
    Expression<int>? dayTo,
    Expression<String>? place,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (personId != null) 'person_id': personId,
      if (familyId != null) 'family_id': familyId,
      if (qualifier != null) 'qualifier': qualifier,
      if (year != null) 'year': year,
      if (month != null) 'month': month,
      if (day != null) 'day': day,
      if (yearTo != null) 'year_to': yearTo,
      if (monthTo != null) 'month_to': monthTo,
      if (dayTo != null) 'day_to': dayTo,
      if (place != null) 'place': place,
    });
  }

  EventsCompanion copyWith({
    Value<int>? id,
    Value<EventType>? type,
    Value<int?>? personId,
    Value<int?>? familyId,
    Value<DateQualifier?>? qualifier,
    Value<int?>? year,
    Value<int?>? month,
    Value<int?>? day,
    Value<int?>? yearTo,
    Value<int?>? monthTo,
    Value<int?>? dayTo,
    Value<String?>? place,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      personId: personId ?? this.personId,
      familyId: familyId ?? this.familyId,
      qualifier: qualifier ?? this.qualifier,
      year: year ?? this.year,
      month: month ?? this.month,
      day: day ?? this.day,
      yearTo: yearTo ?? this.yearTo,
      monthTo: monthTo ?? this.monthTo,
      dayTo: dayTo ?? this.dayTo,
      place: place ?? this.place,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $EventsTable.$convertertype.toSql(type.value),
      );
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (familyId.present) {
      map['family_id'] = Variable<int>(familyId.value);
    }
    if (qualifier.present) {
      map['qualifier'] = Variable<String>(
        $EventsTable.$converterqualifiern.toSql(qualifier.value),
      );
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (month.present) {
      map['month'] = Variable<int>(month.value);
    }
    if (day.present) {
      map['day'] = Variable<int>(day.value);
    }
    if (yearTo.present) {
      map['year_to'] = Variable<int>(yearTo.value);
    }
    if (monthTo.present) {
      map['month_to'] = Variable<int>(monthTo.value);
    }
    if (dayTo.present) {
      map['day_to'] = Variable<int>(dayTo.value);
    }
    if (place.present) {
      map['place'] = Variable<String>(place.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('personId: $personId, ')
          ..write('familyId: $familyId, ')
          ..write('qualifier: $qualifier, ')
          ..write('year: $year, ')
          ..write('month: $month, ')
          ..write('day: $day, ')
          ..write('yearTo: $yearTo, ')
          ..write('monthTo: $monthTo, ')
          ..write('dayTo: $dayTo, ')
          ..write('place: $place')
          ..write(')'))
        .toString();
  }
}

class $CemeteriesTable extends Cemeteries
    with TableInfo<$CemeteriesTable, Cemetery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CemeteriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
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
  static const VerificationMeta _localityMeta = const VerificationMeta(
    'locality',
  );
  @override
  late final GeneratedColumn<String> locality = GeneratedColumn<String>(
    'locality',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _centerLatMeta = const VerificationMeta(
    'centerLat',
  );
  @override
  late final GeneratedColumn<double> centerLat = GeneratedColumn<double>(
    'center_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _centerLonMeta = const VerificationMeta(
    'centerLon',
  );
  @override
  late final GeneratedColumn<double> centerLon = GeneratedColumn<double>(
    'center_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _grobonetUrlMeta = const VerificationMeta(
    'grobonetUrl',
  );
  @override
  late final GeneratedColumn<String> grobonetUrl = GeneratedColumn<String>(
    'grobonet_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    locality,
    centerLat,
    centerLon,
    grobonetUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cemeteries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Cemetery> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('locality')) {
      context.handle(
        _localityMeta,
        locality.isAcceptableOrUnknown(data['locality']!, _localityMeta),
      );
    }
    if (data.containsKey('center_lat')) {
      context.handle(
        _centerLatMeta,
        centerLat.isAcceptableOrUnknown(data['center_lat']!, _centerLatMeta),
      );
    }
    if (data.containsKey('center_lon')) {
      context.handle(
        _centerLonMeta,
        centerLon.isAcceptableOrUnknown(data['center_lon']!, _centerLonMeta),
      );
    }
    if (data.containsKey('grobonet_url')) {
      context.handle(
        _grobonetUrlMeta,
        grobonetUrl.isAcceptableOrUnknown(
          data['grobonet_url']!,
          _grobonetUrlMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Cemetery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Cemetery(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      locality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locality'],
      ),
      centerLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_lat'],
      ),
      centerLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_lon'],
      ),
      grobonetUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grobonet_url'],
      ),
    );
  }

  @override
  $CemeteriesTable createAlias(String alias) {
    return $CemeteriesTable(attachedDatabase, alias);
  }
}

class Cemetery extends DataClass implements Insertable<Cemetery> {
  final int id;
  final String name;
  final String? locality;
  final double? centerLat;
  final double? centerLon;
  final String? grobonetUrl;
  const Cemetery({
    required this.id,
    required this.name,
    this.locality,
    this.centerLat,
    this.centerLon,
    this.grobonetUrl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || locality != null) {
      map['locality'] = Variable<String>(locality);
    }
    if (!nullToAbsent || centerLat != null) {
      map['center_lat'] = Variable<double>(centerLat);
    }
    if (!nullToAbsent || centerLon != null) {
      map['center_lon'] = Variable<double>(centerLon);
    }
    if (!nullToAbsent || grobonetUrl != null) {
      map['grobonet_url'] = Variable<String>(grobonetUrl);
    }
    return map;
  }

  CemeteriesCompanion toCompanion(bool nullToAbsent) {
    return CemeteriesCompanion(
      id: Value(id),
      name: Value(name),
      locality: locality == null && nullToAbsent
          ? const Value.absent()
          : Value(locality),
      centerLat: centerLat == null && nullToAbsent
          ? const Value.absent()
          : Value(centerLat),
      centerLon: centerLon == null && nullToAbsent
          ? const Value.absent()
          : Value(centerLon),
      grobonetUrl: grobonetUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(grobonetUrl),
    );
  }

  factory Cemetery.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Cemetery(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      locality: serializer.fromJson<String?>(json['locality']),
      centerLat: serializer.fromJson<double?>(json['centerLat']),
      centerLon: serializer.fromJson<double?>(json['centerLon']),
      grobonetUrl: serializer.fromJson<String?>(json['grobonetUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'locality': serializer.toJson<String?>(locality),
      'centerLat': serializer.toJson<double?>(centerLat),
      'centerLon': serializer.toJson<double?>(centerLon),
      'grobonetUrl': serializer.toJson<String?>(grobonetUrl),
    };
  }

  Cemetery copyWith({
    int? id,
    String? name,
    Value<String?> locality = const Value.absent(),
    Value<double?> centerLat = const Value.absent(),
    Value<double?> centerLon = const Value.absent(),
    Value<String?> grobonetUrl = const Value.absent(),
  }) => Cemetery(
    id: id ?? this.id,
    name: name ?? this.name,
    locality: locality.present ? locality.value : this.locality,
    centerLat: centerLat.present ? centerLat.value : this.centerLat,
    centerLon: centerLon.present ? centerLon.value : this.centerLon,
    grobonetUrl: grobonetUrl.present ? grobonetUrl.value : this.grobonetUrl,
  );
  Cemetery copyWithCompanion(CemeteriesCompanion data) {
    return Cemetery(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      locality: data.locality.present ? data.locality.value : this.locality,
      centerLat: data.centerLat.present ? data.centerLat.value : this.centerLat,
      centerLon: data.centerLon.present ? data.centerLon.value : this.centerLon,
      grobonetUrl: data.grobonetUrl.present
          ? data.grobonetUrl.value
          : this.grobonetUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Cemetery(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('locality: $locality, ')
          ..write('centerLat: $centerLat, ')
          ..write('centerLon: $centerLon, ')
          ..write('grobonetUrl: $grobonetUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, locality, centerLat, centerLon, grobonetUrl);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Cemetery &&
          other.id == this.id &&
          other.name == this.name &&
          other.locality == this.locality &&
          other.centerLat == this.centerLat &&
          other.centerLon == this.centerLon &&
          other.grobonetUrl == this.grobonetUrl);
}

class CemeteriesCompanion extends UpdateCompanion<Cemetery> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> locality;
  final Value<double?> centerLat;
  final Value<double?> centerLon;
  final Value<String?> grobonetUrl;
  const CemeteriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.locality = const Value.absent(),
    this.centerLat = const Value.absent(),
    this.centerLon = const Value.absent(),
    this.grobonetUrl = const Value.absent(),
  });
  CemeteriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.locality = const Value.absent(),
    this.centerLat = const Value.absent(),
    this.centerLon = const Value.absent(),
    this.grobonetUrl = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Cemetery> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? locality,
    Expression<double>? centerLat,
    Expression<double>? centerLon,
    Expression<String>? grobonetUrl,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (locality != null) 'locality': locality,
      if (centerLat != null) 'center_lat': centerLat,
      if (centerLon != null) 'center_lon': centerLon,
      if (grobonetUrl != null) 'grobonet_url': grobonetUrl,
    });
  }

  CemeteriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? locality,
    Value<double?>? centerLat,
    Value<double?>? centerLon,
    Value<String?>? grobonetUrl,
  }) {
    return CemeteriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      locality: locality ?? this.locality,
      centerLat: centerLat ?? this.centerLat,
      centerLon: centerLon ?? this.centerLon,
      grobonetUrl: grobonetUrl ?? this.grobonetUrl,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (locality.present) {
      map['locality'] = Variable<String>(locality.value);
    }
    if (centerLat.present) {
      map['center_lat'] = Variable<double>(centerLat.value);
    }
    if (centerLon.present) {
      map['center_lon'] = Variable<double>(centerLon.value);
    }
    if (grobonetUrl.present) {
      map['grobonet_url'] = Variable<String>(grobonetUrl.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CemeteriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('locality: $locality, ')
          ..write('centerLat: $centerLat, ')
          ..write('centerLon: $centerLon, ')
          ..write('grobonetUrl: $grobonetUrl')
          ..write(')'))
        .toString();
  }
}

class $GravesTable extends Graves with TableInfo<$GravesTable, Grave> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GravesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cemeteryIdMeta = const VerificationMeta(
    'cemeteryId',
  );
  @override
  late final GeneratedColumn<int> cemeteryId = GeneratedColumn<int>(
    'cemetery_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES cemeteries (id)',
    ),
  );
  static const VerificationMeta _sectorMeta = const VerificationMeta('sector');
  @override
  late final GeneratedColumn<String> sector = GeneratedColumn<String>(
    'sector',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowMeta = const VerificationMeta('row');
  @override
  late final GeneratedColumn<String> row = GeneratedColumn<String>(
    'row',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plotMeta = const VerificationMeta('plot');
  @override
  late final GeneratedColumn<String> plot = GeneratedColumn<String>(
    'plot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PositionSource?, String>
  positionSource = GeneratedColumn<String>(
    'position_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<PositionSource?>($GravesTable.$converterpositionSourcen);
  static const VerificationMeta _positionAccuracyMMeta = const VerificationMeta(
    'positionAccuracyM',
  );
  @override
  late final GeneratedColumn<double> positionAccuracyM =
      GeneratedColumn<double>(
        'position_accuracy_m',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cemeteryId,
    sector,
    row,
    plot,
    lat,
    lon,
    positionSource,
    positionAccuracyM,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'graves';
  @override
  VerificationContext validateIntegrity(
    Insertable<Grave> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cemetery_id')) {
      context.handle(
        _cemeteryIdMeta,
        cemeteryId.isAcceptableOrUnknown(data['cemetery_id']!, _cemeteryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cemeteryIdMeta);
    }
    if (data.containsKey('sector')) {
      context.handle(
        _sectorMeta,
        sector.isAcceptableOrUnknown(data['sector']!, _sectorMeta),
      );
    }
    if (data.containsKey('row')) {
      context.handle(
        _rowMeta,
        row.isAcceptableOrUnknown(data['row']!, _rowMeta),
      );
    }
    if (data.containsKey('plot')) {
      context.handle(
        _plotMeta,
        plot.isAcceptableOrUnknown(data['plot']!, _plotMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    }
    if (data.containsKey('position_accuracy_m')) {
      context.handle(
        _positionAccuracyMMeta,
        positionAccuracyM.isAcceptableOrUnknown(
          data['position_accuracy_m']!,
          _positionAccuracyMMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Grave map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Grave(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cemeteryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cemetery_id'],
      )!,
      sector: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sector'],
      ),
      row: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row'],
      ),
      plot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plot'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      ),
      positionSource: $GravesTable.$converterpositionSourcen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}position_source'],
        ),
      ),
      positionAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}position_accuracy_m'],
      ),
    );
  }

  @override
  $GravesTable createAlias(String alias) {
    return $GravesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PositionSource, String, String>
  $converterpositionSource = const EnumNameConverter<PositionSource>(
    PositionSource.values,
  );
  static JsonTypeConverter2<PositionSource?, String?, String?>
  $converterpositionSourcen = JsonTypeConverter2.asNullable(
    $converterpositionSource,
  );
}

class Grave extends DataClass implements Insertable<Grave> {
  final int id;
  final int cemeteryId;
  final String? sector;
  final String? row;
  final String? plot;
  final double? lat;
  final double? lon;
  final PositionSource? positionSource;
  final double? positionAccuracyM;
  const Grave({
    required this.id,
    required this.cemeteryId,
    this.sector,
    this.row,
    this.plot,
    this.lat,
    this.lon,
    this.positionSource,
    this.positionAccuracyM,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cemetery_id'] = Variable<int>(cemeteryId);
    if (!nullToAbsent || sector != null) {
      map['sector'] = Variable<String>(sector);
    }
    if (!nullToAbsent || row != null) {
      map['row'] = Variable<String>(row);
    }
    if (!nullToAbsent || plot != null) {
      map['plot'] = Variable<String>(plot);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lon != null) {
      map['lon'] = Variable<double>(lon);
    }
    if (!nullToAbsent || positionSource != null) {
      map['position_source'] = Variable<String>(
        $GravesTable.$converterpositionSourcen.toSql(positionSource),
      );
    }
    if (!nullToAbsent || positionAccuracyM != null) {
      map['position_accuracy_m'] = Variable<double>(positionAccuracyM);
    }
    return map;
  }

  GravesCompanion toCompanion(bool nullToAbsent) {
    return GravesCompanion(
      id: Value(id),
      cemeteryId: Value(cemeteryId),
      sector: sector == null && nullToAbsent
          ? const Value.absent()
          : Value(sector),
      row: row == null && nullToAbsent ? const Value.absent() : Value(row),
      plot: plot == null && nullToAbsent ? const Value.absent() : Value(plot),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lon: lon == null && nullToAbsent ? const Value.absent() : Value(lon),
      positionSource: positionSource == null && nullToAbsent
          ? const Value.absent()
          : Value(positionSource),
      positionAccuracyM: positionAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(positionAccuracyM),
    );
  }

  factory Grave.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Grave(
      id: serializer.fromJson<int>(json['id']),
      cemeteryId: serializer.fromJson<int>(json['cemeteryId']),
      sector: serializer.fromJson<String?>(json['sector']),
      row: serializer.fromJson<String?>(json['row']),
      plot: serializer.fromJson<String?>(json['plot']),
      lat: serializer.fromJson<double?>(json['lat']),
      lon: serializer.fromJson<double?>(json['lon']),
      positionSource: $GravesTable.$converterpositionSourcen.fromJson(
        serializer.fromJson<String?>(json['positionSource']),
      ),
      positionAccuracyM: serializer.fromJson<double?>(
        json['positionAccuracyM'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cemeteryId': serializer.toJson<int>(cemeteryId),
      'sector': serializer.toJson<String?>(sector),
      'row': serializer.toJson<String?>(row),
      'plot': serializer.toJson<String?>(plot),
      'lat': serializer.toJson<double?>(lat),
      'lon': serializer.toJson<double?>(lon),
      'positionSource': serializer.toJson<String?>(
        $GravesTable.$converterpositionSourcen.toJson(positionSource),
      ),
      'positionAccuracyM': serializer.toJson<double?>(positionAccuracyM),
    };
  }

  Grave copyWith({
    int? id,
    int? cemeteryId,
    Value<String?> sector = const Value.absent(),
    Value<String?> row = const Value.absent(),
    Value<String?> plot = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lon = const Value.absent(),
    Value<PositionSource?> positionSource = const Value.absent(),
    Value<double?> positionAccuracyM = const Value.absent(),
  }) => Grave(
    id: id ?? this.id,
    cemeteryId: cemeteryId ?? this.cemeteryId,
    sector: sector.present ? sector.value : this.sector,
    row: row.present ? row.value : this.row,
    plot: plot.present ? plot.value : this.plot,
    lat: lat.present ? lat.value : this.lat,
    lon: lon.present ? lon.value : this.lon,
    positionSource: positionSource.present
        ? positionSource.value
        : this.positionSource,
    positionAccuracyM: positionAccuracyM.present
        ? positionAccuracyM.value
        : this.positionAccuracyM,
  );
  Grave copyWithCompanion(GravesCompanion data) {
    return Grave(
      id: data.id.present ? data.id.value : this.id,
      cemeteryId: data.cemeteryId.present
          ? data.cemeteryId.value
          : this.cemeteryId,
      sector: data.sector.present ? data.sector.value : this.sector,
      row: data.row.present ? data.row.value : this.row,
      plot: data.plot.present ? data.plot.value : this.plot,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      positionSource: data.positionSource.present
          ? data.positionSource.value
          : this.positionSource,
      positionAccuracyM: data.positionAccuracyM.present
          ? data.positionAccuracyM.value
          : this.positionAccuracyM,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Grave(')
          ..write('id: $id, ')
          ..write('cemeteryId: $cemeteryId, ')
          ..write('sector: $sector, ')
          ..write('row: $row, ')
          ..write('plot: $plot, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('positionSource: $positionSource, ')
          ..write('positionAccuracyM: $positionAccuracyM')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cemeteryId,
    sector,
    row,
    plot,
    lat,
    lon,
    positionSource,
    positionAccuracyM,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Grave &&
          other.id == this.id &&
          other.cemeteryId == this.cemeteryId &&
          other.sector == this.sector &&
          other.row == this.row &&
          other.plot == this.plot &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.positionSource == this.positionSource &&
          other.positionAccuracyM == this.positionAccuracyM);
}

class GravesCompanion extends UpdateCompanion<Grave> {
  final Value<int> id;
  final Value<int> cemeteryId;
  final Value<String?> sector;
  final Value<String?> row;
  final Value<String?> plot;
  final Value<double?> lat;
  final Value<double?> lon;
  final Value<PositionSource?> positionSource;
  final Value<double?> positionAccuracyM;
  const GravesCompanion({
    this.id = const Value.absent(),
    this.cemeteryId = const Value.absent(),
    this.sector = const Value.absent(),
    this.row = const Value.absent(),
    this.plot = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.positionSource = const Value.absent(),
    this.positionAccuracyM = const Value.absent(),
  });
  GravesCompanion.insert({
    this.id = const Value.absent(),
    required int cemeteryId,
    this.sector = const Value.absent(),
    this.row = const Value.absent(),
    this.plot = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.positionSource = const Value.absent(),
    this.positionAccuracyM = const Value.absent(),
  }) : cemeteryId = Value(cemeteryId);
  static Insertable<Grave> custom({
    Expression<int>? id,
    Expression<int>? cemeteryId,
    Expression<String>? sector,
    Expression<String>? row,
    Expression<String>? plot,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<String>? positionSource,
    Expression<double>? positionAccuracyM,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cemeteryId != null) 'cemetery_id': cemeteryId,
      if (sector != null) 'sector': sector,
      if (row != null) 'row': row,
      if (plot != null) 'plot': plot,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (positionSource != null) 'position_source': positionSource,
      if (positionAccuracyM != null) 'position_accuracy_m': positionAccuracyM,
    });
  }

  GravesCompanion copyWith({
    Value<int>? id,
    Value<int>? cemeteryId,
    Value<String?>? sector,
    Value<String?>? row,
    Value<String?>? plot,
    Value<double?>? lat,
    Value<double?>? lon,
    Value<PositionSource?>? positionSource,
    Value<double?>? positionAccuracyM,
  }) {
    return GravesCompanion(
      id: id ?? this.id,
      cemeteryId: cemeteryId ?? this.cemeteryId,
      sector: sector ?? this.sector,
      row: row ?? this.row,
      plot: plot ?? this.plot,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      positionSource: positionSource ?? this.positionSource,
      positionAccuracyM: positionAccuracyM ?? this.positionAccuracyM,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cemeteryId.present) {
      map['cemetery_id'] = Variable<int>(cemeteryId.value);
    }
    if (sector.present) {
      map['sector'] = Variable<String>(sector.value);
    }
    if (row.present) {
      map['row'] = Variable<String>(row.value);
    }
    if (plot.present) {
      map['plot'] = Variable<String>(plot.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (positionSource.present) {
      map['position_source'] = Variable<String>(
        $GravesTable.$converterpositionSourcen.toSql(positionSource.value),
      );
    }
    if (positionAccuracyM.present) {
      map['position_accuracy_m'] = Variable<double>(positionAccuracyM.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GravesCompanion(')
          ..write('id: $id, ')
          ..write('cemeteryId: $cemeteryId, ')
          ..write('sector: $sector, ')
          ..write('row: $row, ')
          ..write('plot: $plot, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('positionSource: $positionSource, ')
          ..write('positionAccuracyM: $positionAccuracyM')
          ..write(')'))
        .toString();
  }
}

class $BurialsTable extends Burials with TableInfo<$BurialsTable, Burial> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BurialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES persons (id)',
    ),
  );
  static const VerificationMeta _graveIdMeta = const VerificationMeta(
    'graveId',
  );
  @override
  late final GeneratedColumn<int> graveId = GeneratedColumn<int>(
    'grave_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES graves (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [personId, graveId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'burials';
  @override
  VerificationContext validateIntegrity(
    Insertable<Burial> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('grave_id')) {
      context.handle(
        _graveIdMeta,
        graveId.isAcceptableOrUnknown(data['grave_id']!, _graveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_graveIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  Burial map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Burial(
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
      graveId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}grave_id'],
      )!,
    );
  }

  @override
  $BurialsTable createAlias(String alias) {
    return $BurialsTable(attachedDatabase, alias);
  }
}

class Burial extends DataClass implements Insertable<Burial> {
  final int personId;
  final int graveId;
  const Burial({required this.personId, required this.graveId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['person_id'] = Variable<int>(personId);
    map['grave_id'] = Variable<int>(graveId);
    return map;
  }

  BurialsCompanion toCompanion(bool nullToAbsent) {
    return BurialsCompanion(personId: Value(personId), graveId: Value(graveId));
  }

  factory Burial.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Burial(
      personId: serializer.fromJson<int>(json['personId']),
      graveId: serializer.fromJson<int>(json['graveId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'personId': serializer.toJson<int>(personId),
      'graveId': serializer.toJson<int>(graveId),
    };
  }

  Burial copyWith({int? personId, int? graveId}) => Burial(
    personId: personId ?? this.personId,
    graveId: graveId ?? this.graveId,
  );
  Burial copyWithCompanion(BurialsCompanion data) {
    return Burial(
      personId: data.personId.present ? data.personId.value : this.personId,
      graveId: data.graveId.present ? data.graveId.value : this.graveId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Burial(')
          ..write('personId: $personId, ')
          ..write('graveId: $graveId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(personId, graveId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Burial &&
          other.personId == this.personId &&
          other.graveId == this.graveId);
}

class BurialsCompanion extends UpdateCompanion<Burial> {
  final Value<int> personId;
  final Value<int> graveId;
  final Value<int> rowid;
  const BurialsCompanion({
    this.personId = const Value.absent(),
    this.graveId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BurialsCompanion.insert({
    required int personId,
    required int graveId,
    this.rowid = const Value.absent(),
  }) : personId = Value(personId),
       graveId = Value(graveId);
  static Insertable<Burial> custom({
    Expression<int>? personId,
    Expression<int>? graveId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (personId != null) 'person_id': personId,
      if (graveId != null) 'grave_id': graveId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BurialsCompanion copyWith({
    Value<int>? personId,
    Value<int>? graveId,
    Value<int>? rowid,
  }) {
    return BurialsCompanion(
      personId: personId ?? this.personId,
      graveId: graveId ?? this.graveId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (graveId.present) {
      map['grave_id'] = Variable<int>(graveId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BurialsCompanion(')
          ..write('personId: $personId, ')
          ..write('graveId: $graveId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaTable extends Media with TableInfo<$MediaTable, MediaFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id)',
    ),
  );
  static const VerificationMeta _graveIdMeta = const VerificationMeta(
    'graveId',
  );
  @override
  late final GeneratedColumn<int> graveId = GeneratedColumn<int>(
    'grave_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES graves (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, relativePath, personId, graveId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('grave_id')) {
      context.handle(
        _graveIdMeta,
        graveId.isAcceptableOrUnknown(data['grave_id']!, _graveIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaFile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      graveId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}grave_id'],
      ),
    );
  }

  @override
  $MediaTable createAlias(String alias) {
    return $MediaTable(attachedDatabase, alias);
  }
}

class MediaFile extends DataClass implements Insertable<MediaFile> {
  final int id;
  final String relativePath;
  final int? personId;
  final int? graveId;
  const MediaFile({
    required this.id,
    required this.relativePath,
    this.personId,
    this.graveId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['relative_path'] = Variable<String>(relativePath);
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    if (!nullToAbsent || graveId != null) {
      map['grave_id'] = Variable<int>(graveId);
    }
    return map;
  }

  MediaCompanion toCompanion(bool nullToAbsent) {
    return MediaCompanion(
      id: Value(id),
      relativePath: Value(relativePath),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      graveId: graveId == null && nullToAbsent
          ? const Value.absent()
          : Value(graveId),
    );
  }

  factory MediaFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaFile(
      id: serializer.fromJson<int>(json['id']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      personId: serializer.fromJson<int?>(json['personId']),
      graveId: serializer.fromJson<int?>(json['graveId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'relativePath': serializer.toJson<String>(relativePath),
      'personId': serializer.toJson<int?>(personId),
      'graveId': serializer.toJson<int?>(graveId),
    };
  }

  MediaFile copyWith({
    int? id,
    String? relativePath,
    Value<int?> personId = const Value.absent(),
    Value<int?> graveId = const Value.absent(),
  }) => MediaFile(
    id: id ?? this.id,
    relativePath: relativePath ?? this.relativePath,
    personId: personId.present ? personId.value : this.personId,
    graveId: graveId.present ? graveId.value : this.graveId,
  );
  MediaFile copyWithCompanion(MediaCompanion data) {
    return MediaFile(
      id: data.id.present ? data.id.value : this.id,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      personId: data.personId.present ? data.personId.value : this.personId,
      graveId: data.graveId.present ? data.graveId.value : this.graveId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaFile(')
          ..write('id: $id, ')
          ..write('relativePath: $relativePath, ')
          ..write('personId: $personId, ')
          ..write('graveId: $graveId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, relativePath, personId, graveId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaFile &&
          other.id == this.id &&
          other.relativePath == this.relativePath &&
          other.personId == this.personId &&
          other.graveId == this.graveId);
}

class MediaCompanion extends UpdateCompanion<MediaFile> {
  final Value<int> id;
  final Value<String> relativePath;
  final Value<int?> personId;
  final Value<int?> graveId;
  const MediaCompanion({
    this.id = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.personId = const Value.absent(),
    this.graveId = const Value.absent(),
  });
  MediaCompanion.insert({
    this.id = const Value.absent(),
    required String relativePath,
    this.personId = const Value.absent(),
    this.graveId = const Value.absent(),
  }) : relativePath = Value(relativePath);
  static Insertable<MediaFile> custom({
    Expression<int>? id,
    Expression<String>? relativePath,
    Expression<int>? personId,
    Expression<int>? graveId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (relativePath != null) 'relative_path': relativePath,
      if (personId != null) 'person_id': personId,
      if (graveId != null) 'grave_id': graveId,
    });
  }

  MediaCompanion copyWith({
    Value<int>? id,
    Value<String>? relativePath,
    Value<int?>? personId,
    Value<int?>? graveId,
  }) {
    return MediaCompanion(
      id: id ?? this.id,
      relativePath: relativePath ?? this.relativePath,
      personId: personId ?? this.personId,
      graveId: graveId ?? this.graveId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (graveId.present) {
      map['grave_id'] = Variable<int>(graveId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCompanion(')
          ..write('id: $id, ')
          ..write('relativePath: $relativePath, ')
          ..write('personId: $personId, ')
          ..write('graveId: $graveId')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mePersonIdMeta = const VerificationMeta(
    'mePersonId',
  );
  @override
  late final GeneratedColumn<int> mePersonId = GeneratedColumn<int>(
    'me_person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [id, mePersonId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('me_person_id')) {
      context.handle(
        _mePersonIdMeta,
        mePersonId.isAcceptableOrUnknown(
          data['me_person_id']!,
          _mePersonIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mePersonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}me_person_id'],
      ),
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final int id;
  final int? mePersonId;
  const Setting({required this.id, this.mePersonId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mePersonId != null) {
      map['me_person_id'] = Variable<int>(mePersonId);
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      id: Value(id),
      mePersonId: mePersonId == null && nullToAbsent
          ? const Value.absent()
          : Value(mePersonId),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      id: serializer.fromJson<int>(json['id']),
      mePersonId: serializer.fromJson<int?>(json['mePersonId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mePersonId': serializer.toJson<int?>(mePersonId),
    };
  }

  Setting copyWith({int? id, Value<int?> mePersonId = const Value.absent()}) =>
      Setting(
        id: id ?? this.id,
        mePersonId: mePersonId.present ? mePersonId.value : this.mePersonId,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      id: data.id.present ? data.id.value : this.id,
      mePersonId: data.mePersonId.present
          ? data.mePersonId.value
          : this.mePersonId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('id: $id, ')
          ..write('mePersonId: $mePersonId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mePersonId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.id == this.id &&
          other.mePersonId == this.mePersonId);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<int> id;
  final Value<int?> mePersonId;
  const SettingsCompanion({
    this.id = const Value.absent(),
    this.mePersonId = const Value.absent(),
  });
  SettingsCompanion.insert({
    this.id = const Value.absent(),
    this.mePersonId = const Value.absent(),
  });
  static Insertable<Setting> custom({
    Expression<int>? id,
    Expression<int>? mePersonId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mePersonId != null) 'me_person_id': mePersonId,
    });
  }

  SettingsCompanion copyWith({Value<int>? id, Value<int?>? mePersonId}) {
    return SettingsCompanion(
      id: id ?? this.id,
      mePersonId: mePersonId ?? this.mePersonId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mePersonId.present) {
      map['me_person_id'] = Variable<int>(mePersonId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('id: $id, ')
          ..write('mePersonId: $mePersonId')
          ..write(')'))
        .toString();
  }
}

abstract class _$GrobingDatabase extends GeneratedDatabase {
  _$GrobingDatabase(QueryExecutor e) : super(e);
  $GrobingDatabaseManager get managers => $GrobingDatabaseManager(this);
  late final $PersonsTable persons = $PersonsTable(this);
  late final $FamiliesTable families = $FamiliesTable(this);
  late final $FamilyPartnersTable familyPartners = $FamilyPartnersTable(this);
  late final $FamilyChildrenTable familyChildren = $FamilyChildrenTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $CemeteriesTable cemeteries = $CemeteriesTable(this);
  late final $GravesTable graves = $GravesTable(this);
  late final $BurialsTable burials = $BurialsTable(this);
  late final $MediaTable media = $MediaTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    persons,
    families,
    familyPartners,
    familyChildren,
    events,
    cemeteries,
    graves,
    burials,
    media,
    settings,
  ];
}

typedef $$PersonsTableCreateCompanionBuilder =
    PersonsCompanion Function({
      Value<int> id,
      Value<String?> givenNames,
      Value<String?> surname,
      Value<String?> birthSurname,
      Value<String?> bio,
      Value<String?> bioSource,
      Value<bool> isLiving,
    });
typedef $$PersonsTableUpdateCompanionBuilder =
    PersonsCompanion Function({
      Value<int> id,
      Value<String?> givenNames,
      Value<String?> surname,
      Value<String?> birthSurname,
      Value<String?> bio,
      Value<String?> bioSource,
      Value<bool> isLiving,
    });

final class $$PersonsTableReferences
    extends BaseReferences<_$GrobingDatabase, $PersonsTable, Person> {
  $$PersonsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FamilyPartnersTable, List<FamilyPartner>>
  _familyPartnersRefsTable(_$GrobingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.familyPartners,
        aliasName: 'persons__id__family_partners__person_id',
      );

  $$FamilyPartnersTableProcessedTableManager get familyPartnersRefs {
    final manager = $$FamilyPartnersTableTableManager(
      $_db,
      $_db.familyPartners,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_familyPartnersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FamilyChildrenTable, List<FamilyChildrenData>>
  _familyChildrenRefsTable(_$GrobingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.familyChildren,
        aliasName: 'persons__id__family_children__person_id',
      );

  $$FamilyChildrenTableProcessedTableManager get familyChildrenRefs {
    final manager = $$FamilyChildrenTableTableManager(
      $_db,
      $_db.familyChildren,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_familyChildrenRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EventsTable, List<Event>> _eventsRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.events,
    aliasName: 'persons__id__events__person_id',
  );

  $$EventsTableProcessedTableManager get eventsRefs {
    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_eventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BurialsTable, List<Burial>> _burialsRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.burials,
    aliasName: 'persons__id__burials__person_id',
  );

  $$BurialsTableProcessedTableManager get burialsRefs {
    final manager = $$BurialsTableTableManager(
      $_db,
      $_db.burials,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_burialsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MediaTable, List<MediaFile>> _mediaRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.media,
    aliasName: 'persons__id__media__person_id',
  );

  $$MediaTableProcessedTableManager get mediaRefs {
    final manager = $$MediaTableTableManager(
      $_db,
      $_db.media,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SettingsTable, List<Setting>> _settingsRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.settings,
    aliasName: 'persons__id__settings__me_person_id',
  );

  $$SettingsTableProcessedTableManager get settingsRefs {
    final manager = $$SettingsTableTableManager(
      $_db,
      $_db.settings,
    ).filter((f) => f.mePersonId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_settingsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PersonsTableFilterComposer
    extends Composer<_$GrobingDatabase, $PersonsTable> {
  $$PersonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get givenNames => $composableBuilder(
    column: $table.givenNames,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get surname => $composableBuilder(
    column: $table.surname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get birthSurname => $composableBuilder(
    column: $table.birthSurname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bioSource => $composableBuilder(
    column: $table.bioSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLiving => $composableBuilder(
    column: $table.isLiving,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> familyPartnersRefs(
    Expression<bool> Function($$FamilyPartnersTableFilterComposer f) f,
  ) {
    final $$FamilyPartnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyPartners,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyPartnersTableFilterComposer(
            $db: $db,
            $table: $db.familyPartners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> familyChildrenRefs(
    Expression<bool> Function($$FamilyChildrenTableFilterComposer f) f,
  ) {
    final $$FamilyChildrenTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyChildren,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyChildrenTableFilterComposer(
            $db: $db,
            $table: $db.familyChildren,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> eventsRefs(
    Expression<bool> Function($$EventsTableFilterComposer f) f,
  ) {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> burialsRefs(
    Expression<bool> Function($$BurialsTableFilterComposer f) f,
  ) {
    final $$BurialsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.burials,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BurialsTableFilterComposer(
            $db: $db,
            $table: $db.burials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mediaRefs(
    Expression<bool> Function($$MediaTableFilterComposer f) f,
  ) {
    final $$MediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableFilterComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> settingsRefs(
    Expression<bool> Function($$SettingsTableFilterComposer f) f,
  ) {
    final $$SettingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.settings,
      getReferencedColumn: (t) => t.mePersonId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SettingsTableFilterComposer(
            $db: $db,
            $table: $db.settings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PersonsTableOrderingComposer
    extends Composer<_$GrobingDatabase, $PersonsTable> {
  $$PersonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get givenNames => $composableBuilder(
    column: $table.givenNames,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get surname => $composableBuilder(
    column: $table.surname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get birthSurname => $composableBuilder(
    column: $table.birthSurname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bioSource => $composableBuilder(
    column: $table.bioSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLiving => $composableBuilder(
    column: $table.isLiving,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonsTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $PersonsTable> {
  $$PersonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get givenNames => $composableBuilder(
    column: $table.givenNames,
    builder: (column) => column,
  );

  GeneratedColumn<String> get surname =>
      $composableBuilder(column: $table.surname, builder: (column) => column);

  GeneratedColumn<String> get birthSurname => $composableBuilder(
    column: $table.birthSurname,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bio =>
      $composableBuilder(column: $table.bio, builder: (column) => column);

  GeneratedColumn<String> get bioSource =>
      $composableBuilder(column: $table.bioSource, builder: (column) => column);

  GeneratedColumn<bool> get isLiving =>
      $composableBuilder(column: $table.isLiving, builder: (column) => column);

  Expression<T> familyPartnersRefs<T extends Object>(
    Expression<T> Function($$FamilyPartnersTableAnnotationComposer a) f,
  ) {
    final $$FamilyPartnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyPartners,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyPartnersTableAnnotationComposer(
            $db: $db,
            $table: $db.familyPartners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> familyChildrenRefs<T extends Object>(
    Expression<T> Function($$FamilyChildrenTableAnnotationComposer a) f,
  ) {
    final $$FamilyChildrenTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyChildren,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyChildrenTableAnnotationComposer(
            $db: $db,
            $table: $db.familyChildren,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> eventsRefs<T extends Object>(
    Expression<T> Function($$EventsTableAnnotationComposer a) f,
  ) {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> burialsRefs<T extends Object>(
    Expression<T> Function($$BurialsTableAnnotationComposer a) f,
  ) {
    final $$BurialsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.burials,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BurialsTableAnnotationComposer(
            $db: $db,
            $table: $db.burials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mediaRefs<T extends Object>(
    Expression<T> Function($$MediaTableAnnotationComposer a) f,
  ) {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableAnnotationComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> settingsRefs<T extends Object>(
    Expression<T> Function($$SettingsTableAnnotationComposer a) f,
  ) {
    final $$SettingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.settings,
      getReferencedColumn: (t) => t.mePersonId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SettingsTableAnnotationComposer(
            $db: $db,
            $table: $db.settings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PersonsTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $PersonsTable,
          Person,
          $$PersonsTableFilterComposer,
          $$PersonsTableOrderingComposer,
          $$PersonsTableAnnotationComposer,
          $$PersonsTableCreateCompanionBuilder,
          $$PersonsTableUpdateCompanionBuilder,
          (Person, $$PersonsTableReferences),
          Person,
          PrefetchHooks Function({
            bool familyPartnersRefs,
            bool familyChildrenRefs,
            bool eventsRefs,
            bool burialsRefs,
            bool mediaRefs,
            bool settingsRefs,
          })
        > {
  $$PersonsTableTableManager(_$GrobingDatabase db, $PersonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> givenNames = const Value.absent(),
                Value<String?> surname = const Value.absent(),
                Value<String?> birthSurname = const Value.absent(),
                Value<String?> bio = const Value.absent(),
                Value<String?> bioSource = const Value.absent(),
                Value<bool> isLiving = const Value.absent(),
              }) => PersonsCompanion(
                id: id,
                givenNames: givenNames,
                surname: surname,
                birthSurname: birthSurname,
                bio: bio,
                bioSource: bioSource,
                isLiving: isLiving,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> givenNames = const Value.absent(),
                Value<String?> surname = const Value.absent(),
                Value<String?> birthSurname = const Value.absent(),
                Value<String?> bio = const Value.absent(),
                Value<String?> bioSource = const Value.absent(),
                Value<bool> isLiving = const Value.absent(),
              }) => PersonsCompanion.insert(
                id: id,
                givenNames: givenNames,
                surname: surname,
                birthSurname: birthSurname,
                bio: bio,
                bioSource: bioSource,
                isLiving: isLiving,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PersonsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                familyPartnersRefs = false,
                familyChildrenRefs = false,
                eventsRefs = false,
                burialsRefs = false,
                mediaRefs = false,
                settingsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (familyPartnersRefs) db.familyPartners,
                    if (familyChildrenRefs) db.familyChildren,
                    if (eventsRefs) db.events,
                    if (burialsRefs) db.burials,
                    if (mediaRefs) db.media,
                    if (settingsRefs) db.settings,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (familyPartnersRefs)
                        await $_getPrefetchedData<
                          Person,
                          $PersonsTable,
                          FamilyPartner
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._familyPartnersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).familyPartnersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (familyChildrenRefs)
                        await $_getPrefetchedData<
                          Person,
                          $PersonsTable,
                          FamilyChildrenData
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._familyChildrenRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).familyChildrenRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (eventsRefs)
                        await $_getPrefetchedData<Person, $PersonsTable, Event>(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._eventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).eventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (burialsRefs)
                        await $_getPrefetchedData<
                          Person,
                          $PersonsTable,
                          Burial
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._burialsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).burialsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mediaRefs)
                        await $_getPrefetchedData<
                          Person,
                          $PersonsTable,
                          MediaFile
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._mediaRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(db, table, p0).mediaRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (settingsRefs)
                        await $_getPrefetchedData<
                          Person,
                          $PersonsTable,
                          Setting
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._settingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).settingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mePersonId == item.id,
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

typedef $$PersonsTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $PersonsTable,
      Person,
      $$PersonsTableFilterComposer,
      $$PersonsTableOrderingComposer,
      $$PersonsTableAnnotationComposer,
      $$PersonsTableCreateCompanionBuilder,
      $$PersonsTableUpdateCompanionBuilder,
      (Person, $$PersonsTableReferences),
      Person,
      PrefetchHooks Function({
        bool familyPartnersRefs,
        bool familyChildrenRefs,
        bool eventsRefs,
        bool burialsRefs,
        bool mediaRefs,
        bool settingsRefs,
      })
    >;
typedef $$FamiliesTableCreateCompanionBuilder =
    FamiliesCompanion Function({Value<int> id});
typedef $$FamiliesTableUpdateCompanionBuilder =
    FamiliesCompanion Function({Value<int> id});

final class $$FamiliesTableReferences
    extends BaseReferences<_$GrobingDatabase, $FamiliesTable, Family> {
  $$FamiliesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FamilyPartnersTable, List<FamilyPartner>>
  _familyPartnersRefsTable(_$GrobingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.familyPartners,
        aliasName: 'families__id__family_partners__family_id',
      );

  $$FamilyPartnersTableProcessedTableManager get familyPartnersRefs {
    final manager = $$FamilyPartnersTableTableManager(
      $_db,
      $_db.familyPartners,
    ).filter((f) => f.familyId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_familyPartnersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FamilyChildrenTable, List<FamilyChildrenData>>
  _familyChildrenRefsTable(_$GrobingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.familyChildren,
        aliasName: 'families__id__family_children__family_id',
      );

  $$FamilyChildrenTableProcessedTableManager get familyChildrenRefs {
    final manager = $$FamilyChildrenTableTableManager(
      $_db,
      $_db.familyChildren,
    ).filter((f) => f.familyId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_familyChildrenRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EventsTable, List<Event>> _eventsRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.events,
    aliasName: 'families__id__events__family_id',
  );

  $$EventsTableProcessedTableManager get eventsRefs {
    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.familyId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_eventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FamiliesTableFilterComposer
    extends Composer<_$GrobingDatabase, $FamiliesTable> {
  $$FamiliesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> familyPartnersRefs(
    Expression<bool> Function($$FamilyPartnersTableFilterComposer f) f,
  ) {
    final $$FamilyPartnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyPartners,
      getReferencedColumn: (t) => t.familyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyPartnersTableFilterComposer(
            $db: $db,
            $table: $db.familyPartners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> familyChildrenRefs(
    Expression<bool> Function($$FamilyChildrenTableFilterComposer f) f,
  ) {
    final $$FamilyChildrenTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyChildren,
      getReferencedColumn: (t) => t.familyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyChildrenTableFilterComposer(
            $db: $db,
            $table: $db.familyChildren,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> eventsRefs(
    Expression<bool> Function($$EventsTableFilterComposer f) f,
  ) {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.familyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FamiliesTableOrderingComposer
    extends Composer<_$GrobingDatabase, $FamiliesTable> {
  $$FamiliesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FamiliesTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $FamiliesTable> {
  $$FamiliesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  Expression<T> familyPartnersRefs<T extends Object>(
    Expression<T> Function($$FamilyPartnersTableAnnotationComposer a) f,
  ) {
    final $$FamilyPartnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyPartners,
      getReferencedColumn: (t) => t.familyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyPartnersTableAnnotationComposer(
            $db: $db,
            $table: $db.familyPartners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> familyChildrenRefs<T extends Object>(
    Expression<T> Function($$FamilyChildrenTableAnnotationComposer a) f,
  ) {
    final $$FamilyChildrenTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.familyChildren,
      getReferencedColumn: (t) => t.familyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamilyChildrenTableAnnotationComposer(
            $db: $db,
            $table: $db.familyChildren,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> eventsRefs<T extends Object>(
    Expression<T> Function($$EventsTableAnnotationComposer a) f,
  ) {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.familyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FamiliesTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $FamiliesTable,
          Family,
          $$FamiliesTableFilterComposer,
          $$FamiliesTableOrderingComposer,
          $$FamiliesTableAnnotationComposer,
          $$FamiliesTableCreateCompanionBuilder,
          $$FamiliesTableUpdateCompanionBuilder,
          (Family, $$FamiliesTableReferences),
          Family,
          PrefetchHooks Function({
            bool familyPartnersRefs,
            bool familyChildrenRefs,
            bool eventsRefs,
          })
        > {
  $$FamiliesTableTableManager(_$GrobingDatabase db, $FamiliesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FamiliesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FamiliesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FamiliesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({Value<int> id = const Value.absent()}) =>
              FamiliesCompanion(id: id),
          createCompanionCallback: ({Value<int> id = const Value.absent()}) =>
              FamiliesCompanion.insert(id: id),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FamiliesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                familyPartnersRefs = false,
                familyChildrenRefs = false,
                eventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (familyPartnersRefs) db.familyPartners,
                    if (familyChildrenRefs) db.familyChildren,
                    if (eventsRefs) db.events,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (familyPartnersRefs)
                        await $_getPrefetchedData<
                          Family,
                          $FamiliesTable,
                          FamilyPartner
                        >(
                          currentTable: table,
                          referencedTable: $$FamiliesTableReferences
                              ._familyPartnersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FamiliesTableReferences(
                                db,
                                table,
                                p0,
                              ).familyPartnersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.familyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (familyChildrenRefs)
                        await $_getPrefetchedData<
                          Family,
                          $FamiliesTable,
                          FamilyChildrenData
                        >(
                          currentTable: table,
                          referencedTable: $$FamiliesTableReferences
                              ._familyChildrenRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FamiliesTableReferences(
                                db,
                                table,
                                p0,
                              ).familyChildrenRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.familyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (eventsRefs)
                        await $_getPrefetchedData<
                          Family,
                          $FamiliesTable,
                          Event
                        >(
                          currentTable: table,
                          referencedTable: $$FamiliesTableReferences
                              ._eventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FamiliesTableReferences(
                                db,
                                table,
                                p0,
                              ).eventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.familyId == item.id,
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

typedef $$FamiliesTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $FamiliesTable,
      Family,
      $$FamiliesTableFilterComposer,
      $$FamiliesTableOrderingComposer,
      $$FamiliesTableAnnotationComposer,
      $$FamiliesTableCreateCompanionBuilder,
      $$FamiliesTableUpdateCompanionBuilder,
      (Family, $$FamiliesTableReferences),
      Family,
      PrefetchHooks Function({
        bool familyPartnersRefs,
        bool familyChildrenRefs,
        bool eventsRefs,
      })
    >;
typedef $$FamilyPartnersTableCreateCompanionBuilder =
    FamilyPartnersCompanion Function({
      required int familyId,
      required int personId,
      Value<int> rowid,
    });
typedef $$FamilyPartnersTableUpdateCompanionBuilder =
    FamilyPartnersCompanion Function({
      Value<int> familyId,
      Value<int> personId,
      Value<int> rowid,
    });

final class $$FamilyPartnersTableReferences
    extends
        BaseReferences<_$GrobingDatabase, $FamilyPartnersTable, FamilyPartner> {
  $$FamilyPartnersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FamiliesTable _familyIdTable(_$GrobingDatabase db) =>
      db.families.createAlias('family_partners__family_id__families__id');

  $$FamiliesTableProcessedTableManager get familyId {
    final $_column = $_itemColumn<int>('family_id')!;

    final manager = $$FamiliesTableTableManager(
      $_db,
      $_db.families,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_familyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$GrobingDatabase db) =>
      db.persons.createAlias('family_partners__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FamilyPartnersTableFilterComposer
    extends Composer<_$GrobingDatabase, $FamilyPartnersTable> {
  $$FamilyPartnersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FamiliesTableFilterComposer get familyId {
    final $$FamiliesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableFilterComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FamilyPartnersTableOrderingComposer
    extends Composer<_$GrobingDatabase, $FamilyPartnersTable> {
  $$FamilyPartnersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FamiliesTableOrderingComposer get familyId {
    final $$FamiliesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableOrderingComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FamilyPartnersTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $FamilyPartnersTable> {
  $$FamilyPartnersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FamiliesTableAnnotationComposer get familyId {
    final $$FamiliesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableAnnotationComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FamilyPartnersTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $FamilyPartnersTable,
          FamilyPartner,
          $$FamilyPartnersTableFilterComposer,
          $$FamilyPartnersTableOrderingComposer,
          $$FamilyPartnersTableAnnotationComposer,
          $$FamilyPartnersTableCreateCompanionBuilder,
          $$FamilyPartnersTableUpdateCompanionBuilder,
          (FamilyPartner, $$FamilyPartnersTableReferences),
          FamilyPartner,
          PrefetchHooks Function({bool familyId, bool personId})
        > {
  $$FamilyPartnersTableTableManager(
    _$GrobingDatabase db,
    $FamilyPartnersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FamilyPartnersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FamilyPartnersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FamilyPartnersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> familyId = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FamilyPartnersCompanion(
                familyId: familyId,
                personId: personId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int familyId,
                required int personId,
                Value<int> rowid = const Value.absent(),
              }) => FamilyPartnersCompanion.insert(
                familyId: familyId,
                personId: personId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FamilyPartnersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({familyId = false, personId = false}) {
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
                    if (familyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.familyId,
                                referencedTable: $$FamilyPartnersTableReferences
                                    ._familyIdTable(db),
                                referencedColumn:
                                    $$FamilyPartnersTableReferences
                                        ._familyIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$FamilyPartnersTableReferences
                                    ._personIdTable(db),
                                referencedColumn:
                                    $$FamilyPartnersTableReferences
                                        ._personIdTable(db)
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

typedef $$FamilyPartnersTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $FamilyPartnersTable,
      FamilyPartner,
      $$FamilyPartnersTableFilterComposer,
      $$FamilyPartnersTableOrderingComposer,
      $$FamilyPartnersTableAnnotationComposer,
      $$FamilyPartnersTableCreateCompanionBuilder,
      $$FamilyPartnersTableUpdateCompanionBuilder,
      (FamilyPartner, $$FamilyPartnersTableReferences),
      FamilyPartner,
      PrefetchHooks Function({bool familyId, bool personId})
    >;
typedef $$FamilyChildrenTableCreateCompanionBuilder =
    FamilyChildrenCompanion Function({
      required int familyId,
      required int personId,
      Value<int> rowid,
    });
typedef $$FamilyChildrenTableUpdateCompanionBuilder =
    FamilyChildrenCompanion Function({
      Value<int> familyId,
      Value<int> personId,
      Value<int> rowid,
    });

final class $$FamilyChildrenTableReferences
    extends
        BaseReferences<
          _$GrobingDatabase,
          $FamilyChildrenTable,
          FamilyChildrenData
        > {
  $$FamilyChildrenTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FamiliesTable _familyIdTable(_$GrobingDatabase db) =>
      db.families.createAlias('family_children__family_id__families__id');

  $$FamiliesTableProcessedTableManager get familyId {
    final $_column = $_itemColumn<int>('family_id')!;

    final manager = $$FamiliesTableTableManager(
      $_db,
      $_db.families,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_familyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$GrobingDatabase db) =>
      db.persons.createAlias('family_children__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FamilyChildrenTableFilterComposer
    extends Composer<_$GrobingDatabase, $FamilyChildrenTable> {
  $$FamilyChildrenTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FamiliesTableFilterComposer get familyId {
    final $$FamiliesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableFilterComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FamilyChildrenTableOrderingComposer
    extends Composer<_$GrobingDatabase, $FamilyChildrenTable> {
  $$FamilyChildrenTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FamiliesTableOrderingComposer get familyId {
    final $$FamiliesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableOrderingComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FamilyChildrenTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $FamilyChildrenTable> {
  $$FamilyChildrenTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FamiliesTableAnnotationComposer get familyId {
    final $$FamiliesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableAnnotationComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FamilyChildrenTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $FamilyChildrenTable,
          FamilyChildrenData,
          $$FamilyChildrenTableFilterComposer,
          $$FamilyChildrenTableOrderingComposer,
          $$FamilyChildrenTableAnnotationComposer,
          $$FamilyChildrenTableCreateCompanionBuilder,
          $$FamilyChildrenTableUpdateCompanionBuilder,
          (FamilyChildrenData, $$FamilyChildrenTableReferences),
          FamilyChildrenData,
          PrefetchHooks Function({bool familyId, bool personId})
        > {
  $$FamilyChildrenTableTableManager(
    _$GrobingDatabase db,
    $FamilyChildrenTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FamilyChildrenTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FamilyChildrenTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FamilyChildrenTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> familyId = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FamilyChildrenCompanion(
                familyId: familyId,
                personId: personId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int familyId,
                required int personId,
                Value<int> rowid = const Value.absent(),
              }) => FamilyChildrenCompanion.insert(
                familyId: familyId,
                personId: personId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FamilyChildrenTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({familyId = false, personId = false}) {
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
                    if (familyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.familyId,
                                referencedTable: $$FamilyChildrenTableReferences
                                    ._familyIdTable(db),
                                referencedColumn:
                                    $$FamilyChildrenTableReferences
                                        ._familyIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$FamilyChildrenTableReferences
                                    ._personIdTable(db),
                                referencedColumn:
                                    $$FamilyChildrenTableReferences
                                        ._personIdTable(db)
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

typedef $$FamilyChildrenTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $FamilyChildrenTable,
      FamilyChildrenData,
      $$FamilyChildrenTableFilterComposer,
      $$FamilyChildrenTableOrderingComposer,
      $$FamilyChildrenTableAnnotationComposer,
      $$FamilyChildrenTableCreateCompanionBuilder,
      $$FamilyChildrenTableUpdateCompanionBuilder,
      (FamilyChildrenData, $$FamilyChildrenTableReferences),
      FamilyChildrenData,
      PrefetchHooks Function({bool familyId, bool personId})
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      required EventType type,
      Value<int?> personId,
      Value<int?> familyId,
      Value<DateQualifier?> qualifier,
      Value<int?> year,
      Value<int?> month,
      Value<int?> day,
      Value<int?> yearTo,
      Value<int?> monthTo,
      Value<int?> dayTo,
      Value<String?> place,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      Value<EventType> type,
      Value<int?> personId,
      Value<int?> familyId,
      Value<DateQualifier?> qualifier,
      Value<int?> year,
      Value<int?> month,
      Value<int?> day,
      Value<int?> yearTo,
      Value<int?> monthTo,
      Value<int?> dayTo,
      Value<String?> place,
    });

final class $$EventsTableReferences
    extends BaseReferences<_$GrobingDatabase, $EventsTable, Event> {
  $$EventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$GrobingDatabase db) =>
      db.persons.createAlias('events__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FamiliesTable _familyIdTable(_$GrobingDatabase db) =>
      db.families.createAlias('events__family_id__families__id');

  $$FamiliesTableProcessedTableManager? get familyId {
    final $_column = $_itemColumn<int>('family_id');
    if ($_column == null) return null;
    final manager = $$FamiliesTableTableManager(
      $_db,
      $_db.families,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_familyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EventsTableFilterComposer
    extends Composer<_$GrobingDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EventType, EventType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateQualifier?, DateQualifier, String>
  get qualifier => $composableBuilder(
    column: $table.qualifier,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get yearTo => $composableBuilder(
    column: $table.yearTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get monthTo => $composableBuilder(
    column: $table.monthTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayTo => $composableBuilder(
    column: $table.dayTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get place => $composableBuilder(
    column: $table.place,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FamiliesTableFilterComposer get familyId {
    final $$FamiliesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableFilterComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventsTableOrderingComposer
    extends Composer<_$GrobingDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qualifier => $composableBuilder(
    column: $table.qualifier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get yearTo => $composableBuilder(
    column: $table.yearTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get monthTo => $composableBuilder(
    column: $table.monthTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayTo => $composableBuilder(
    column: $table.dayTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get place => $composableBuilder(
    column: $table.place,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FamiliesTableOrderingComposer get familyId {
    final $$FamiliesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableOrderingComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventsTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EventType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateQualifier?, String> get qualifier =>
      $composableBuilder(column: $table.qualifier, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<int> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get yearTo =>
      $composableBuilder(column: $table.yearTo, builder: (column) => column);

  GeneratedColumn<int> get monthTo =>
      $composableBuilder(column: $table.monthTo, builder: (column) => column);

  GeneratedColumn<int> get dayTo =>
      $composableBuilder(column: $table.dayTo, builder: (column) => column);

  GeneratedColumn<String> get place =>
      $composableBuilder(column: $table.place, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FamiliesTableAnnotationComposer get familyId {
    final $$FamiliesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.familyId,
      referencedTable: $db.families,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FamiliesTableAnnotationComposer(
            $db: $db,
            $table: $db.families,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, $$EventsTableReferences),
          Event,
          PrefetchHooks Function({bool personId, bool familyId})
        > {
  $$EventsTableTableManager(_$GrobingDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<EventType> type = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<int?> familyId = const Value.absent(),
                Value<DateQualifier?> qualifier = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> month = const Value.absent(),
                Value<int?> day = const Value.absent(),
                Value<int?> yearTo = const Value.absent(),
                Value<int?> monthTo = const Value.absent(),
                Value<int?> dayTo = const Value.absent(),
                Value<String?> place = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                type: type,
                personId: personId,
                familyId: familyId,
                qualifier: qualifier,
                year: year,
                month: month,
                day: day,
                yearTo: yearTo,
                monthTo: monthTo,
                dayTo: dayTo,
                place: place,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required EventType type,
                Value<int?> personId = const Value.absent(),
                Value<int?> familyId = const Value.absent(),
                Value<DateQualifier?> qualifier = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> month = const Value.absent(),
                Value<int?> day = const Value.absent(),
                Value<int?> yearTo = const Value.absent(),
                Value<int?> monthTo = const Value.absent(),
                Value<int?> dayTo = const Value.absent(),
                Value<String?> place = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                type: type,
                personId: personId,
                familyId: familyId,
                qualifier: qualifier,
                year: year,
                month: month,
                day: day,
                yearTo: yearTo,
                monthTo: monthTo,
                dayTo: dayTo,
                place: place,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$EventsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({personId = false, familyId = false}) {
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
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$EventsTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$EventsTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (familyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.familyId,
                                referencedTable: $$EventsTableReferences
                                    ._familyIdTable(db),
                                referencedColumn: $$EventsTableReferences
                                    ._familyIdTable(db)
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

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, $$EventsTableReferences),
      Event,
      PrefetchHooks Function({bool personId, bool familyId})
    >;
typedef $$CemeteriesTableCreateCompanionBuilder =
    CemeteriesCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> locality,
      Value<double?> centerLat,
      Value<double?> centerLon,
      Value<String?> grobonetUrl,
    });
typedef $$CemeteriesTableUpdateCompanionBuilder =
    CemeteriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> locality,
      Value<double?> centerLat,
      Value<double?> centerLon,
      Value<String?> grobonetUrl,
    });

final class $$CemeteriesTableReferences
    extends BaseReferences<_$GrobingDatabase, $CemeteriesTable, Cemetery> {
  $$CemeteriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GravesTable, List<Grave>> _gravesRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.graves,
    aliasName: 'cemeteries__id__graves__cemetery_id',
  );

  $$GravesTableProcessedTableManager get gravesRefs {
    final manager = $$GravesTableTableManager(
      $_db,
      $_db.graves,
    ).filter((f) => f.cemeteryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_gravesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CemeteriesTableFilterComposer
    extends Composer<_$GrobingDatabase, $CemeteriesTable> {
  $$CemeteriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locality => $composableBuilder(
    column: $table.locality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLat => $composableBuilder(
    column: $table.centerLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLon => $composableBuilder(
    column: $table.centerLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grobonetUrl => $composableBuilder(
    column: $table.grobonetUrl,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> gravesRefs(
    Expression<bool> Function($$GravesTableFilterComposer f) f,
  ) {
    final $$GravesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.cemeteryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableFilterComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CemeteriesTableOrderingComposer
    extends Composer<_$GrobingDatabase, $CemeteriesTable> {
  $$CemeteriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locality => $composableBuilder(
    column: $table.locality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLat => $composableBuilder(
    column: $table.centerLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLon => $composableBuilder(
    column: $table.centerLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grobonetUrl => $composableBuilder(
    column: $table.grobonetUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CemeteriesTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $CemeteriesTable> {
  $$CemeteriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get locality =>
      $composableBuilder(column: $table.locality, builder: (column) => column);

  GeneratedColumn<double> get centerLat =>
      $composableBuilder(column: $table.centerLat, builder: (column) => column);

  GeneratedColumn<double> get centerLon =>
      $composableBuilder(column: $table.centerLon, builder: (column) => column);

  GeneratedColumn<String> get grobonetUrl => $composableBuilder(
    column: $table.grobonetUrl,
    builder: (column) => column,
  );

  Expression<T> gravesRefs<T extends Object>(
    Expression<T> Function($$GravesTableAnnotationComposer a) f,
  ) {
    final $$GravesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.cemeteryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableAnnotationComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CemeteriesTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $CemeteriesTable,
          Cemetery,
          $$CemeteriesTableFilterComposer,
          $$CemeteriesTableOrderingComposer,
          $$CemeteriesTableAnnotationComposer,
          $$CemeteriesTableCreateCompanionBuilder,
          $$CemeteriesTableUpdateCompanionBuilder,
          (Cemetery, $$CemeteriesTableReferences),
          Cemetery,
          PrefetchHooks Function({bool gravesRefs})
        > {
  $$CemeteriesTableTableManager(_$GrobingDatabase db, $CemeteriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CemeteriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CemeteriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CemeteriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> locality = const Value.absent(),
                Value<double?> centerLat = const Value.absent(),
                Value<double?> centerLon = const Value.absent(),
                Value<String?> grobonetUrl = const Value.absent(),
              }) => CemeteriesCompanion(
                id: id,
                name: name,
                locality: locality,
                centerLat: centerLat,
                centerLon: centerLon,
                grobonetUrl: grobonetUrl,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> locality = const Value.absent(),
                Value<double?> centerLat = const Value.absent(),
                Value<double?> centerLon = const Value.absent(),
                Value<String?> grobonetUrl = const Value.absent(),
              }) => CemeteriesCompanion.insert(
                id: id,
                name: name,
                locality: locality,
                centerLat: centerLat,
                centerLon: centerLon,
                grobonetUrl: grobonetUrl,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CemeteriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({gravesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (gravesRefs) db.graves],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (gravesRefs)
                    await $_getPrefetchedData<
                      Cemetery,
                      $CemeteriesTable,
                      Grave
                    >(
                      currentTable: table,
                      referencedTable: $$CemeteriesTableReferences
                          ._gravesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CemeteriesTableReferences(db, table, p0).gravesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.cemeteryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CemeteriesTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $CemeteriesTable,
      Cemetery,
      $$CemeteriesTableFilterComposer,
      $$CemeteriesTableOrderingComposer,
      $$CemeteriesTableAnnotationComposer,
      $$CemeteriesTableCreateCompanionBuilder,
      $$CemeteriesTableUpdateCompanionBuilder,
      (Cemetery, $$CemeteriesTableReferences),
      Cemetery,
      PrefetchHooks Function({bool gravesRefs})
    >;
typedef $$GravesTableCreateCompanionBuilder =
    GravesCompanion Function({
      Value<int> id,
      required int cemeteryId,
      Value<String?> sector,
      Value<String?> row,
      Value<String?> plot,
      Value<double?> lat,
      Value<double?> lon,
      Value<PositionSource?> positionSource,
      Value<double?> positionAccuracyM,
    });
typedef $$GravesTableUpdateCompanionBuilder =
    GravesCompanion Function({
      Value<int> id,
      Value<int> cemeteryId,
      Value<String?> sector,
      Value<String?> row,
      Value<String?> plot,
      Value<double?> lat,
      Value<double?> lon,
      Value<PositionSource?> positionSource,
      Value<double?> positionAccuracyM,
    });

final class $$GravesTableReferences
    extends BaseReferences<_$GrobingDatabase, $GravesTable, Grave> {
  $$GravesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CemeteriesTable _cemeteryIdTable(_$GrobingDatabase db) =>
      db.cemeteries.createAlias('graves__cemetery_id__cemeteries__id');

  $$CemeteriesTableProcessedTableManager get cemeteryId {
    final $_column = $_itemColumn<int>('cemetery_id')!;

    final manager = $$CemeteriesTableTableManager(
      $_db,
      $_db.cemeteries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_cemeteryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$BurialsTable, List<Burial>> _burialsRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.burials,
    aliasName: 'graves__id__burials__grave_id',
  );

  $$BurialsTableProcessedTableManager get burialsRefs {
    final manager = $$BurialsTableTableManager(
      $_db,
      $_db.burials,
    ).filter((f) => f.graveId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_burialsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MediaTable, List<MediaFile>> _mediaRefsTable(
    _$GrobingDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.media,
    aliasName: 'graves__id__media__grave_id',
  );

  $$MediaTableProcessedTableManager get mediaRefs {
    final manager = $$MediaTableTableManager(
      $_db,
      $_db.media,
    ).filter((f) => f.graveId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GravesTableFilterComposer
    extends Composer<_$GrobingDatabase, $GravesTable> {
  $$GravesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sector => $composableBuilder(
    column: $table.sector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get row => $composableBuilder(
    column: $table.row,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PositionSource?, PositionSource, String>
  get positionSource => $composableBuilder(
    column: $table.positionSource,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<double> get positionAccuracyM => $composableBuilder(
    column: $table.positionAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  $$CemeteriesTableFilterComposer get cemeteryId {
    final $$CemeteriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cemeteryId,
      referencedTable: $db.cemeteries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CemeteriesTableFilterComposer(
            $db: $db,
            $table: $db.cemeteries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> burialsRefs(
    Expression<bool> Function($$BurialsTableFilterComposer f) f,
  ) {
    final $$BurialsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.burials,
      getReferencedColumn: (t) => t.graveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BurialsTableFilterComposer(
            $db: $db,
            $table: $db.burials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mediaRefs(
    Expression<bool> Function($$MediaTableFilterComposer f) f,
  ) {
    final $$MediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.graveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableFilterComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GravesTableOrderingComposer
    extends Composer<_$GrobingDatabase, $GravesTable> {
  $$GravesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sector => $composableBuilder(
    column: $table.sector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get row => $composableBuilder(
    column: $table.row,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plot => $composableBuilder(
    column: $table.plot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get positionSource => $composableBuilder(
    column: $table.positionSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get positionAccuracyM => $composableBuilder(
    column: $table.positionAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  $$CemeteriesTableOrderingComposer get cemeteryId {
    final $$CemeteriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cemeteryId,
      referencedTable: $db.cemeteries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CemeteriesTableOrderingComposer(
            $db: $db,
            $table: $db.cemeteries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GravesTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $GravesTable> {
  $$GravesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sector =>
      $composableBuilder(column: $table.sector, builder: (column) => column);

  GeneratedColumn<String> get row =>
      $composableBuilder(column: $table.row, builder: (column) => column);

  GeneratedColumn<String> get plot =>
      $composableBuilder(column: $table.plot, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PositionSource?, String>
  get positionSource => $composableBuilder(
    column: $table.positionSource,
    builder: (column) => column,
  );

  GeneratedColumn<double> get positionAccuracyM => $composableBuilder(
    column: $table.positionAccuracyM,
    builder: (column) => column,
  );

  $$CemeteriesTableAnnotationComposer get cemeteryId {
    final $$CemeteriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cemeteryId,
      referencedTable: $db.cemeteries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CemeteriesTableAnnotationComposer(
            $db: $db,
            $table: $db.cemeteries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> burialsRefs<T extends Object>(
    Expression<T> Function($$BurialsTableAnnotationComposer a) f,
  ) {
    final $$BurialsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.burials,
      getReferencedColumn: (t) => t.graveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BurialsTableAnnotationComposer(
            $db: $db,
            $table: $db.burials,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mediaRefs<T extends Object>(
    Expression<T> Function($$MediaTableAnnotationComposer a) f,
  ) {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.graveId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableAnnotationComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GravesTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $GravesTable,
          Grave,
          $$GravesTableFilterComposer,
          $$GravesTableOrderingComposer,
          $$GravesTableAnnotationComposer,
          $$GravesTableCreateCompanionBuilder,
          $$GravesTableUpdateCompanionBuilder,
          (Grave, $$GravesTableReferences),
          Grave,
          PrefetchHooks Function({
            bool cemeteryId,
            bool burialsRefs,
            bool mediaRefs,
          })
        > {
  $$GravesTableTableManager(_$GrobingDatabase db, $GravesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GravesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GravesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GravesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> cemeteryId = const Value.absent(),
                Value<String?> sector = const Value.absent(),
                Value<String?> row = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lon = const Value.absent(),
                Value<PositionSource?> positionSource = const Value.absent(),
                Value<double?> positionAccuracyM = const Value.absent(),
              }) => GravesCompanion(
                id: id,
                cemeteryId: cemeteryId,
                sector: sector,
                row: row,
                plot: plot,
                lat: lat,
                lon: lon,
                positionSource: positionSource,
                positionAccuracyM: positionAccuracyM,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int cemeteryId,
                Value<String?> sector = const Value.absent(),
                Value<String?> row = const Value.absent(),
                Value<String?> plot = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lon = const Value.absent(),
                Value<PositionSource?> positionSource = const Value.absent(),
                Value<double?> positionAccuracyM = const Value.absent(),
              }) => GravesCompanion.insert(
                id: id,
                cemeteryId: cemeteryId,
                sector: sector,
                row: row,
                plot: plot,
                lat: lat,
                lon: lon,
                positionSource: positionSource,
                positionAccuracyM: positionAccuracyM,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$GravesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({cemeteryId = false, burialsRefs = false, mediaRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (burialsRefs) db.burials,
                    if (mediaRefs) db.media,
                  ],
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
                        if (cemeteryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.cemeteryId,
                                    referencedTable: $$GravesTableReferences
                                        ._cemeteryIdTable(db),
                                    referencedColumn: $$GravesTableReferences
                                        ._cemeteryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (burialsRefs)
                        await $_getPrefetchedData<Grave, $GravesTable, Burial>(
                          currentTable: table,
                          referencedTable: $$GravesTableReferences
                              ._burialsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GravesTableReferences(
                                db,
                                table,
                                p0,
                              ).burialsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.graveId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mediaRefs)
                        await $_getPrefetchedData<
                          Grave,
                          $GravesTable,
                          MediaFile
                        >(
                          currentTable: table,
                          referencedTable: $$GravesTableReferences
                              ._mediaRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GravesTableReferences(db, table, p0).mediaRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.graveId == item.id,
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

typedef $$GravesTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $GravesTable,
      Grave,
      $$GravesTableFilterComposer,
      $$GravesTableOrderingComposer,
      $$GravesTableAnnotationComposer,
      $$GravesTableCreateCompanionBuilder,
      $$GravesTableUpdateCompanionBuilder,
      (Grave, $$GravesTableReferences),
      Grave,
      PrefetchHooks Function({
        bool cemeteryId,
        bool burialsRefs,
        bool mediaRefs,
      })
    >;
typedef $$BurialsTableCreateCompanionBuilder =
    BurialsCompanion Function({
      required int personId,
      required int graveId,
      Value<int> rowid,
    });
typedef $$BurialsTableUpdateCompanionBuilder =
    BurialsCompanion Function({
      Value<int> personId,
      Value<int> graveId,
      Value<int> rowid,
    });

final class $$BurialsTableReferences
    extends BaseReferences<_$GrobingDatabase, $BurialsTable, Burial> {
  $$BurialsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$GrobingDatabase db) =>
      db.persons.createAlias('burials__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $GravesTable _graveIdTable(_$GrobingDatabase db) =>
      db.graves.createAlias('burials__grave_id__graves__id');

  $$GravesTableProcessedTableManager get graveId {
    final $_column = $_itemColumn<int>('grave_id')!;

    final manager = $$GravesTableTableManager(
      $_db,
      $_db.graves,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_graveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BurialsTableFilterComposer
    extends Composer<_$GrobingDatabase, $BurialsTable> {
  $$BurialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GravesTableFilterComposer get graveId {
    final $$GravesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.graveId,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableFilterComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BurialsTableOrderingComposer
    extends Composer<_$GrobingDatabase, $BurialsTable> {
  $$BurialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GravesTableOrderingComposer get graveId {
    final $$GravesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.graveId,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableOrderingComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BurialsTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $BurialsTable> {
  $$BurialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GravesTableAnnotationComposer get graveId {
    final $$GravesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.graveId,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableAnnotationComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BurialsTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $BurialsTable,
          Burial,
          $$BurialsTableFilterComposer,
          $$BurialsTableOrderingComposer,
          $$BurialsTableAnnotationComposer,
          $$BurialsTableCreateCompanionBuilder,
          $$BurialsTableUpdateCompanionBuilder,
          (Burial, $$BurialsTableReferences),
          Burial,
          PrefetchHooks Function({bool personId, bool graveId})
        > {
  $$BurialsTableTableManager(_$GrobingDatabase db, $BurialsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BurialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BurialsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BurialsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> personId = const Value.absent(),
                Value<int> graveId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BurialsCompanion(
                personId: personId,
                graveId: graveId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int personId,
                required int graveId,
                Value<int> rowid = const Value.absent(),
              }) => BurialsCompanion.insert(
                personId: personId,
                graveId: graveId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BurialsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({personId = false, graveId = false}) {
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
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$BurialsTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$BurialsTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (graveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.graveId,
                                referencedTable: $$BurialsTableReferences
                                    ._graveIdTable(db),
                                referencedColumn: $$BurialsTableReferences
                                    ._graveIdTable(db)
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

typedef $$BurialsTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $BurialsTable,
      Burial,
      $$BurialsTableFilterComposer,
      $$BurialsTableOrderingComposer,
      $$BurialsTableAnnotationComposer,
      $$BurialsTableCreateCompanionBuilder,
      $$BurialsTableUpdateCompanionBuilder,
      (Burial, $$BurialsTableReferences),
      Burial,
      PrefetchHooks Function({bool personId, bool graveId})
    >;
typedef $$MediaTableCreateCompanionBuilder =
    MediaCompanion Function({
      Value<int> id,
      required String relativePath,
      Value<int?> personId,
      Value<int?> graveId,
    });
typedef $$MediaTableUpdateCompanionBuilder =
    MediaCompanion Function({
      Value<int> id,
      Value<String> relativePath,
      Value<int?> personId,
      Value<int?> graveId,
    });

final class $$MediaTableReferences
    extends BaseReferences<_$GrobingDatabase, $MediaTable, MediaFile> {
  $$MediaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$GrobingDatabase db) =>
      db.persons.createAlias('media__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $GravesTable _graveIdTable(_$GrobingDatabase db) =>
      db.graves.createAlias('media__grave_id__graves__id');

  $$GravesTableProcessedTableManager? get graveId {
    final $_column = $_itemColumn<int>('grave_id');
    if ($_column == null) return null;
    final manager = $$GravesTableTableManager(
      $_db,
      $_db.graves,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_graveIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MediaTableFilterComposer
    extends Composer<_$GrobingDatabase, $MediaTable> {
  $$MediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GravesTableFilterComposer get graveId {
    final $$GravesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.graveId,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableFilterComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaTableOrderingComposer
    extends Composer<_$GrobingDatabase, $MediaTable> {
  $$MediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GravesTableOrderingComposer get graveId {
    final $$GravesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.graveId,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableOrderingComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $MediaTable> {
  $$MediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GravesTableAnnotationComposer get graveId {
    final $$GravesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.graveId,
      referencedTable: $db.graves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GravesTableAnnotationComposer(
            $db: $db,
            $table: $db.graves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $MediaTable,
          MediaFile,
          $$MediaTableFilterComposer,
          $$MediaTableOrderingComposer,
          $$MediaTableAnnotationComposer,
          $$MediaTableCreateCompanionBuilder,
          $$MediaTableUpdateCompanionBuilder,
          (MediaFile, $$MediaTableReferences),
          MediaFile,
          PrefetchHooks Function({bool personId, bool graveId})
        > {
  $$MediaTableTableManager(_$GrobingDatabase db, $MediaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<int?> graveId = const Value.absent(),
              }) => MediaCompanion(
                id: id,
                relativePath: relativePath,
                personId: personId,
                graveId: graveId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String relativePath,
                Value<int?> personId = const Value.absent(),
                Value<int?> graveId = const Value.absent(),
              }) => MediaCompanion.insert(
                id: id,
                relativePath: relativePath,
                personId: personId,
                graveId: graveId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$MediaTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({personId = false, graveId = false}) {
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
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$MediaTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$MediaTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (graveId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.graveId,
                                referencedTable: $$MediaTableReferences
                                    ._graveIdTable(db),
                                referencedColumn: $$MediaTableReferences
                                    ._graveIdTable(db)
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

typedef $$MediaTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $MediaTable,
      MediaFile,
      $$MediaTableFilterComposer,
      $$MediaTableOrderingComposer,
      $$MediaTableAnnotationComposer,
      $$MediaTableCreateCompanionBuilder,
      $$MediaTableUpdateCompanionBuilder,
      (MediaFile, $$MediaTableReferences),
      MediaFile,
      PrefetchHooks Function({bool personId, bool graveId})
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({Value<int> id, Value<int?> mePersonId});
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({Value<int> id, Value<int?> mePersonId});

final class $$SettingsTableReferences
    extends BaseReferences<_$GrobingDatabase, $SettingsTable, Setting> {
  $$SettingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _mePersonIdTable(_$GrobingDatabase db) =>
      db.persons.createAlias('settings__me_person_id__persons__id');

  $$PersonsTableProcessedTableManager? get mePersonId {
    final $_column = $_itemColumn<int>('me_person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mePersonIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SettingsTableFilterComposer
    extends Composer<_$GrobingDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get mePersonId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mePersonId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SettingsTableOrderingComposer
    extends Composer<_$GrobingDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get mePersonId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mePersonId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$GrobingDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  $$PersonsTableAnnotationComposer get mePersonId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mePersonId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$GrobingDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, $$SettingsTableReferences),
          Setting,
          PrefetchHooks Function({bool mePersonId})
        > {
  $$SettingsTableTableManager(_$GrobingDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mePersonId = const Value.absent(),
              }) => SettingsCompanion(id: id, mePersonId: mePersonId),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mePersonId = const Value.absent(),
              }) => SettingsCompanion.insert(id: id, mePersonId: mePersonId),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SettingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mePersonId = false}) {
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
                    if (mePersonId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.mePersonId,
                                referencedTable: $$SettingsTableReferences
                                    ._mePersonIdTable(db),
                                referencedColumn: $$SettingsTableReferences
                                    ._mePersonIdTable(db)
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

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$GrobingDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, $$SettingsTableReferences),
      Setting,
      PrefetchHooks Function({bool mePersonId})
    >;

class $GrobingDatabaseManager {
  final _$GrobingDatabase _db;
  $GrobingDatabaseManager(this._db);
  $$PersonsTableTableManager get persons =>
      $$PersonsTableTableManager(_db, _db.persons);
  $$FamiliesTableTableManager get families =>
      $$FamiliesTableTableManager(_db, _db.families);
  $$FamilyPartnersTableTableManager get familyPartners =>
      $$FamilyPartnersTableTableManager(_db, _db.familyPartners);
  $$FamilyChildrenTableTableManager get familyChildren =>
      $$FamilyChildrenTableTableManager(_db, _db.familyChildren);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$CemeteriesTableTableManager get cemeteries =>
      $$CemeteriesTableTableManager(_db, _db.cemeteries);
  $$GravesTableTableManager get graves =>
      $$GravesTableTableManager(_db, _db.graves);
  $$BurialsTableTableManager get burials =>
      $$BurialsTableTableManager(_db, _db.burials);
  $$MediaTableTableManager get media =>
      $$MediaTableTableManager(_db, _db.media);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
