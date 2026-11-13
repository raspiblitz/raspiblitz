#!/usr/bin/python3
"""Validates JSON documents against the schemas in test/tunnelsats/schema/ (stdlib only).

Supports the subset the schemas use: type (including lists and "null"), const, enum, pattern,
required, properties, additionalProperties false, items, minimum, maximum.

Usage: schema_check.py SCHEMA DOC [DOC...]   (DOC "-" reads stdin)
"""

import json
import re
import sys

_TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "null": lambda v: v is None,
}


def _same_value(actual, expected):
    if isinstance(actual, bool) != isinstance(expected, bool):
        return False
    return actual == expected


def validate(value, schema, path="$"):
    """Returns a list of error strings (empty when the value matches)."""
    errors = []
    if "const" in schema and not _same_value(value, schema["const"]):
        errors.append(f"{path}: expected {schema['const']!r}")
    if "enum" in schema and not any(_same_value(value, item) for item in schema["enum"]):
        errors.append(f"{path}: {value!r} not in {schema['enum']!r}")
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_TYPES[t](value) for t in types):
            errors.append(f"{path}: type {type(value).__name__} not in {types}")
            return errors
    if isinstance(value, str) and "pattern" in schema and not re.search(schema["pattern"], value):
        errors.append(f"{path}: does not match {schema['pattern']}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: above {schema['maximum']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing {key}")
        props = schema.get("properties", {})
        for key, sub in value.items():
            if key in props:
                errors.extend(validate(sub, props[key], f"{path}.{key}"))
            elif schema.get("additionalProperties", True) is False:
                errors.append(f"{path}: unexpected {key}")
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            errors.extend(validate(item, schema["items"], f"{path}[{i}]"))
    return errors


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        schema = json.load(f)
    failed = False
    for name in argv[2:]:
        text = sys.stdin.read() if name == "-" else open(name, encoding="utf-8").read()
        try:
            doc = json.loads(text)
        except ValueError as exc:
            print(f"{name}: not JSON ({exc})")
            failed = True
            continue
        for err in validate(doc, schema):
            print(f"{name}: {err}")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
