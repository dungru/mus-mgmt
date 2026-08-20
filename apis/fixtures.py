# -*- coding: utf-8 -*-
import json
import logging
import re
from pathlib import Path

import pytest
import yaml
from _pytest.monkeypatch import MonkeyPatch
from ansible import constants
from ansible import context
from ansible.module_utils.common.collections import ImmutableDict
from ansible.utils import display
from scapy.all import Packet
from scapy.utils import hexdump
from snappi.snappi import OpenApiObject

from apis.ansible import AdHoc
try:
    from apis.sonic.dvt.dvt_pb2 import ResultValue
except (ImportError, TypeError):
    # Non-SONiC suites must not require SONiC's legacy generated protobufs.
    ResultValue = None


def _str_presenter(dumper, data):
    """configures yaml for dumping multiline strings"""
    if "\n" in data:  # check for multiline string
        return dumper.represent_scalar(
            "tag:yaml.org,2002:str",
            re.sub(r"\s+$", "", data, flags=re.M),
            style="|",
        )
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


yaml.add_representer(str, _str_presenter)


@pytest.fixture(scope="session")
def adhoc(request):
    # since the API is constructed for CLI it expects certain options to always
    # be set in the context object
    context.CLIARGS = ImmutableDict(
        connection="smart",
        verbosity=request.config.getoption("--verbosity"),
        become_user="root",
        become_method="sudo",
    )

    # Enable connection debugging
    ansible_display = display.Display()
    ansible_display.verbosity = request.config.getoption("--verbosity")

    environment_name = f"{request.config.getoption('--environment')}.yml"
    inventory_file = Path(
        request.config.invocation_params.dir, "environments", environment_name
    )
    if not inventory_file.exists():
        # Retain compatibility with legacy suites that keep environments at
        # the pytest root rather than beside the invoking test suite.
        inventory_file = Path(
            request.config.rootdir, "environments", environment_name
        )

    return AdHoc(str(inventory_file))


@pytest.fixture(scope="session", autouse=True)
def monkeypatch_session():
    m = MonkeyPatch()

    m.setattr(OpenApiObject, "__repr__", lambda self: self.serialize())
    m.setattr(Packet, "__repr__", lambda self: f"\n{hexdump(self, dump=True)}")
    if ResultValue is not None:
        m.setattr(
            ResultValue,
            "__repr__",
            lambda self: (
                f"isValid: {self.isValid}\n"
                f"ret_int: {self.ret_int}\n"
                f"[DUT] >>>>>>>>>> Console Log Start <<<<<<<<<<\n{self.output}"
                f"[DUT] >>>>>>>>>> Console Log End <<<<<<<<<<\n"
            ),
        )

    def _ansible_disply_verbose(self, msg, host=None, caplevel=2):
        if self.verbosity < caplevel:
            return

        if host is None:
            return

        text = list()
        if isinstance(msg, tuple):
            for m in msg:
                if isinstance(m, bytes):
                    text.append(str(m, "utf-8"))
                else:
                    text.append(str(m))
        else:
            text.append(str(msg))

        # remove dummy message
        text = "\n".join(
            t
            for t in text
            if t
            and not t.isdigit()
            and not t.startswith(
                (
                    "ESTABLISH SSH CONNECTION FOR USER:",
                    "Warning: Permanently added",
                    "Shared connection to",
                    "SSH: EXEC ",
                    "ansible-tmp-",
                    "PUT ",
                    "sftp> put",
                )
            )
        )

        if not text:
            return

        def _ret_filter(ret):
            """
            Recursively remove all dummy values from dictionaries and lists,
            and returns the result as a new dictionary or list.
            """
            if isinstance(ret, list):
                return [_ret_filter(i) for i in ret if i not in (None, "")]
            elif isinstance(ret, dict):
                return {
                    k: _ret_filter(v)
                    for k, v in ret.items()
                    if k not in ("invocation", "msg") and v not in (None, "")
                }
            else:
                return ret

        try:
            # pretty-print ansible returns
            # ref: https://docs.ansible.com/ansible/latest/reference_appendices/common_return_values.html
            text = yaml.dump(_ret_filter(json.loads(text)))
        except Exception:
            # if text is not an ansible returns, do noting
            pass

        self.display(
            f"# Ansible task on '{host}'\n{text}",
            color=constants.COLOR_VERBOSE,
        )

    m.setattr(display.Display, "verbose", _ansible_disply_verbose)

    def _get_logger(*args, **kwargs):
        return logging.root

    m.setattr(logging, "getLogger", _get_logger)

    yield m

    m.undo()


@pytest.fixture(scope="module", autouse=True)
def init_tg(topo):
    if hasattr(topo, "tg"):
        topo.tg.clear_all()
        port_list = [p.name for p in topo.tg.config.ports]
        topo.tg.link_up_ports(*port_list)
