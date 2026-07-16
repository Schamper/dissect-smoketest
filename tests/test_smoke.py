from dissect.target import Target

from tests.conftest import ImageInfo


def test_target_opens(image: ImageInfo) -> None:
    target = Target.open(image["path"])
    assert target is not None


def test_target_detects_os(image: ImageInfo) -> None:
    target = Target.open(image["path"])
    assert target.os


def test_target_has_hostname(image: ImageInfo) -> None:
    target = Target.open(image["path"])
    assert target.hostname
