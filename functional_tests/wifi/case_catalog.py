"""Load the human-readable Wi-Fi test catalogue used by pytest and Allure."""

from pathlib import Path

import yaml


CATALOGUE_PATH = Path(__file__).parent / "cases" / "wifi_restart_procfs.yml"


def load_cases():
    """Return ordered test cases from the maintained YAML test catalogue."""
    with CATALOGUE_PATH.open(encoding="utf-8") as source:
        data = yaml.safe_load(source)
    return [
        {"number": int(number), **details}
        for number, details in sorted(data["cases"].items(), key=lambda item: int(item[0]))
    ]


def select_cases(value):
    """Resolve the --wifi-case option to catalogue entries."""
    cases = load_cases()
    if value == "all":
        return cases
    if not value.isdigit():
        raise ValueError("--wifi-case must be 1-7 or 'all'")
    number = int(value)
    for case in cases:
        if case["number"] == number:
            return [case]
    raise ValueError("--wifi-case must be 1-7 or 'all'")
