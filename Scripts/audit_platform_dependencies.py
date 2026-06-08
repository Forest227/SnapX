#!/usr/bin/env python3

from __future__ import annotations

from collections import Counter, defaultdict
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = PROJECT_ROOT / "Sources" / "SnapX"

FRAMEWORK_IMPORTS = [
    "AppKit",
    "SwiftUI",
    "Carbon.HIToolbox",
    "Vision",
    "ServiceManagement",
]

API_MARKERS = {
    "windowing": ["NSWindow", "NSPanel", "NSPopover", "NSScreen", "NSStatusBar"],
    "capture": ["CGWindowList", "CGDisplay", "CGRequestScreenCaptureAccess", "CGPreflightScreenCaptureAccess"],
    "hotkeys": ["Carbon", "kVK_", "RegisterHotKey", "WM_HOTKEY"],
    "ocr": ["VNRecognizeTextRequest", "Vision"],
    "startup": ["SMAppService"],
    "alerts": ["NSAlert"],
}


def main() -> None:
    swift_files = sorted(SOURCE_ROOT.glob("*.swift"))
    import_counter: Counter[str] = Counter()
    category_hits: dict[str, list[tuple[str, list[str]]]] = defaultdict(list)

    print("# Platform Dependency Audit")
    print()
    print(f"Source root: `{SOURCE_ROOT}`")
    print(f"Swift files scanned: `{len(swift_files)}`")
    print()

    for path in swift_files:
        content = path.read_text(encoding="utf-8")
        file_imports = [framework for framework in FRAMEWORK_IMPORTS if f"import {framework}" in content]
        for framework in file_imports:
            import_counter[framework] += 1

        for category, markers in API_MARKERS.items():
            hits = [marker for marker in markers if marker in content]
            if hits:
                category_hits[category].append((path.name, hits))

    print("## Framework imports")
    print()
    for framework in FRAMEWORK_IMPORTS:
        print(f"- `{framework}`: {import_counter[framework]} file(s)")
    print()

    print("## macOS-tied capability map")
    print()
    for category in sorted(category_hits):
        print(f"### {category}")
        print()
        for file_name, hits in category_hits[category]:
            marker_list = ", ".join(f"`{marker}`" for marker in hits)
            print(f"- `{file_name}` -> {marker_list}")
        print()


if __name__ == "__main__":
    main()
