part of '../fuzzylogic.dart';

final Logger logger = Logger('fuzzylogic');

String _nameOrUnnamed(String? name, String type) {
  if (name == null /* name.isEmpty*/) {
    return 'unnamed $type';
  }

  return '$type $name';
}
