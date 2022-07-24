import 'dart:convert';

import 'package:leto_schema/src/validate/rules_prelude.dart';

class ValidaAttachment implements ToDirectiveValue {
  /// The valida spec as json
  final dynamic annotation;

  /// A GraphQL attachment which specifies a valida [annotation]
  /// in a [GraphQLElement] for validating input and outputs.
  /// Presented as a directive [directiveDefinition] in the GraphQL schema.
  ///
  /// In code generation use [AttachFn] or the valida annotations.
  const ValidaAttachment(this.annotation);

  @override
  DirectiveNode get directiveValue {
    return DirectiveNode(
      name: const NameNode(value: 'valida'),
      arguments: [
        ArgumentNode(
          name: const NameNode(value: 'jsonSpec'),
          value: StringValueNode(
            value: _jsonSpec(),
            isBlock: false,
          ),
        ),
      ],
    );
  }

  static Object? _mapJsonValue(Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    } else if (value is List<Object?>) {
      return value.map(_mapJsonValue).toList();
    } else if (value is Map<String, Object?>) {
      return value.map((key, value) => MapEntry(key, _mapJsonValue(value)))
        ..removeWhere((key, value) => value == null);
    }
    return _mapJsonValue((value as dynamic).toJson());
  }

  String _jsonSpec() {
    final map = annotation.toJson() as Map<String, Object?>;
    return jsonEncode(_mapJsonValue(map));
  }

  @override
  GraphQLDirective get directiveDefinition => validaGraphQLDirective;

  @override
  String toString() {
    return 'ValidaAttachment(${jsonEncode(annotation.toJson())})';
  }
}

/// The validation performed in a type, field or argument definition
final validaGraphQLDirective = GraphQLDirective(
  name: 'valida',
  locations: [
    // Types
    DirectiveLocation.SCALAR,
    DirectiveLocation.OBJECT,
    DirectiveLocation.INTERFACE,
    DirectiveLocation.UNION,
    DirectiveLocation.ENUM,
    DirectiveLocation.INPUT_OBJECT,
    // Fields
    DirectiveLocation.FIELD_DEFINITION,
    DirectiveLocation.ARGUMENT_DEFINITION,
    DirectiveLocation.INPUT_FIELD_DEFINITION,
  ],
  description:
      'The validation performed in a type, field or argument definition',
  isRepeatable: false,
  inputs: [
    graphQLString.nonNull().inputField('jsonSpec'),
  ],
);
