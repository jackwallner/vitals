#!/usr/bin/env python3
"""Check localized Swift literals and String Catalog coverage."""

from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIRS = ("Shared", "Vitals", "VitalsWidget", "VitalsWatch", "VitalsWatchWidget")
SUPPORTED_LANGUAGES = (
    "ar", "cs", "da", "de", "el", "es", "et", "fa", "fi", "fr", "he", "hi", "hr",
    "hu", "id", "it", "ja", "ko", "lv", "ms", "nb", "nl", "pl", "pt-BR", "pt-PT",
    "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
)
CATALOGS = (
    "Shared/Localizable.xcstrings",
    "Vitals/InfoPlist.xcstrings",
    "Vitals/AppShortcuts.xcstrings",
    "VitalsWatch/InfoPlist.xcstrings",
)
PLISTS = (
    "Vitals/Info.plist",
    "VitalsWidget/Info.plist",
    "VitalsWatch/Info.plist",
    "VitalsWatchWidget/Info.plist",
)
UI_FUNCTIONS = {
    "Text", "Button", "Label", "Section", "Toggle", "TextField", "navigationTitle",
    "accessibilityLabel", "accessibilityHint", "accessibilityValue", "alert",
    "confirmationDialog", "DatePicker", "Stepper", "Link", "configurationDisplayName",
    "description", "eyebrow", "Picker", "SecureField", "IntentDescription",
}
IGNORED_KEYS = {"0"}
FORMAT_SPECIFIER = re.compile(r"%(?:(\d+)\$)?(lld|@|%)|%#@(\w+)@")


def parse_literal(source: str, index: int) -> tuple[int, list[tuple[str, str]] | None]:
    """Parse a regular Swift string into literal and interpolation segments."""
    if source.startswith('"""', index):
        end = source.find('"""', index + 3)
        return (len(source) if end < 0 else end + 3), None

    segments: list[tuple[str, str]] = []
    buffer: list[str] = []
    cursor = index + 1

    while cursor < len(source):
        char = source[cursor]
        if char == '"':
            if buffer:
                segments.append(("literal", "".join(buffer)))
            return cursor + 1, segments
        if char != "\\":
            buffer.append(char)
            cursor += 1
            continue

        next_char = source[cursor + 1]
        if next_char == "(":
            if buffer:
                segments.append(("literal", "".join(buffer)))
                buffer = []
            depth = 1
            cursor += 2
            expression: list[str] = []
            while cursor < len(source) and depth:
                char = source[cursor]
                if char == '"':
                    end, _ = parse_literal(source, cursor)
                    expression.append(source[cursor:end])
                    cursor = end
                    continue
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                    if depth == 0:
                        break
                expression.append(char)
                cursor += 1
            segments.append(("interpolation", "".join(expression).strip()))
            cursor += 1
            continue

        escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}
        if next_char == "u" and cursor + 2 < len(source) and source[cursor + 2] == "{":
            end = source.index("}", cursor + 3)
            buffer.append(chr(int(source[cursor + 3 : end], 16)))
            cursor = end + 1
        else:
            buffer.append(escapes.get(next_char, next_char))
            cursor += 2

    return len(source), segments


def scan_source(path: Path) -> list[tuple[int, str, list[tuple[str, str]]]]:
    """Find string literals used as localizable UI arguments or app phrases."""
    source = path.read_text(encoding="utf-8")
    found: list[tuple[int, str, list[tuple[str, str]]]] = []
    stack: list[tuple[str, str, int]] = []
    index = 0
    line = 1

    while index < len(source):
        char = source[index]
        if char == "\n":
            line += 1
        if source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            end = len(source) if end < 0 else end + 2
            line += source[index:end].count("\n")
            index = end
            continue
        if char == '"':
            end, segments = parse_literal(source, index)
            if segments is not None:
                if segments and any(kind == "interpolation" and ".applicationName" in value for kind, value in segments):
                    found.append((line, "AppShortcut", segments))
                if stack:
                    function, argument, argument_index = stack[-1]
                    prefix = argument.rstrip()
                    is_localized_string = function == "String" and re.fullmatch(r"\s*localized\s*:\s*", argument)
                    is_direct_ui_argument = function in UI_FUNCTIONS and argument_index == 0 and not prefix
                    is_inline_ui_variant = (
                        function in UI_FUNCTIONS
                        and argument_index == 0
                        and prefix.endswith(("?", ":", "+"))
                    )
                    is_named_key = function in UI_FUNCTIONS and argument_index == 0 and re.fullmatch(
                        r"\s*(?:titleKey|title|label|placeholder|message|shortTitle)\s*:\s*", argument
                    )
                    if is_localized_string or is_direct_ui_argument or is_inline_ui_variant or is_named_key:
                        found.append((line, function, segments))
            line += source[index:end].count("\n")
            if stack:
                function, argument, argument_index = stack[-1]
                stack[-1] = (function, argument + source[index:end], argument_index)
            index = end
            continue
        if char == "(":
            match = re.search(r"([A-Za-z_][A-Za-z_0-9]*)\s*$", source[max(0, index - 80) : index])
            stack.append((match.group(1) if match else "", "", 0))
            index += 1
            continue
        if char == ")":
            if stack:
                stack.pop()
            index += 1
            continue
        if char == "," and stack:
            function, _, argument_index = stack[-1]
            stack[-1] = (function, "", argument_index + 1)
            index += 1
            continue
        if stack:
            function, argument, argument_index = stack[-1]
            stack[-1] = (function, argument + char, argument_index)
        index += 1

    return found


def loose_format_key(value: str) -> str:
    return re.sub(r"%(\d+\$)?(lld|@)", "%*", value)


def format_specifiers(value: str) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    automatic_index = 0
    for match in FORMAT_SPECIFIER.finditer(value):
        if match.group(2) == "%":
            continue
        if match.group(3):
            continue
        if match.group(1):
            position = int(match.group(1))
        else:
            automatic_index += 1
            position = automatic_index
        found.append((position, match.group(2) or "lld"))
    return sorted(set(found))


def literal_key(segments: list[tuple[str, str]]) -> str:
    has_interpolation = any(kind == "interpolation" for kind, _ in segments)
    value = []
    for kind, segment in segments:
        if kind == "interpolation":
            value.append("${applicationName}" if ".applicationName" in segment else "%@")
        else:
            value.append(segment.replace("%", "%%") if has_interpolation else segment)
    return "".join(value)


def localization_values(localization: dict[str, Any]) -> list[dict[str, Any]]:
    if "stringUnit" in localization:
        return [localization["stringUnit"]]
    plural = localization.get("variations", {}).get("plural", {})
    return [entry["stringUnit"] for entry in plural.values() if "stringUnit" in entry]


def check_catalog(path: Path, problems: list[str]) -> dict[str, Any]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("sourceLanguage") != "en":
        problems.append(f"{path.relative_to(ROOT)}: sourceLanguage must be en")
    strings = document["strings"]
    for key, entry in strings.items():
        if not key:
            # Xcode keeps this intentionally empty entry for explicit empty UI strings.
            continue
        localizations = entry.get("localizations", {})
        for language in SUPPORTED_LANGUAGES:
            localization = localizations.get(language)
            if localization is None:
                problems.append(f'{path.relative_to(ROOT)}: "{key}" is missing {language}')
                continue
            values = localization_values(localization)
            if not values:
                problems.append(f'{path.relative_to(ROOT)}: "{key}" [{language}] has no translated value')
                continue
            for unit in values:
                value = unit.get("value", "")
                if not value or unit.get("state") == "new":
                    problems.append(f'{path.relative_to(ROOT)}: "{key}" [{language}] has an empty or new value')
                if format_specifiers(key) and format_specifiers(value) != format_specifiers(key):
                    problems.append(
                        f'{path.relative_to(ROOT)}: "{key}" [{language}] format specifiers differ in "{value}"'
                    )
            if "${applicationName}" in key:
                source_count = key.count("${applicationName}")
                translated_text = "".join(unit.get("value", "") for unit in values)
                if translated_text.count("${applicationName}") != source_count:
                    problems.append(
                        f'{path.relative_to(ROOT)}: "{key}" [{language}] must keep ${{applicationName}} exactly once'
                    )
    return strings


def main() -> int:
    problems: list[str] = []
    catalog_data: dict[str, dict[str, Any]] = {}
    for relative_path in CATALOGS:
        path = ROOT / relative_path
        if not path.is_file():
            problems.append(f"{relative_path}: catalog is missing")
            continue
        catalog_data[relative_path] = check_catalog(path, problems)

    for relative_path in PLISTS:
        path = ROOT / relative_path
        if not path.is_file():
            problems.append(f"{relative_path}: Info.plist is missing")
            continue
        with path.open("rb") as file:
            localizations = plistlib.load(file).get("CFBundleLocalizations", [])
        missing = sorted((set(SUPPORTED_LANGUAGES) | {"en"}) - set(localizations))
        for language in missing:
            problems.append(f"{relative_path}: CFBundleLocalizations is missing {language}")

    shared_strings = catalog_data.get("Shared/Localizable.xcstrings", {})
    app_shortcuts = catalog_data.get("Vitals/AppShortcuts.xcstrings", {})
    shared_lookup = {loose_format_key(key): key for key in shared_strings}
    shortcuts_lookup = {key: key for key in app_shortcuts}
    for directory in SOURCE_DIRS:
        root = ROOT / directory
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            if "/Tests/" in path.as_posix() or "UITests" in path.parts:
                continue
            for line, context, segments in scan_source(path):
                key = literal_key(segments)
                if not key.strip() or key in IGNORED_KEYS:
                    continue
                if context == "AppShortcut":
                    if key not in shortcuts_lookup:
                        problems.append(f'{path.relative_to(ROOT)}:{line}: no AppShortcuts catalog key for "{key}"')
                    continue
                if loose_format_key(key) not in shared_lookup:
                    problems.append(f'{path.relative_to(ROOT)}:{line}: no shared catalog key for "{key}"')

    intent_resource_pattern = re.compile(r"LocalizedStringResource\s*=\s*(\"(?:\\.|[^\"\\])*\")")
    for path in sorted((ROOT / "Vitals").rglob("*.swift")):
        if "Tests" in path.parts:
            continue
        source = path.read_text(encoding="utf-8")
        for match in intent_resource_pattern.finditer(source):
            end, segments = parse_literal(match.group(1), 0)
            if segments is None:
                continue
            key = literal_key(segments)
            if loose_format_key(key) not in shared_lookup:
                line = source.count("\n", 0, match.start()) + 1
                problems.append(f'{path.relative_to(ROOT)}:{line}: no shared catalog key for "{key}"')

    if problems:
        print("\n".join(problems))
    print(f"{len(shared_strings)} shared keys, {len(SUPPORTED_LANGUAGES)} languages, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
