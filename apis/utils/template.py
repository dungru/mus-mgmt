# -*- coding: utf-8 -*-
from io import BytesIO
from pathlib import Path

from textfsm import TextFSM

_BASEDIR = Path(
    str(Path(__file__).parent),
    "templates",
)
TEMPLATES = dict()


def parse_output(tmpl, output):
    if tmpl not in TEMPLATES.keys():
        with open(Path(_BASEDIR, tmpl), "rb") as f:
            TEMPLATES[tmpl] = BytesIO(f.read())

    return TextFSM(TEMPLATES[tmpl]).ParseTextToDicts(output)


def __utest():
    """
    A test function to ensure raw output of DUT can be parsed correctly
    with our TextFSM templates.

    Usage:
      Place "command outputs" and "expected parsed result" respectively
      in key "raw:" and "expect:" of yml files (whose filename should be
      the same as tmpl files), and run test as follows:

          pipenv run python apis/utils/template.py

      If AssertionError raised, the message will also present the failure case.
    """
    import yaml
    import json

    for tmpl_path in Path(_BASEDIR).rglob("*.tmpl"):
        yml_path = tmpl_path.with_suffix(".yml")
        print(f"==> testing: {yml_path}")
        with open(yml_path) as f:
            test_data = yaml.safe_load(f)

            for idx, d in enumerate(test_data):
                try:
                    tmpl_name = str(tmpl_path).replace(str(_BASEDIR), "")[1:]
                    yml_name = Path(tmpl_name).with_suffix(".yml")
                    assert json.loads(d["expect"]) == parse_output(
                        tmpl_name, d["raw"]
                    ), (
                        "the parsed result should be identical as expected\n"
                        f'  in "{yml_name}", case {idx + 1}'
                    )

                except AssertionError as e:
                    print(f"[Assert failed] {e}")

                except Exception as e:
                    print(f"[Exception raised] {e}")


if __name__ == "__main__":
    __utest()
