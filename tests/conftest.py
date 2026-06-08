from collections.abc import Iterator
from pathlib import Path
from typing import TypedDict

import pytest
from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).parent.parent
TEMPLATES_ROOT = REPO_ROOT / "templates"
BUILD_ROOT = REPO_ROOT / "local" / "build"


class ImageInfo(TypedDict):
    name: str
    os: str | None
    markers: set[str]
    lifecycle: str
    path: Path | str | None


def _discover() -> Iterator[ImageInfo]:
    for sidecar in TEMPLATES_ROOT.rglob("image.yml"):
        with sidecar.open() as fh:
            meta = YAML(typ="safe").load(fh)

        template_dir = sidecar.parent
        name = template_dir.name
        lifecycle = template_dir.parent.name

        disks: list[Path] = []
        n = 0
        while (p := BUILD_ROOT / lifecycle / name / ("disk" if n == 0 else f"disk-{n}")).exists():
            disks.append(p)
            n += 1

        yield {
            "name": name,
            "os": meta.get("os"),
            "markers": set(meta.get("markers", [])),
            "lifecycle": lifecycle,
            "path": disks[0] if len(disks) == 1 else ("+".join(str(p) for p in disks) if disks else None),
        }


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "_image" not in metafunc.fixturenames:
        return

    # TODO: filter by markers
    matched = list(_discover())
    metafunc.parametrize("_image", matched, ids=[img["name"] for img in matched])


@pytest.fixture
def image(_image: ImageInfo) -> ImageInfo:
    if _image["path"] is None:
        pytest.skip(f"image not built locally: {_image['name']}")
    return _image
