"""DUT adapter for Buildroot targets."""

from .base import BaseDut


class BuildrootDut(BaseDut):
    system = "buildroot"
