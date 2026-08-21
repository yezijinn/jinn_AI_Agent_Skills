import argparse
import re
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description="Query Android UIAutomator XML nodes.")
    parser.add_argument("xml_file")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--text")
    group.add_argument("--resource-id")
    group.add_argument("--content-desc")
    group.add_argument("--class-name")
    args = parser.parse_args()

    root = ET.parse(args.xml_file).getroot()
    key, value = next((k, v) for k, v in vars(args).items() if k in {"text", "resource_id", "content_desc", "class_name"} and v is not None)
    attr = {"resource_id": "resource-id", "content_desc": "content-desc", "class_name": "class"}.get(key, key)
    matches = []
    for node in root.iter("node"):
        actual = node.attrib.get(attr, "")
        if actual == value or (key == "text" and value.lower() in actual.lower()):
            bounds = node.attrib.get("bounds", "")
            center = None
            match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
            if match:
                try:
                    x1, y1, x2, y2 = map(int, match.groups())
                    center = ((x1 + x2) // 2, (y1 + y2) // 2)
                except ValueError:
                    center = None
            matches.append((node.attrib, center))

    if not matches:
        print("NO_MATCH")
        return 1
    for index, (attrs, center) in enumerate(matches, 1):
        print(f"MATCH {index}")
        for name in ("text", "resource-id", "content-desc", "class", "clickable", "enabled", "selected", "bounds"):
            if attrs.get(name):
                print(f"{name}={attrs[name]}")
        if center:
            print(f"center_x={center[0]} center_y={center[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
