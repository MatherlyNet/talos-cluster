#!/usr/bin/env python3
"""
Generate JSON Schema from CUE schema files for IDE validation.

This script parses CUE schemas and produces JSON Schemas that provide
autocomplete and validation in editors using yaml-language-server.

Usage:
    python generate_jsonschema.py              # Generate all schemas
    python generate_jsonschema.py --cluster    # Generate cluster schema only
    python generate_jsonschema.py --nodes      # Generate nodes schema only
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_BASE_URL = "https://github.com/MatherlyNet/talos-cluster"


def parse_cluster_schema(cue_content: str) -> dict[str, Any]:
    """Parse cluster.schema.cue and extract field definitions."""
    schema: dict[str, Any] = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": f"{SCHEMA_BASE_URL}/cluster.schema.json",
        "title": "Cluster Configuration",
        "description": "Configuration schema for matherlynet-talos-cluster GitOps template",
        "type": "object",
        "additionalProperties": False,
        "properties": {},
        "required": [],
    }

    # Extract the #Config block
    config_match = re.search(
        r"#Config:\s*\{(.*?)\n\}\s*$", cue_content, re.DOTALL | re.MULTILINE
    )
    if not config_match:
        raise ValueError("Could not find #Config block in CUE schema")

    config_block = config_match.group(1)
    parse_fields_into_schema(config_block, schema)

    return schema


def parse_nodes_schema(cue_content: str) -> dict[str, Any]:
    """Parse nodes.schema.cue and extract field definitions."""
    schema: dict[str, Any] = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "$id": f"{SCHEMA_BASE_URL}/nodes.schema.json",
        "title": "Nodes Configuration",
        "description": "Node definitions for matherlynet-talos-cluster",
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "nodes": {
                "type": "array",
                "description": "List of cluster nodes",
                "items": {},
                "minItems": 1,
            }
        },
        "required": ["nodes"],
    }

    # Extract the #Node block
    node_match = re.search(r"#Node:\s*\{(.*?)\n\}", cue_content, re.DOTALL)
    if not node_match:
        raise ValueError("Could not find #Node block in CUE schema")

    node_block = node_match.group(1)

    # Build the node item schema
    node_schema: dict[str, Any] = {
        "type": "object",
        "additionalProperties": False,
        "properties": {},
        "required": [],
    }

    parse_fields_into_schema(node_block, node_schema)

    schema["properties"]["nodes"]["items"] = node_schema

    return schema


def parse_fields_into_schema(block: str, schema: dict[str, Any]) -> None:
    """Parse field definitions from a CUE block into a JSON Schema."""
    current_comment = ""
    lines = block.split("\n")
    i = 0

    while i < len(lines):
        line = lines[i].strip()

        # Skip empty lines
        if not line:
            current_comment = ""
            i += 1
            continue

        # Skip internal fields (starting with _)
        if line.startswith("_"):
            i += 1
            continue

        # Collect comments for descriptions
        if line.startswith("//"):
            comment = line[2:].strip()
            if current_comment:
                current_comment += " " + comment
            else:
                current_comment = comment
            i += 1
            continue

        # Parse field definitions
        field_match = re.match(r"^(\w+)(\?)?\s*:\s*(.+)$", line)
        if field_match:
            field_name = field_match.group(1)
            is_optional = field_match.group(2) == "?"
            field_type = field_match.group(3).rstrip(",")

            # Handle multi-line nested objects
            open_braces = field_type.count("{")
            close_braces = field_type.count("}")
            if open_braces > close_braces:
                # Collect all lines until we find the matching closing brace
                brace_count = open_braces - close_braces
                full_type = field_type
                while brace_count > 0 and i + 1 < len(lines):
                    i += 1
                    next_line = lines[i]
                    full_type += "\n" + next_line
                    brace_count += next_line.count("{") - next_line.count("}")
                field_type = full_type

            prop = parse_field_type(field_name, field_type)
            if current_comment:
                prop["description"] = current_comment

            schema["properties"][field_name] = prop

            if not is_optional:
                schema["required"].append(field_name)

            current_comment = ""

        i += 1


def parse_field_type(field_name: str, type_def: str) -> dict[str, Any]:
    """Convert CUE type definition to JSON Schema property."""
    prop: dict[str, Any] = {}

    # Handle nested object types (like proxmox_vm_defaults)
    if type_def.startswith("{"):
        return parse_nested_object(type_def)

    # Handle array types [...Type] (use DOTALL for multi-line nested objects)
    # Use greedy matching with end anchor to avoid stopping at ] inside regex patterns
    # e.g., [...{name: string & =~"^[a-z0-9-]*$"}] - the [a-z0-9-] has a ] inside
    array_match = re.match(r"\[\.\.\.(.*)\]$", type_def, re.DOTALL)
    if array_match:
        inner_type = array_match.group(1).strip()
        prop["type"] = "array"
        prop["items"] = get_simple_type(inner_type)
        return prop

    # Handle default values with alternation: *"value" | type
    default_match = re.match(r'\*"?([^"|]+)"?\s*\|\s*(.+)', type_def)
    if default_match:
        default_val = default_match.group(1).strip()
        rest_type = default_match.group(2)

        # Try to parse the default value
        if default_val.lower() == "true":
            prop["default"] = True
        elif default_val.lower() == "false":
            prop["default"] = False
        elif default_val.isdigit():
            prop["default"] = int(default_val)
        else:
            prop["default"] = default_val

        # Parse remaining type constraints
        type_props = parse_type_constraints(rest_type)
        prop.update(type_props)
        return prop

    # Handle enum types: "value1" | "value2"
    enum_match = re.findall(r'"([^"]+)"', type_def)
    if enum_match and "|" in type_def and "=~" not in type_def:
        prop["type"] = "string"
        prop["enum"] = enum_match
        return prop

    # Parse type constraints
    type_props = parse_type_constraints(type_def)
    prop.update(type_props)

    return prop


def parse_nested_object(type_def: str) -> dict[str, Any]:
    """Parse a nested object type definition."""
    prop: dict[str, Any] = {
        "type": "object",
        "additionalProperties": False,
        "properties": {},
    }

    # Extract content between braces - handle multi-line
    brace_count = 0
    start_idx = type_def.find("{")
    if start_idx == -1:
        return prop

    end_idx = start_idx
    for i, char in enumerate(type_def[start_idx:], start_idx):
        if char == "{":
            brace_count += 1
        elif char == "}":
            brace_count -= 1
            if brace_count == 0:
                end_idx = i
                break

    content = type_def[start_idx + 1 : end_idx]
    current_comment = ""

    for line in content.split("\n"):
        line = line.strip()
        if not line:
            current_comment = ""
            continue

        if line.startswith("//"):
            comment = line[2:].strip()
            if current_comment:
                current_comment += " " + comment
            else:
                current_comment = comment
            continue

        # Handle CUE map pattern: [string]: value_type
        # This indicates any string key is allowed with values of the specified type
        # Example: langfuse_role_mapping?: { [string]: "OWNER" | "ADMIN" | "MEMBER" }
        map_match = re.match(r"^\[string\]\s*:\s*(.+)$", line)
        if map_match:
            value_type = map_match.group(1).rstrip(",")
            # Parse enum values (e.g., "OWNER" | "ADMIN" | "MEMBER")
            enum_values = re.findall(r'"([^"]+)"', value_type)
            if enum_values and "|" in value_type:
                prop["additionalProperties"] = {"type": "string", "enum": enum_values}
            else:
                # Default to string type for unknown value types
                prop["additionalProperties"] = {"type": "string"}
            # Remove empty properties since we're using additionalProperties
            if not prop["properties"]:
                del prop["properties"]
            if current_comment:
                prop["description"] = current_comment
            continue

        field_match = re.match(r"^(\w+)(\?)?\s*:\s*(.+)$", line)
        if field_match:
            field_name = field_match.group(1)
            field_type = field_match.group(3).rstrip(",")
            field_prop = parse_field_type(field_name, field_type)
            if current_comment:
                field_prop["description"] = current_comment
            prop["properties"][field_name] = field_prop
            current_comment = ""

    return prop


def parse_type_constraints(type_def: str) -> dict[str, Any]:
    """Parse CUE type constraints and convert to JSON Schema."""
    prop: dict[str, Any] = {}

    # Remove leading type markers
    type_def = type_def.strip()

    # Handle bool type
    if "bool" in type_def:
        prop["type"] = "boolean"
        return prop

    # Handle standalone range constraints (like >=1450 & <=9000)
    range_only = re.match(r"^>=(\d+)\s*&\s*<=(\d+)$", type_def)
    if range_only:
        prop["type"] = "integer"
        prop["minimum"] = int(range_only.group(1))
        prop["maximum"] = int(range_only.group(2))
        return prop

    # Handle int type with range constraints
    if "int" in type_def:
        prop["type"] = "integer"

        # Extract min constraint
        min_match = re.search(r">=(\d+)", type_def)
        if min_match:
            prop["minimum"] = int(min_match.group(1))

        # Extract max constraint
        max_match = re.search(r"<=(\d+)", type_def)
        if max_match:
            prop["maximum"] = int(max_match.group(1))

        return prop

    # Handle string with regex pattern
    pattern_match = re.search(r'=~"([^"]+)"', type_def)
    if pattern_match:
        prop["type"] = "string"
        # Unescape CUE string escapes (e.g., \\ -> \) for JSON Schema
        prop["pattern"] = pattern_match.group(1).replace("\\\\", "\\")
        return prop

    # Handle net types
    if "net.IPCIDR" in type_def:
        prop["type"] = "string"
        prop["format"] = "ipv4-cidr"
        prop["pattern"] = r"^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$"
        return prop

    if "net.IPv4" in type_def:
        prop["type"] = "string"
        prop["format"] = "ipv4"
        prop["pattern"] = r"^(\d{1,3}\.){3}\d{1,3}$"
        return prop

    if "net.FQDN" in type_def:
        prop["type"] = "string"
        prop["format"] = "hostname"
        return prop

    # Handle plain string
    if "string" in type_def:
        prop["type"] = "string"
        if '!=""' in type_def:
            prop["minLength"] = 1
        return prop

    # Default to string for unrecognized types
    prop["type"] = "string"
    return prop


def get_simple_type(type_name: str) -> dict[str, Any]:
    """Get JSON Schema type for simple CUE types."""
    type_name = type_name.strip()

    if type_name == "net.IPv4":
        return {"type": "string", "format": "ipv4"}
    if type_name == "net.FQDN":
        return {"type": "string", "format": "hostname"}
    if type_name == "net.IPCIDR":
        return {"type": "string", "format": "ipv4-cidr"}
    if type_name == "string":
        return {"type": "string"}
    if type_name == "int":
        return {"type": "integer"}
    if type_name == "bool":
        return {"type": "boolean"}

    # Handle nested object in array
    if type_name.startswith("{"):
        return parse_nested_object(type_name)

    # Handle reference to another definition (like #Node)
    if type_name.startswith("#"):
        # This should be resolved by the caller
        return {"type": "object"}

    return {"type": "string"}


def generate_schema(
    input_path: Path,
    output_path: Path,
    schema_type: str,
) -> bool:
    """Generate a JSON Schema from a CUE schema file."""
    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}", file=sys.stderr)
        return False

    try:
        cue_content = input_path.read_text()

        if schema_type == "cluster":
            schema = parse_cluster_schema(cue_content)
        elif schema_type == "nodes":
            schema = parse_nodes_schema(cue_content)
        else:
            print(f"Error: Unknown schema type: {schema_type}", file=sys.stderr)
            return False

        # Write JSON Schema
        output_path.write_text(json.dumps(schema, indent=2) + "\n")
        print(f"Generated JSON Schema: {output_path}")
        return True

    except Exception as e:
        print(f"Error generating {schema_type} schema: {e}", file=sys.stderr)
        return False


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Generate JSON Schema from CUE schema for IDE validation"
    )
    parser.add_argument(
        "--cluster",
        action="store_true",
        help="Generate cluster schema only",
    )
    parser.add_argument(
        "--nodes",
        action="store_true",
        help="Generate nodes schema only",
    )
    args = parser.parse_args()

    resources_dir = Path(__file__).parent
    success = True

    # If no specific schema requested, generate all
    generate_all = not args.cluster and not args.nodes

    if args.cluster or generate_all:
        success &= generate_schema(
            resources_dir / "cluster.schema.cue",
            resources_dir / "cluster.schema.json",
            "cluster",
        )

    if args.nodes or generate_all:
        success &= generate_schema(
            resources_dir / "nodes.schema.cue",
            resources_dir / "nodes.schema.json",
            "nodes",
        )

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
