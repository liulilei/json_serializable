// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('!browser')
library json_serializable.test.json_generator_test;

// TODO(kevmoo): test all flavors of `nullable` - class, fields, etc

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/src/string_source.dart';
import 'package:dart_style/dart_style.dart' as dart_style;
import 'package:json_serializable/json_serializable.dart';
import 'package:json_serializable/src/constants.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

import 'analysis_utils.dart';
import 'test_utils.dart';

void main() {
  setUpAll(() async {
    _compUnit = await _getCompilationUnitForString(getPackagePath());
  });

  group('without wrappers',
      () => _registerTests(const JsonSerializableGenerator()));
  group('with wrapper',
      () => _registerTests(const JsonSerializableGenerator(useWrappers: true)));
}

void _registerTests(JsonSerializableGenerator generator) {
  Future<String> runForElementNamed(String name) async {
    var library = new LibraryReader(_compUnit.element.library);
    var element = library.allElements.singleWhere((e) => e.name == name);
    var annotation = generator.typeChecker.firstAnnotationOf(element);
    var generated = await generator.generateForAnnotatedElement(
        element, new ConstantReader(annotation), null);

    return _formatter.format(generated);
  }

  group('non-classes', () {
    test('const field', () async {
      expect(
          runForElementNamed('theAnswer'),
          throwsInvalidGenerationSourceError(
              'Generator cannot target `theAnswer`.',
              'Remove the JsonSerializable annotation from `theAnswer`.'));
    });

    test('method', () async {
      expect(
          runForElementNamed('annotatedMethod'),
          throwsInvalidGenerationSourceError(
              'Generator cannot target `annotatedMethod`.',
              'Remove the JsonSerializable annotation from `annotatedMethod`.'));
    });
  });
  group('unknown types', () {
    test('in constructor arguments', () async {
      expect(
          runForElementNamed('UnknownCtorParamType'),
          throwsInvalidGenerationSourceError(
              'At least one constructor argument has an invalid type: `number`.',
              'Check names and imports.'));
    });

    test('in fields', () async {
      expect(
          runForElementNamed('UnknownFieldType'),
          throwsInvalidGenerationSourceError(
              'At least one field has an invalid type: `number`.',
              'Check names and imports.'));
    });
  });

  group('unserializable types', () {
    final noSupportHelperFyi = 'Could not generate `toJson` code for `watch`.\n'
        'None of the provided `TypeHelper` instances support the defined type.';

    test('for toJson', () async {
      expect(
          runForElementNamed('NoSerializeFieldType'),
          throwsInvalidGenerationSourceError(noSupportHelperFyi,
              'Make sure all of the types are serializable.'));
    });

    test('for fromJson', () async {
      expect(
          runForElementNamed('NoDeserializeFieldType'),
          throwsInvalidGenerationSourceError(
              noSupportHelperFyi.replaceFirst('toJson', 'fromJson'),
              'Make sure all of the types are serializable.'));
    });

    final mapKeyFyi = 'Could not generate `toJson` code for '
        '`intDateTimeMap` because of type `int`.\n'
        'The type of the Map key must be `String`, `Object` or `dynamic`.';

    test('for toJson in Map key', () async {
      expect(
          runForElementNamed('NoSerializeBadKey'),
          throwsInvalidGenerationSourceError(
              mapKeyFyi, 'Make sure all of the types are serializable.'));
    });

    test('for fromJson', () async {
      expect(
          runForElementNamed('NoDeserializeBadKey'),
          throwsInvalidGenerationSourceError(
              mapKeyFyi.replaceFirst('toJson', 'fromJson'),
              'Make sure all of the types are serializable.'));
    });
  });

  test('class with final fields', () async {
    var generateResult = await runForElementNamed('FinalFields');
    expect(generateResult, contains('Map<String, dynamic> toJson()'));
  });

  if (!generator.useWrappers) {
    test('includes final field in toJson when set in ctor', () async {
      var generateResult = await runForElementNamed('FinalFields');
      expect(generateResult, contains('new FinalFields(json[\'a\'] as int);'));
      expect(
          generateResult, contains('toJson() => <String, dynamic>{\'a\': a};'));
    });

    test('excludes final field in toJson when not set in ctor', () async {
      var generateResult = await runForElementNamed('FinalFieldsNotSetInCtor');
      expect(generateResult,
          isNot(contains('new FinalFields(json[\'a\'] as int);')));
      expect(generateResult,
          isNot(contains('toJson() => <String, dynamic>{\'a\': a};')));
    });
  }

  group('valid inputs', () {
    if (!generator.useWrappers) {
      test('class with no ctor params', () async {
        var output = await runForElementNamed('Person');
        expect(output,
            r'''Person _$PersonFromJson(Map<String, dynamic> json) => new Person()
  ..firstName = json['firstName'] as String
  ..lastName = json['lastName'] as String
  ..height = json['h'] as int
  ..dateOfBirth = json['dateOfBirth'] == null
      ? null
      : DateTime.parse(json['dateOfBirth'] as String)
  ..dynamicType = json['dynamicType']
  ..varType = json['varType']
  ..listOfInts = (json['listOfInts'] as List)?.map((e) => e as int)?.toList();

abstract class _$PersonSerializerMixin {
  String get firstName;
  String get lastName;
  int get height;
  DateTime get dateOfBirth;
  dynamic get dynamicType;
  dynamic get varType;
  List<int> get listOfInts;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'h': height,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'dynamicType': dynamicType,
        'varType': varType,
        'listOfInts': listOfInts
      };
}
''');
      });

      test('class with ctor params', () async {
        var output = await runForElementNamed('Order');
        expect(output,
            r'''Order _$OrderFromJson(Map<String, dynamic> json) => new Order(
    json['height'] as int,
    json['firstName'] as String,
    json['lastName'] as String)
  ..dateOfBirth = json['dateOfBirth'] == null
      ? null
      : DateTime.parse(json['dateOfBirth'] as String);

abstract class _$OrderSerializerMixin {
  String get firstName;
  String get lastName;
  int get height;
  DateTime get dateOfBirth;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'height': height,
        'dateOfBirth': dateOfBirth?.toIso8601String()
      };
}
''');
      });
    }

    test('class with fromJson() constructor with optional parameters',
        () async {
      var output = await runForElementNamed('FromJsonOptionalParameters');

      expect(output, contains('new ChildWithFromJson.fromJson'));
    });

    test('class with child json-able object', () async {
      var output = await runForElementNamed('ParentObject');

      expect(output, contains('new ChildObject.fromJson'));
    });

    test('class with child list of json-able objects', () async {
      var output = await runForElementNamed('ParentObjectWithChildren');

      expect(output, contains('.toList()'));
      expect(output, contains('new ChildObject.fromJson'));
    });

    test('class with child list of dynamic objects is left alone', () async {
      var output = await runForElementNamed('ParentObjectWithDynamicChildren');

      expect(output, contains('children = json[\'children\'] as List;'));
    });

    test('class with list of int is cast for strong mode', () async {
      var output = await runForElementNamed('Person');

      expect(output,
          contains("json['listOfInts'] as List)?.map((e) => e as int)"));
    });
  });

  group('JsonKey', () {
    if (!generator.useWrappers) {
      test('works to change the name of a field', () async {
        var output = await runForElementNamed('Person');

        expect(output, contains("'h': height,"));
        expect(output, contains("..height = json['h']"));
      });
    }

    if (!generator.useWrappers) {
      test('works to ignore a field', () async {
        var output = await runForElementNamed('IgnoredFieldClass');

        expect(output, contains("'ignoredFalseField': ignoredFalseField,"));
        expect(output, contains("'ignoredNullField': ignoredNullField"));
        expect(output, isNot(contains("'ignoredTrueField': ignoredTrueField")));
      });
    }

    if (!generator.useWrappers) {
      test('fails if ignored field is referenced by ctor', () async {
        expect(
            () => runForElementNamed('IgnoredFieldCtorClass'),
            throwsA(new FeatureMatcher<UnsupportedError>(
                'message',
                (e) => e.message,
                'Cannot populate the required constructor argument: '
                'ignoredTrueField. It is assigned to an ignored field.')));
      });
    }
    if (!generator.useWrappers) {
      test('fails if private field is referenced by ctor', () async {
        expect(
            () => runForElementNamed('PrivateFieldCtorClass'),
            throwsA(new FeatureMatcher<UnsupportedError>(
                'message',
                (e) => e.message,
                'Cannot populate the required constructor argument: '
                '_privateField. It is assigned to a private field.')));
      });
    }

    test('fails if name duplicates existing field', () async {
      expect(
          () => runForElementNamed('KeyDupesField'),
          throwsInvalidGenerationSourceError(
              'More than one field has the JSON key `str`.',
              'Check the `JsonKey` annotations on fields.'));
    });

    test('fails if two names collide', () async {
      expect(
          () => runForElementNamed('DupeKeys'),
          throwsInvalidGenerationSourceError(
              'More than one field has the JSON key `a`.',
              'Check the `JsonKey` annotations on fields.'));
    });
  });

  group('includeIfNull', () {
    test('some', () async {
      var output = await runForElementNamed('IncludeIfNullAll');
      expect(output, isNot(contains(toJsonMapVarName)));
      expect(output, isNot(contains(toJsonMapHelperName)));
    });

    if (!generator.useWrappers) {
      test('all', () async {
        var output = await runForElementNamed('IncludeIfNullOverride');
        expect(output, contains("'number': number,"));
        expect(output, contains("$toJsonMapHelperName('str', str);"));
      });
    }
  });

  test('missing default ctor with a factory', () async {
    expect(
        () => runForElementNamed('NoCtorClass'),
        throwsA(new FeatureMatcher<UnsupportedError>(
            'message',
            (e) => e.message,
            'The class `NoCtorClass` has no default constructor.')));
  });

  test('super types', () async {
    var output = await runForElementNamed('SubType');

    String expected;
    if (generator.useWrappers) {
      expected =
          r'''SubType _$SubTypeFromJson(Map<String, dynamic> json) => new SubType(
    json['subTypeViaCtor'] as int, json['super-type-via-ctor'] as int)
  ..superTypeReadWrite = json['superTypeReadWrite'] as int
  ..subTypeReadWrite = json['subTypeReadWrite'] as int;

abstract class _$SubTypeSerializerMixin {
  int get superTypeViaCtor;
  int get superTypeReadWrite;
  int get subTypeViaCtor;
  int get subTypeReadWrite;
  Map<String, dynamic> toJson() => new _$SubTypeJsonMapWrapper(this);
}

class _$SubTypeJsonMapWrapper extends $JsonMapWrapper {
  final _$SubTypeSerializerMixin _v;
  _$SubTypeJsonMapWrapper(this._v);

  @override
  Iterable<String> get keys sync* {
    yield 'super-type-via-ctor';
    if (_v.superTypeReadWrite != null) {
      yield 'superTypeReadWrite';
    }
    yield 'subTypeViaCtor';
    yield 'subTypeReadWrite';
  }

  @override
  dynamic operator [](Object key) {
    if (key is String) {
      switch (key) {
        case 'super-type-via-ctor':
          return _v.superTypeViaCtor;
        case 'superTypeReadWrite':
          return _v.superTypeReadWrite;
        case 'subTypeViaCtor':
          return _v.subTypeViaCtor;
        case 'subTypeReadWrite':
          return _v.subTypeReadWrite;
      }
    }
    return null;
  }
}
''';
    } else {
      expected =
          r'''SubType _$SubTypeFromJson(Map<String, dynamic> json) => new SubType(
    json['subTypeViaCtor'] as int, json['super-type-via-ctor'] as int)
  ..superTypeReadWrite = json['superTypeReadWrite'] as int
  ..subTypeReadWrite = json['subTypeReadWrite'] as int;

abstract class _$SubTypeSerializerMixin {
  int get superTypeViaCtor;
  int get superTypeReadWrite;
  int get subTypeViaCtor;
  int get subTypeReadWrite;
  Map<String, dynamic> toJson() {
    var val = <String, dynamic>{
      'super-type-via-ctor': superTypeViaCtor,
    };

    void writeNotNull(String key, dynamic value) {
      if (value != null) {
        val[key] = value;
      }
    }

    writeNotNull('superTypeReadWrite', superTypeReadWrite);
    val['subTypeViaCtor'] = subTypeViaCtor;
    val['subTypeReadWrite'] = subTypeReadWrite;
    return val;
  }
}
''';
    }

    expect(output, expected);
  });
}

final _formatter = new dart_style.DartFormatter();

Future<CompilationUnit> _getCompilationUnitForString(String projectPath) async {
  var filePath = p.join(
      getPackagePath(), 'test', 'src', 'json_serializable_test_input.dart');
  var source =
      new StringSource(new File(filePath).readAsStringSync(), 'test content');

  var context = await getAnalysisContextForProjectPath(projectPath);

  var libElement = context.computeLibraryElement(source);
  return context.resolveCompilationUnit(source, libElement);
}

CompilationUnit _compUnit;
