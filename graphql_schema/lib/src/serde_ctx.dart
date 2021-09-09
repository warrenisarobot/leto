part of graphql_schema.src.schema;

class SerdeCtx {
  SerdeCtx();

  final Map<Type, Serializer<Object?>> _map = {
    int: const _SerializerIdentity<int>(),
    double: const _SerializerIdentity<double>(),
    num: const _SerializerIdentity<num>(),
    String: const _SerializerIdentity<String>(),
    bool: const _SerializerIdentity<bool>(),
    // ignore: prefer_void_to_null
    Null: const _SerializerIdentity<Null>(),
    DateTime: const _SerializerDateTime(),
  };

  T fromJson<T>(Object? json, [T Function()? _itemFactory]) {
    if (json is T) {
      return json;
    } else {
      // final itemFactory = _itemFactory ?? Globals.getFactory<T>();
      // if (itemFactory != null) {
      //   try {
      //     final item = itemFactory();
      //     if (item is SerializableItem && item.trySetFromJson(json)) {
      //       return item;
      //     } else {
      //       throw Error();
      //     }
      //   } catch (_) {}
      // }
      final serializer = of<T>();
      if (serializer == null) {
        throw Exception('No serializer for type $T');
      }
      return serializer.fromJson(json);
    }
  }

  Map<K, V> fromJsonMap<K, V>(Object? json) {
    if (json is Map) {
      return json.map(
        (Object? key, Object? value) => MapEntry(
          fromJson<K>(key),
          fromJson<V>(value),
        ),
      );
    }
    throw Error();
  }

  Map<String, Object?> toJsonMap<K, V>(Map<K, V> map) {
    return map.map(
      (key, value) => MapEntry(
        toJson<K>(key).toString(),
        toJson<V>(value),
      ),
    );
  }

  List<V> fromJsonList<V>(Iterable json, [V Function()? itemFactory]) {
    return json
        .map((Object? value) => fromJson<V>(value, itemFactory))
        .toList();
  }

  List<Object?> toJsonList<V>(Iterable<V> list) {
    return list.map((value) => toJson<V>(value)).toList();
  }

  Object? toJson<T>(T instance) {
    try {
      final serializer = of<T>();
      return serializer!.toJson(instance);
    } catch (_) {
      if (instance is Map) {
        return instance.toJsonMap(this);
      } else if (instance is List || instance is Set) {
        return (instance as Iterable).toJsonList(this);
      } else if (instance == null && null is T) {
        return null;
      } else {
        try {
          // ignore: avoid_dynamic_calls
          return (instance as dynamic).toJson();
        } catch (_) {
          // ignore: avoid_dynamic_calls
          return (instance as dynamic).toMap();
        }
      }
    }
  }

  void addAll(Iterable<Serializer<dynamic>> serializers) {
    serializers.forEach(add);
  }

  void add(Serializer serializer) {
    _map[serializer.type] = serializer;
  }

  Serializer<Object?>? ofValue(Type T) {
    return _map[T];
  }

  Serializer<T>? of<T>() {
    final v = _map[T] as Serializer<T>?;
    if (v != null) return v;
    return _map.values.firstWhereOrNull((serde) => serde.isEqualType<T>())
        as Serializer<T>?;
  }

  List<Serializer<T>> manyOf<T>() {
    final v = _map[T] as Serializer<T>?;
    if (v != null) return [v];
    return _map.values
        .where((serde) => serde.isType<T>())
        .map((s) => s as Serializer<T>)
        .toList();
  }
}

abstract class SerializableGeneric<S> {
  S toJson();
}

abstract class Serializable
    implements SerializableGeneric<Map<String, dynamic>> {
  @override
  Map<String, dynamic> toJson();
}

abstract class Serializer<T> {
  const Serializer(); // {
  //   Serializers.add(this);
  // }

  T fromJson(Object? json);
  Object? toJson(T instance);

  Type get type => T;

  bool isType<O>() => O is T;
  bool isOtherType<O>() => T is O;
  bool isEqualType<O>() => O == T;
}

class _SerializerIdentity<T> extends Serializer<T> {
  const _SerializerIdentity();

  @override
  T fromJson(Object? json) {
    return json as T;
  }

  @override
  Object? toJson(T instance) {
    return instance;
  }
}

class _SerializerDateTime extends Serializer<DateTime> {
  const _SerializerDateTime();

  @override
  DateTime fromJson(Object? json) {
    if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json);
    } else if (json is String) {
      return DateTime.parse(json);
    }
    throw Error();
  }

  @override
  Object? toJson(DateTime instance) {
    return instance.toIso8601String();
  }
}

class SerializerFuncGeneric<T extends SerializableGeneric<S>, S>
    extends Serializer<T> {
  SerializerFuncGeneric({
    required T Function(S json) fromJson,
  })  : _fromJson = fromJson,
        super();

  final T Function(S json) _fromJson;

  @override
  T fromJson(Object? json) => _fromJson(json as S);
  @override
  S toJson(T instance) => instance.toJson();
}

class SerializerFunc<T extends Serializable> extends Serializer<T> {
  const SerializerFunc({
    required T Function(Map<String, dynamic> json) fromJson,
  })  : _fromJson = fromJson,
        super();

  final T Function(Map<String, dynamic> json) _fromJson;

  @override
  T fromJson(Object? json) =>
      json is T ? json : _fromJson(json! as Map<String, dynamic>);
  @override
  Map<String, dynamic> toJson(T instance) => instance.toJson();
}

extension GenMap<K, V> on Map<K, V> {
  Map<String, Object?> toJsonMap(SerdeCtx serdeCtx) {
    return serdeCtx.toJsonMap(this);
  }
}

extension GenIterable<V> on Iterable<V> {
  List<Object?> toJsonList(SerdeCtx serdeCtx) {
    return serdeCtx.toJsonList(this);
  }
}

class SerializerValue<T> extends Serializer<T> {
  const SerializerValue({
    required T Function(Map<String, dynamic> json) fromJson,
    required Map<String, dynamic> Function(T value) toJson,
  })  : _fromJson = fromJson,
        _toJson = toJson,
        super();

  final T Function(Map<String, dynamic> json) _fromJson;
  final Map<String, dynamic> Function(T value) _toJson;

  @override
  T fromJson(Object? json) =>
      json is T ? json : _fromJson(json! as Map<String, dynamic>);
  @override
  Map<String, dynamic> toJson(T instance) => _toJson(instance);
}
