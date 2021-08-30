import 'package:collection/collection.dart' show IterableExtension;
import 'package:gql/ast.dart' as gql;
import 'package:graphql_schema/graphql_schema.dart';

/// Performs introspection over a GraphQL [schema], and returns a one,
/// containing introspective information.
///
/// [allTypes] should contain all types, not directly defined in the schema,
/// that you would like to have introspection available for.
GraphQLSchema reflectSchema(GraphQLSchema schema, List<GraphQLType> allTypes) {
  final typeType = _reflectSchemaTypes();
  final directiveType = _reflectDirectiveType();

  Set<GraphQLType>? allTypeSet;

  final schemaType = objectType('__Schema', fields: [
    field(
      'types',
      listOf(typeType),
      resolve: (_, __) => allTypeSet ??= allTypes.toSet(),
    ),
    field(
      'queryType',
      typeType,
      resolve: (_, __) => schema.queryType,
    ),
    field(
      'mutationType',
      typeType,
      resolve: (_, __) => schema.mutationType,
    ),
    field(
      'subscriptionType',
      typeType,
      resolve: (_, __) => schema.subscriptionType,
    ),
    field(
      'directives',
      listOf(directiveType).nonNullable(),
      resolve: (_, __) => <Object?>[], // TODO: Actually fetch directives
    ),
  ]);

  allTypes.addAll([
    graphQLBoolean,
    graphQLString,
    graphQLId,
    graphQLDate,
    graphQLFloat,
    graphQLInt,
    directiveType,
    typeType,
    directiveType,
    schemaType,
    _typeKindType,
    _directiveLocationType,
    _reflectFields(),
    _reflectInputValueType(),
    _reflectEnumValueType(),
  ]);

  final fields = <GraphQLObjectField<Object?, Object?, void>>[
    field(
      '__schema',
      schemaType,
      resolve: (_, __) => schemaType,
    ),
    field(
      '__type',
      typeType,
      inputs: [GraphQLFieldInput('name', graphQLString.nonNullable())],
      resolve: (_, args) {
        final name = args['name'] as String?;
        return allTypes.firstWhere(
          (t) => t.name == name,
          orElse: () => throw GraphQLException.fromMessage(
            'No type named "$name" exists.',
          ),
        );
      },
    ),
  ];

  fields.addAll(schema.queryType!.fields);

  return GraphQLSchema(
    queryType: objectType(schema.queryType!.name, fields: fields),
    mutationType: schema.mutationType,
    subscriptionType: schema.subscriptionType,
  );
}

GraphQLObjectType<GraphQLType>? _typeType;

GraphQLObjectType<GraphQLType> _reflectSchemaTypes() {
  if (_typeType == null) {
    _typeType = _createTypeType();
    _typeType!.fields.add(
      field(
        'ofType',
        _reflectSchemaTypes(),
        resolve: (type, _) {
          if (type is GraphQLListType) {
            return type.ofType;
          } else if (type is GraphQLNonNullableType) {
            return type.ofType;
          } else {
            return null;
          }
        },
      ),
    );

    _typeType!.fields.add(
      field(
        'interfaces',
        listOf(_reflectSchemaTypes().nonNullable()),
        resolve: (type, _) {
          if (type is GraphQLObjectType) {
            return type.interfaces;
          } else {
            return <GraphQLType>[];
          }
        },
      ),
    );

    _typeType!.fields.add(
      field(
        'possibleTypes',
        listOf(_reflectSchemaTypes().nonNullable()),
        resolve: (type, _) {
          if (type is GraphQLObjectType && type.isInterface) {
            return type.possibleTypes;
          } else if (type is GraphQLUnionType) {
            return type.possibleTypes;
          } else {
            return null;
          }
        },
      ),
    );

    final fieldType = _reflectFields();
    final inputValueType = _reflectInputValueType();
    GraphQLObjectField<Object?, Object?, Object?>? typeField =
        fieldType.fields.firstWhereOrNull((f) => f.name == 'type');

    if (typeField == null) {
      fieldType.fields.add(
        field(
          'type',
          _reflectSchemaTypes(),
          resolve: (f, _) => (f as GraphQLObjectField).type,
        ),
      );
    }

    typeField = inputValueType.fields.firstWhereOrNull((f) => f.name == 'type');

    if (typeField == null) {
      inputValueType.fields.add(
        field(
          'type',
          _reflectSchemaTypes(),
          resolve: (f, _) =>
              _fetchFromInputValue(f, (f) => f.type, (f) => f.type),
        ),
      );
    }
  }

  return _typeType!;
}

final GraphQLEnumType<String> _typeKindType =
    enumTypeFromStrings('__TypeKind', [
  'SCALAR',
  'OBJECT',
  'INTERFACE',
  'UNION',
  'ENUM',
  'INPUT_OBJECT',
  'LIST',
  'NON_NULL'
]);

GraphQLObjectType<GraphQLType> _createTypeType() {
  final enumValueType = _reflectEnumValueType();
  final fieldType = _reflectFields();
  final inputValueType = _reflectInputValueType();

  return objectType<GraphQLType>('__Type', fields: [
    field(
      'name',
      graphQLString,
      resolve: (type, _) => type.name,
    ),
    field(
      'description',
      graphQLString,
      resolve: (type, _) => type.description,
    ),
    field(
      'kind',
      _typeKindType,
      resolve: (type, _) {
        final t = type;

        if (t is GraphQLEnumType) {
          return 'ENUM';
        } else if (t is GraphQLScalarType) {
          return 'SCALAR';
        } else if (t is GraphQLInputObjectType) {
          return 'INPUT_OBJECT';
        } else if (t is GraphQLObjectType) {
          return t.isInterface ? 'INTERFACE' : 'OBJECT';
        } else if (t is GraphQLListType) {
          return 'LIST';
        } else if (t is GraphQLNonNullableType) {
          return 'NON_NULL';
        } else if (t is GraphQLUnionType) {
          return 'UNION';
        } else {
          throw UnsupportedError('Cannot get the kind of $t.');
        }
      },
    ),
    field(
      'fields',
      listOf(fieldType),
      inputs: [
        GraphQLFieldInput(
          'includeDeprecated',
          graphQLBoolean,
          defaultValue: false,
        ),
      ],
      resolve: (type, args) => type is GraphQLObjectType
          ? type.fields
              .where(
                (f) => !f.isDeprecated || args['includeDeprecated'] == true,
              )
              .toList()
          : null,
    ),
    field(
      'enumValues',
      listOf(enumValueType.nonNullable()),
      inputs: [
        GraphQLFieldInput(
          'includeDeprecated',
          graphQLBoolean,
          defaultValue: false,
        ),
      ],
      resolve: (obj, args) {
        if (obj is GraphQLEnumType) {
          return obj.values
              .where(
                (f) => !f.isDeprecated || args['includeDeprecated'] == true,
              )
              .toList();
        } else {
          return null;
        }
      },
    ),
    field(
      'inputFields',
      listOf(inputValueType.nonNullable()),
      resolve: (obj, _) {
        if (obj is GraphQLInputObjectType) {
          return obj.inputFields;
        }

        return null;
      },
    ),
  ]);
}

GraphQLObjectType<GraphQLObjectField>? _fieldType;

GraphQLObjectType<GraphQLObjectField> _reflectFields() {
  return _fieldType ??= _createFieldType();
}

GraphQLObjectType<GraphQLObjectField> _createFieldType() {
  final inputValueType = _reflectInputValueType();

  return objectType<GraphQLObjectField>('__Field', fields: [
    field(
      'name',
      graphQLString,
      resolve: (f, _) => f.name,
    ),
    field(
      'description',
      graphQLString,
      resolve: (f, _) => f.description,
    ),
    field(
      'isDeprecated',
      graphQLBoolean,
      resolve: (f, _) => f.isDeprecated,
    ),
    field(
      'deprecationReason',
      graphQLString,
      resolve: (f, _) => f.deprecationReason,
    ),
    field(
      'args',
      listOf(inputValueType.nonNullable()).nonNullable(),
      resolve: (f, _) => f.inputs,
    ),
  ]);
}

GraphQLObjectType<GraphQLFieldInput>? _inputValueType;

T? _fetchFromInputValue<T>(
  Object? x,
  T Function(GraphQLFieldInput) ifInput,
  T Function(GraphQLInputObjectField) ifObjectField,
) {
  if (x is GraphQLFieldInput) {
    return ifInput(x);
  } else if (x is GraphQLInputObjectField) {
    return ifObjectField(x);
  } else {
    return null;
  }
}

GraphQLObjectType<GraphQLFieldInput> _reflectInputValueType() {
  return _inputValueType ??=
      objectType<GraphQLFieldInput>('__InputValue', fields: [
    field(
      'name',
      graphQLString.nonNullable(),
      resolve: (obj, _) =>
          _fetchFromInputValue(obj, (f) => f.name, (f) => f.name),
    ),
    field(
      'description',
      graphQLString,
      resolve: (obj, _) => _fetchFromInputValue<Object?>(
          obj, (f) => f.description, (f) => f.description),
    ),
    field(
      'defaultValue',
      graphQLString,
      resolve: (obj, _) {
        return _fetchFromInputValue<Object?>(
          obj,
          (f) => f.defaultValue?.toString(),
          (f) => f.defaultValue?.toString(),
        );
      },
    ),
  ]);
}

GraphQLObjectType? _directiveType;

final GraphQLEnumType<String> _directiveLocationType =
    enumTypeFromStrings('__DirectiveLocation', [
  'QUERY',
  'MUTATION',
  'FIELD',
  'FRAGMENT_DEFINITION',
  'FRAGMENT_SPREAD',
  'INLINE_FRAGMENT'
]);

GraphQLObjectType _reflectDirectiveType() {
  final inputValueType = _reflectInputValueType();

  // TODO: What actually is this???
  return _directiveType ??=
      objectType<gql.DirectiveNode>('__Directive', fields: [
    field(
      'name',
      graphQLString.nonNullable(),
      resolve: (obj, _) => obj.name.value,
    ),
    field(
      'description',
      graphQLString,
      resolve: (obj, _) => null,
    ),
    field(
      'locations',
      listOf(_directiveLocationType.nonNullable()).nonNullable(),
      // TODO: Fetch directiveLocation
      resolve: (obj, _) => <String>[],
    ),
    field(
      'args',
      listOf(inputValueType.nonNullable()).nonNullable(),
      resolve: (obj, _) => <Map<String, Object?>>[],
    ),
  ]);
}

GraphQLObjectType? _enumValueType;

GraphQLObjectType _reflectEnumValueType() {
  return _enumValueType ??= objectType<GraphQLEnumValue>(
    '__EnumValue',
    fields: [
      field(
        'name',
        graphQLString.nonNullable(),
        resolve: (obj, _) => obj.name,
      ),
      field(
        'description',
        graphQLString,
        resolve: (obj, _) => obj.description,
      ),
      field(
        'isDeprecated',
        graphQLBoolean.nonNullable(),
        resolve: (obj, _) => obj.isDeprecated,
      ),
      field(
        'deprecationReason',
        graphQLString,
        resolve: (obj, _) => obj.deprecationReason,
      ),
    ],
  );
}

List<GraphQLType> fetchAllTypes(
    GraphQLSchema schema, List<GraphQLType> specifiedTypes) {
  final data = <GraphQLType?>{}
    ..add(schema.queryType)
    ..addAll(specifiedTypes);

  if (schema.mutationType != null) {
    data.add(schema.mutationType);
  }

  if (schema.subscriptionType != null) {
    data.add(schema.subscriptionType);
  }

  return CollectTypes(data).types.toList();
}

class CollectTypes {
  Set<GraphQLType> traversedTypes = {};

  Set<GraphQLType> get types => traversedTypes;

  CollectTypes(Iterable<GraphQLType?> types) {
    types.forEach(_fetchAllTypesFromType);
  }

  CollectTypes.fromRootObject(GraphQLObjectType type) {
    _fetchAllTypesFromObject(type);
  }

  void _fetchAllTypesFromObject(GraphQLObjectType objectType) {
    if (traversedTypes.contains(objectType)) {
      return;
    }

    traversedTypes.add(objectType);

    for (final field in objectType.fields) {
      if (field.type is GraphQLObjectType) {
        _fetchAllTypesFromObject(field.type as GraphQLObjectType);
      } else if (field.type is GraphQLInputObjectType) {
        for (final v in (field.type as GraphQLInputObjectType).inputFields) {
          _fetchAllTypesFromType(v.type);
        }
      } else {
        _fetchAllTypesFromType(field.type);
      }

      for (final input in field.inputs) {
        _fetchAllTypesFromType(input.type);
      }
    }

    for (final i in objectType.interfaces) {
      _fetchAllTypesFromObject(i);
    }
  }

  void _fetchAllTypesFromType(GraphQLType? type) {
    if (traversedTypes.contains(type)) {
      return;
    }

    /*
     * Unwrap generics
     */
    if (type is GraphQLNonNullableType) {
      return _fetchAllTypesFromType(type.ofType);
    }
    if (type is GraphQLListType) {
      return _fetchAllTypesFromType(type.ofType);
    }

    /*
     * Handle simple types
     */
    if (type is GraphQLEnumType) {
      traversedTypes.add(type);
      return;
    }
    if (type is GraphQLUnionType) {
      traversedTypes.add(type);
      for (final t in type.possibleTypes) {
        _fetchAllTypesFromType(t);
      }
      return;
    }
    if (type is GraphQLInputObjectType) {
      traversedTypes.add(type);
      for (final v in type.inputFields) {
        _fetchAllTypesFromType(v.type);
      }
      return;
    }

    /*
     * defer to object type traverser
     */
    if (type is GraphQLObjectType) {
      return _fetchAllTypesFromObject(type);
    }

    return;
  }
}
