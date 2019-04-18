import 'dart:async';
import 'package:graphql_schema/graphql_schema.dart';
import 'package:stream_channel/stream_channel.dart';

/// A basic message in the Apollo WebSocket protocol.
class OperationMessage {
  static const String gqlConnectionInit = 'GQL_CONNECTION_INIT',
      gqlConnectionAck = 'GQL_CONNECTION_ACK',
      gqlConnectionKeepAlive = 'GQL_CONNECTION_KEEP_ALIVE',
      gqlConnectionError = 'GQL_CONNECTION_ERROR',
      gqlStart = 'GQL_START',
      gqlStop = 'GQL_STOP',
      gqlConnectionTerminate = 'GQL_CONNECTION_TERMINATE',
      gqlData = 'GQL_DATA',
      gqlError = 'GQL_ERROR',
      gqlComplete = 'GQL_COMPLETE';
  final dynamic payload;
  final String id;
  final String type;

  OperationMessage(this.type, {this.payload, this.id});

  factory OperationMessage.fromJson(Map map) {
    var type = map['type'];
    var payload = map['payload'];
    var id = map['id'];

    if (type == null)
      throw ArgumentError.notNull('type');
    else if (type is! String)
      throw ArgumentError.value(type, 'type', 'must be a string');
    else if (id != null && id is! String)
      throw ArgumentError.value(type, 'id', 'must be a string');
    return OperationMessage(type as String, id: id as String, payload: payload);
  }

  Map<String, dynamic> toJson() {
    var out = <String, dynamic>{'type': type};
    if (id != null) out['id'] = id;
    if (payload != null) out['payload'] = payload;
    return out;
  }
}

class GraphQLResult {
  final dynamic data;
  final Iterable<GraphQLExceptionError> errors;

  GraphQLResult(this.data, {this.errors: const []});
}