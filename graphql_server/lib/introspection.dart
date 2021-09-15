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

  final schemaType = objectType<Object>('__Schema', fields: [
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
      listOf(directiveType).nonNull(),
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

  final fields = <GraphQLObjectField<Object, Object, Object>>[
    field(
      '__schema',
      schemaType,
      resolve: (_, __) => schemaType,
    ),
    field(
      '__type',
      typeType,
      inputs: [GraphQLFieldInput('name', graphQLString.nonNull())],
      resolve: (_, ctx) {
        final name = ctx.args['name'] as String?;
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
    serdeCtx: schema.serdeCtx,
    description: schema.description,
    directives: schema.directives,
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
          return type.whenOrNull(
            list: (type) => type.ofType,
            nonNullable: (type) => type.ofType,
          );
        },
      ),
    );

    _typeType!.fields.add(
      field(
        'interfaces',
        listOf(_reflectSchemaTypes().nonNull()),
        resolve: (type, _) => type.whenMaybe(
          object: (type) => type.interfaces,
          orElse: (_) => <GraphQLType>[],
        ),
      ),
    );

    _typeType!.fields.add(
      field(
        'possibleTypes',
        listOf(_reflectSchemaTypes().nonNull()),
        resolve: (type, _) => type.whenOrNull(
          object: (type) => type.isInterface ? type.possibleTypes : null,
          union: (type) => type.possibleTypes,
        ),
      ),
    );

    final fieldType = _reflectFields();
    final inputValueType = _reflectInputValueType();
    GraphQLObjectField<Object, Object, Object>? typeField =
        fieldType.fields.firstWhereOrNull((f) => f.name == 'type');

    if (typeField == null) {
      fieldType.fields.add(
        field(
          'type',
          _reflectSchemaTypes(),
          resolve: (f, _) => f.type,
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
      resolve: (t, _) => t.when(
        enum_: (type) => 'ENUM',
        scalar: (type) => 'SCALAR',
        object: (type) => type.isInterface ? 'INTERFACE' : 'OBJECT',
        input: (type) => 'INPUT_OBJECT',
        union: (type) => 'UNION',
        list: (type) => 'LIST',
        nonNullable: (type) => 'NON_NULL',
      ),
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
      resolve: (type, ctx) => type.whenOrNull(
        object: (type) {
          return type.fields
              .where((f) =>
                  !f.isDeprecated || ctx.args['includeDeprecated'] == true)
              .toList();
        },
      ),
    ),
    field(
      'enumValues',
      listOf(enumValueType.nonNull()),
      inputs: [
        GraphQLFieldInput(
          'includeDeprecated',
          graphQLBoolean,
          defaultValue: false,
        ),
      ],
      resolve: (type, ctx) => type.whenOrNull(
        enum_: (type) {
          return type.values
              .where(
                (f) => !f.isDeprecated || ctx.args['includeDeprecated'] == true,
              )
              .toList();
        },
      ),
    ),
    field(
      'inputFields',
      listOf(inputValueType.nonNull()),
      resolve: (obj, _) => obj.whenOrNull(input: (type) => type.inputFields),
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
      listOf(inputValueType.nonNull()).nonNull(),
      resolve: (f, _) => f.inputs,
    ),
  ]);
}

// TODO: remove
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

GraphQLObjectType<GraphQLInputField>? _inputValueType;
GraphQLObjectType<GraphQLInputField> _reflectInputValueType() {
  return _inputValueType ??= objectType('__InputValue', fields: [
    field(
      'name',
      graphQLString.nonNull(),
      resolve: (obj, _) =>
          _fetchFromInputValue(obj, (f) => f.name, (f) => f.name),
    ),
    field(
      'description',
      graphQLString,
      resolve: (obj, _) => _fetchFromInputValue<String?>(
          obj, (f) => f.description, (f) => f.description),
    ),
    field(
      'defaultValue',
      graphQLString,
      resolve: (obj, _) => _fetchFromInputValue<String?>(
        obj,
        (f) => f.defaultValue?.toString(),
        (f) => f.defaultValue?.toString(),
      ),
    ),
  ]);
}

final GraphQLEnumType<String> _directiveLocationType =
    enumTypeFromStrings('__DirectiveLocation', [
  'QUERY',
  'MUTATION',
  'FIELD',
  'FRAGMENT_DEFINITION',
  'FRAGMENT_SPREAD',
  'INLINE_FRAGMENT'
]);

GraphQLObjectType<gql.DirectiveNode>? _directiveType;
GraphQLObjectType<gql.DirectiveNode> _reflectDirectiveType() {
  final inputValueType = _reflectInputValueType();

  // TODO: What actually is this???
  return _directiveType ??= objectType('__Directive', fields: [
    field(
      'name',
      graphQLString.nonNull(),
      resolve: (obj, _) => obj.name.value,
    ),
    field(
      'description',
      graphQLString,
      resolve: (obj, _) => null,
    ),
    field(
      'locations',
      listOf(_directiveLocationType.nonNull()).nonNull(),
      // TODO: Fetch directiveLocation
      resolve: (obj, _) => <String>[],
    ),
    field(
      'args',
      listOf(inputValueType.nonNull()).nonNull(),
      resolve: (obj, _) => <Map<String, Object?>>[],
    ),
  ]);
}

GraphQLObjectType<GraphQLEnumValue>? _enumValueType;
GraphQLObjectType<GraphQLEnumValue> _reflectEnumValueType() {
  return _enumValueType ??= objectType(
    '__EnumValue',
    fields: [
      field(
        'name',
        graphQLString.nonNull(),
        resolve: (obj, _) => obj.name,
      ),
      field(
        'description',
        graphQLString,
        resolve: (obj, _) => obj.description,
      ),
      field(
        'isDeprecated',
        graphQLBoolean.nonNull(),
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
