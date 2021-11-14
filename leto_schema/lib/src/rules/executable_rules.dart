import 'package:gql/ast.dart';
import 'package:leto_schema/leto_schema.dart';
import 'package:leto_schema/src/rules/typed_visitor.dart';
import 'package:leto_schema/src/rules/validate.dart';
import 'package:leto_schema/src/utilities/build_schema.dart';
import 'package:leto_schema/src/utilities/predicates.dart';

/// Executable definitions
///
/// A GraphQL document is only valid for execution if all definitions are either
/// operation or fragment definitions.
///
/// See https://spec.graphql.org/draft/#sec-Executable-Definitions
Visitor executableDefinitionsRule(ValidationCtx ctx) =>
    ExecutableDefinitionsRule();

class ExecutableDefinitionsRule extends SimpleVisitor<List<GraphQLError>> {
  @override
  List<GraphQLError>? visitDocumentNode(DocumentNode node) {
    final nonExecutable = node.definitions.where(
      (element) =>
          element is! OperationDefinitionNode &&
          element is! FragmentDefinitionNode,
    );
    return nonExecutable
        .map((e) => GraphQLError(
              'The $e is not executable',
              locations: GraphQLErrorLocation.listFromSource(e.span?.start),
            ))
        .toList();
  }
}

/// Unique operation names
///
/// A GraphQL document is only valid if all
/// defined operations have unique names.
///
/// See https://spec.graphql.org/draft/#sec-Operation-Name-Uniqueness
Visitor uniqueOperationNamesRule(ValidationCtx ctx) =>
    UniqueOperationNamesRule();

class UniqueOperationNamesRule extends SimpleVisitor<List<GraphQLError>> {
  final operations = <String, OperationDefinitionNode>{};

  @override
  List<GraphQLError>? visitOperationDefinitionNode(
    OperationDefinitionNode node,
  ) {
    final name = node.name?.value;
    if (name == null) {
      return null;
    }
    final prev = operations[name];
    if (prev != null) {
      return [
        GraphQLError(
          'There can be only one operation named "$name".',
          locations: [
            GraphQLErrorLocation.fromSourceLocation(prev.name!.span!.start),
            GraphQLErrorLocation.fromSourceLocation(node.name!.span!.start),
          ],
        )
      ];
    } else {
      operations[name] = node;
    }
  }
}

/// Lone anonymous operation
///
/// A GraphQL document is only valid if when it contains an anonymous operation
/// (the query short-hand) that it contains only that one operation definition.
///
/// See https://spec.graphql.org/draft/#sec-Lone-Anonymous-Operation
Visitor loneAnonymousOperationRule(ValidationCtx ctx) =>
    LoneAnonymousOperationRule();

class LoneAnonymousOperationRule extends SimpleVisitor<List<GraphQLError>> {
  final operations = <String, OperationDefinitionNode>{};
  int operationCount = 0;

  @override
  List<GraphQLError>? visitDocumentNode(DocumentNode node) {
    operationCount =
        node.definitions.whereType<OperationDefinitionNode>().length;
  }

  @override
  List<GraphQLError>? visitOperationDefinitionNode(
    OperationDefinitionNode node,
  ) {
    final name = node.name?.value;
    if (name == null && operationCount > 1) {
      return [
        GraphQLError(
          'This anonymous operation must be the only defined operation.',
          locations: GraphQLErrorLocation.listFromSource(node.span?.start),
        )
      ];
    }
  }
}

/// Known type names
///
/// A GraphQL document is only valid if referenced types (specifically
/// variable definitions and fragment conditions) are defined
/// by the type schema.
///
/// See https://spec.graphql.org/draft/#sec-Fragment-Spread-Type-Existence
Visitor knownTypeNamesRule(ValidationCtx ctx) => KnownTypeNamesRule(ctx.schema);

class KnownTypeNamesRule extends SimpleVisitor<List<GraphQLError>> {
  final GraphQLSchema schema;

  KnownTypeNamesRule(this.schema);

  @override
  List<GraphQLError>? visitNamedTypeNode(NamedTypeNode node) {
    final name = node.name.value;
    if (!schema.typeMap.containsKey(name) &&
        !introspectionTypeNames.contains(name) &&
        !specifiedScalarNames.contains(name)) {
      return [
        GraphQLError(
          'Unknown type "$name".',
          locations: GraphQLErrorLocation.listFromSource(node.name.span?.start),
        )
      ];
    }
  }
}

/// Fragments on composite type
///
/// Fragments use a type condition to determine if they apply, since fragments
/// can only be spread into a composite type (object, interface, or union), the
/// type condition must also be a composite type.
///
/// See https://spec.graphql.org/draft/#sec-Fragments-On-Composite-Types
Visitor fragmentsOnCompositeTypesRule(ValidationCtx ctx) =>
    FragmentsOnCompositeTypesRule(ctx.schema);

class FragmentsOnCompositeTypesRule extends SimpleVisitor<List<GraphQLError>> {
  final GraphQLSchema schema;

  FragmentsOnCompositeTypesRule(this.schema);

  @override
  List<GraphQLError>? visitInlineFragmentNode(InlineFragmentNode node) {
    return validate(node.typeCondition, null);
  }

  @override
  List<GraphQLError>? visitFragmentDefinitionNode(FragmentDefinitionNode node) {
    return validate(node.typeCondition, node.name.value);
  }

  /// Execute the validation
  List<GraphQLError>? validate(TypeConditionNode? typeCondition, String? name) {
    if (typeCondition != null) {
      final type = convertType(typeCondition.on, schema.typeMap);
      if (type is! GraphQLUnionType && type is! GraphQLObjectType) {
        return [
          GraphQLError(
            'Fragment${name == null ? '' : ' $name'} cannot condition'
            ' on non composite type "$type".',
            locations: GraphQLErrorLocation.listFromSource(
              typeCondition.span?.start ?? typeCondition.on.name.span?.start,
            ),
          )
        ];
      }
    }
  }
}

/// Variables are input types
///
/// A GraphQL operation is only valid if all the variables it defines are of
/// input types (scalar, enum, or input object).
///
/// See https://spec.graphql.org/draft/#sec-Variables-Are-Input-Types
Visitor variablesAreInputTypesRule(ValidationCtx ctx) =>
    VariablesAreInputTypesRule(ctx.schema);

class VariablesAreInputTypesRule extends SimpleVisitor<List<GraphQLError>> {
  final GraphQLSchema schema;

  VariablesAreInputTypesRule(this.schema);

  @override
  List<GraphQLError>? visitVariableDefinitionNode(VariableDefinitionNode node) {
    final type = convertType(node.type, schema.typeMap);

    if (!isInputType(type)) {
      return [
        GraphQLError(
          'Variable "\$${node.variable.name.value}" cannot'
          ' be non-input type "$type".',
          locations: GraphQLErrorLocation.listFromSource(
            node.span?.start ?? node.type.span?.start,
          ),
        )
      ];
    }
  }
}

/// Scalar leafs
///
/// A GraphQL document is valid only if all leaf fields (fields without
/// sub selections) are of scalar or enum types.
Visitor scalarLeafsRule(ValidationCtx ctx) => ScalarLeafsRule();

class ScalarLeafsRule extends SimpleVisitor<List<GraphQLError>> {
  @override
  List<GraphQLError>? visitFieldNode(FieldNode node) {}
}

// TODO: need info in parent types
// ScalarLeafsRule,
// FieldsOnCorrectTypeRule,

/// Unique fragment names
///
/// A GraphQL document is only valid if all defined fragments have unique names.
///
/// See https://spec.graphql.org/draft/#sec-Fragment-Name-Uniqueness
class UniqueFragmentNamesRule extends UniqueNamesRule<FragmentDefinitionNode> {
  @override
  List<GraphQLError>? visitFragmentDefinitionNode(FragmentDefinitionNode node) {
    final name = node.name.value;
    return super.process(
      node: node,
      nameNode: node.name,
      error: 'There can be only one fragment named "$name".',
    );
  }
}

class UniqueNamesRule<T extends DefinitionNode>
    extends SimpleVisitor<List<GraphQLError>> {
  final operations = <String, T>{};

  List<GraphQLError>? process({
    required T node,
    required NameNode nameNode,
    required String error,
  }) {
    final name = nameNode.value;
    final prev = operations[name];
    if (prev != null) {
      return [
        GraphQLError(
          error,
          locations: GraphQLErrorLocation.listFromSource(
            node.span?.start ?? nameNode.span?.start,
          ),
        )
      ];
    } else {
      operations[name] = node;
    }
  }
}

/// Known fragment names
///
/// A GraphQL document is only valid if all `...Fragment` fragment spreads refer
/// to fragments defined in the same document.
///
/// See https://spec.graphql.org/draft/#sec-Fragment-spread-target-defined
Visitor knownFragmentNamesRule(ValidationCtx ctx) => KnownFragmentNamesRule();

class KnownFragmentNamesRule extends SimpleVisitor<List<GraphQLError>> {
  late final List<FragmentDefinitionNode> fragments;
  @override
  List<GraphQLError>? visitDocumentNode(DocumentNode node) {
    fragments = node.definitions.whereType<FragmentDefinitionNode>().toList();
  }

  @override
  List<GraphQLError>? visitFragmentSpreadNode(FragmentSpreadNode node) {
    final found = fragments.any((f) => f.name.value == node.name.value);
    if (!found) {
      return [
        GraphQLError(
          'Unknown fragment "${node.name.value}"',
          locations: GraphQLErrorLocation.listFromSource(
            node.span?.start ?? node.name.span?.start,
          ),
        )
      ];
    }
  }
}

/// No unused fragments
///
/// A GraphQL document is only valid if all fragment definitions are spread
/// within operations, or spread within other fragments spread within
/// operations.
///
/// See https://spec.graphql.org/draft/#sec-Fragments-Must-Be-Used
class NoUnusedFragmentsRule extends RecursiveVisitor {
  final operationDefs = <OperationDefinitionNode>[];
  final fragmentDefs = <FragmentDefinitionNode>[];

  @override
  void visitOperationDefinitionNode(OperationDefinitionNode node) {
    operationDefs.add(node);
    super.visitOperationDefinitionNode(node);
  }

  @override
  void visitFragmentDefinitionNode(FragmentDefinitionNode node) {
    // TODO: implement visitFragmentDefinitionNode
    super.visitFragmentDefinitionNode(node);
  }
}

/// Fields on correct type
///
/// A GraphQL document is only valid if all fields selected are defined by the
/// parent type, or are an allowed meta field such as __typename.
///
/// See https://spec.graphql.org/draft/#sec-Field-Selections
TypedVisitor fieldsOnCorrectTypeRule(ValidationCtx context) {
  final visitor = TypedVisitor();
  final typeInfo = context.typeInfo;

  visitor.add<FieldNode>((node) {
    final type = typeInfo.getParentType();
    if (type != null) {
      final fieldDef = typeInfo.getFieldDef();
      if (fieldDef == null) {
        // This field doesn't exist, lets look for suggestions.
        // final schema = context.schema;
        final fieldName = node.name.value;

        // // First determine if there are any suggested types to condition on.
        // var suggestion = didYouMean(
        //   'to use an inline fragment on',
        //   getSuggestedTypeNames(schema, type, fieldName),
        // );

        // // If there are no suggested types, then perhaps this was a typo?
        // if (suggestion == '') {
        //   suggestion = didYouMean(getSuggestedFieldNames(type, fieldName));
        // }

        // Report an error, including helpful suggestions.
        context.reportError(
          GraphQLError(
            'Cannot query field "$fieldName" on type "${type.name}".',
            locations: GraphQLErrorLocation.listFromSource(
              node.span?.start ?? node.name.span?.start,
            ),
          ),
        );
      }
    }
  });

  return visitor;
}