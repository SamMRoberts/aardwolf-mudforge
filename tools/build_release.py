#!/usr/bin/env python3
"""Build deterministic MudForge repository artifacts for Aardwolf Core."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "release" / "manifest.json"
DIST = ROOT / "dist"


class BuildError(RuntimeError):
    pass


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BuildError(f"cannot read {path}: {exc}") from exc


def lua_metadata(source: str, table_name: str) -> dict[str, str]:
    match = re.search(rf"\b{re.escape(table_name)}\s*=\s*\{{(.*?)\n\}}", source, re.DOTALL)
    if not match:
        raise BuildError(f"missing {table_name} metadata table")
    body = match.group(1)
    values: dict[str, str] = {}
    for key in ("id", "name", "version", "author", "description", "license"):
        field = re.search(rf"\b{key}\s*=\s*\"([^\"]*)\"", body)
        if field:
            values[key] = field.group(1)
    return values


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=False, ensure_ascii=False) + "\n").encode("utf-8")


def validate_manifest(manifest: dict) -> None:
    if manifest.get("schemaVersion") != 1:
        raise BuildError("release manifest schemaVersion must be 1")
    version = manifest.get("version")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise BuildError("release version must be semantic x.y.z")
    if manifest.get("minClientVersion") != "1.2.2454":
        raise BuildError("minimum MudForge version must remain 1.2.2454 for Core 0.3")


def build_files(output: Path) -> dict[PurePosixPath, bytes]:
    manifest = read_json(MANIFEST_PATH)
    validate_manifest(manifest)
    version = manifest["version"]

    plugin_path = ROOT / manifest["plugin"]["source"]
    library_path = ROOT / manifest["library"]["source"]
    plugin_bytes = plugin_path.read_bytes()
    library_bytes = library_path.read_bytes()
    if len(library_bytes) > 256 * 1024:
        raise BuildError("library exceeds MudForge's 256 KB repository limit")

    plugin_meta = lua_metadata(plugin_bytes.decode("utf-8"), "plugin")
    library_meta = lua_metadata(library_bytes.decode("utf-8"), "library")
    expected_plugin = manifest["plugin"]["id"]
    expected_library = manifest["library"]["name"]
    if plugin_meta.get("id") != expected_plugin:
        raise BuildError("plugin id differs from release manifest")
    if library_meta.get("name") != expected_library:
        raise BuildError("library name differs from release manifest")
    if plugin_meta.get("version") != version or library_meta.get("version") != version:
        raise BuildError("plugin, library, and release versions must match")
    if plugin_meta.get("author") != "Sam Roberts" or library_meta.get("author") != "Sam Roberts":
        raise BuildError("author metadata must be Sam Roberts")
    if library_meta.get("license") != "MIT":
        raise BuildError("library metadata must declare MIT")

    plugin_download = f"files/{expected_plugin}.lua"
    library_download = f"libs/{expected_library}.lua"
    index = {
        "schemaVersion": 1,
        "name": manifest["name"],
        "description": manifest["description"],
        "plugins": [
            {
                "id": expected_plugin,
                "name": plugin_meta["name"],
                "version": version,
                "author": plugin_meta["author"],
                "description": plugin_meta["description"],
                "category": manifest["plugin"]["category"],
                "tags": manifest["plugin"]["tags"],
                "downloadUrl": plugin_download,
                "format": "lua",
                "sha256": digest(plugin_bytes),
                "size": len(plugin_bytes),
                "license": "MIT",
                "lastUpdated": manifest["releasedAt"],
                "featured": True,
            }
        ],
        "libraries": [
            {
                "name": expected_library,
                "version": version,
                "author": library_meta["author"],
                "description": library_meta["description"],
                "downloadUrl": library_download,
                "sha256": digest(library_bytes),
                "size": len(library_bytes),
                "license": "MIT",
                "tags": manifest["library"]["tags"],
                "lastUpdated": manifest["releasedAt"],
            }
        ],
    }
    package_input = {
        "formatVersion": 1,
        "packageId": manifest["packageId"],
        "name": manifest["packageName"],
        "version": version,
        "minClientVersion": manifest["minClientVersion"],
        "plugin": {
            "id": expected_plugin,
            "source": f"plugins/{expected_plugin}.lua",
            "sha256": digest(plugin_bytes),
            "size": len(plugin_bytes),
        },
        "library": {
            "name": expected_library,
            "source": f"libs/{expected_library}.lua",
            "sha256": digest(library_bytes),
            "size": len(library_bytes),
        },
        "note": "Package input only. Create the .mfp with MudForge Settings > Packages > Create Package.",
    }

    files = {
        PurePosixPath("plugin-repo") / plugin_download: plugin_bytes,
        PurePosixPath("plugin-repo") / library_download: library_bytes,
        PurePosixPath("plugin-repo/plugins.json"): json_bytes(index),
        PurePosixPath(f"native-package-input/plugins/{expected_plugin}.lua"): plugin_bytes,
        PurePosixPath(f"native-package-input/libs/{expected_library}.lua"): library_bytes,
        PurePosixPath("native-package-input/package-input.json"): json_bytes(package_input),
    }
    for relative, data in files.items():
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    return files


def compare_tree(expected_root: Path, actual_root: Path) -> list[str]:
    differences: list[str] = []
    expected = {p.relative_to(expected_root): p.read_bytes() for p in expected_root.rglob("*") if p.is_file()}
    actual: dict[Path, bytes] = {}
    for generated_dir in ("plugin-repo", "native-package-input"):
        current = actual_root / generated_dir
        if current.exists():
            actual.update({p.relative_to(actual_root): p.read_bytes() for p in current.rglob("*") if p.is_file()})
    for relative in sorted(set(expected) | set(actual), key=str):
        if relative not in actual:
            differences.append(f"missing {relative}")
        elif relative not in expected:
            differences.append(f"unexpected {relative}")
        elif expected[relative] != actual[relative]:
            differences.append(f"changed {relative}")
    return differences


def safe_members(archive: zipfile.ZipFile) -> list[str]:
    names: list[str] = []
    for info in archive.infolist():
        path = PurePosixPath(info.filename)
        if path.is_absolute() or ".." in path.parts:
            raise BuildError(f"unsafe archive path: {info.filename}")
        names.append(info.filename)
    return names


def verify_package(path: Path) -> None:
    if not path.is_file():
        raise BuildError(f"package not found: {path}")
    manifest = read_json(MANIFEST_PATH)
    with zipfile.ZipFile(path) as archive:
        names = safe_members(archive)
        if "world.json" in names:
            raise BuildError(".mfp must not contain world.json")
        if "package.json" not in names:
            raise BuildError(".mfp is missing package.json")
        package = json.loads(archive.read("package.json"))
        for key in ("packageId", "name", "version", "minClientVersion"):
            expected_key = "packageName" if key == "name" else key
            if package.get(key) != manifest.get(expected_key):
                raise BuildError(f"package {key} differs from release manifest")
        plugin_name = f"plugins/{manifest['plugin']['id']}.lua"
        library_name = f"libs/{manifest['library']['name']}.lua"
        for member, source in ((plugin_name, ROOT / manifest["plugin"]["source"]),
                               (library_name, ROOT / manifest["library"]["source"])):
            if member not in names:
                raise BuildError(f".mfp is missing {member}")
            if archive.read(member) != source.read_bytes():
                raise BuildError(f".mfp {member} differs from source")
    print(f"verified native package: {path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if dist differs from a clean build")
    parser.add_argument("--out", type=Path, default=DIST, help="output directory")
    parser.add_argument("--verify-package", type=Path, help="verify a client-created .mfp")
    args = parser.parse_args()
    try:
        if args.verify_package:
            verify_package(args.verify_package)
            return 0
        if args.check:
            with tempfile.TemporaryDirectory(prefix="aardwolf-core-build-") as temporary:
                expected_root = Path(temporary)
                build_files(expected_root)
                differences = compare_tree(expected_root, args.out)
                if differences:
                    raise BuildError("distribution is out of date:\n  " + "\n  ".join(differences))
            print("distribution matches deterministic build")
            return 0
        args.out.mkdir(parents=True, exist_ok=True)
        for generated_dir in ("plugin-repo", "native-package-input"):
            generated_path = args.out / generated_dir
            if generated_path.exists():
                shutil.rmtree(generated_path)
        build_files(args.out)
        print(f"built deterministic repository artifacts in {args.out}")
        print("native .mfp remains pending MudForge's Create Package workflow")
        return 0
    except (BuildError, OSError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(f"build error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
