#!/usr/bin/python
# -*- coding: utf-8 -*-
import sys
from threading import Thread

from ansible.module_utils.basic import AnsibleModule

DOCUMENTATION = """
module: get_port_stats
version_added:  "1.0"

short_description: Get interfaces counter detailed in SONiC

Options:
    - option-name: ports
      description: the port list of DUT
      required: True
      type: list

"""

_RESULTS = {"ports_info": {}}
_PORTS_INFO = _RESULTS["ports_info"]


def show_interfaces_counters_detailed(module, iface):
    rc, out, err = module.run_command(
        "show interfaces counters detailed %s" % iface, use_unsafe_shell=True
    )
    # The return code of the command always as 0,
    # checking the variable `out` instead of return code
    if not out and rc == 0:
        msg = "show interfaces counters detailed"
        module.fail_json(
            msg="Failed %s: rc=%d, out=%s, err=%s" % (msg, rc, out, err)
        )

    _PORTS_INFO[iface] = out


def get_port_stats(module, ports):
    tasks = list()

    for p_name in ports:
        task = Thread(
            target=show_interfaces_counters_detailed, args=(module, p_name)
        )
        task.start()
        tasks.append(task)

    try:
        for t in tasks:
            t.join()
    except Exception as e:
        _RESULTS["get_port_stats"] = (
            "Error occurred while get_port_stats, Details: %s" % e
        )

    return 0, _RESULTS, ""


def main():
    module = AnsibleModule(
        argument_spec=dict(
            ports=dict(required=True, type="list"),
        ),
        supports_check_mode=False,
    )
    try:
        get_port_stats(module, module.params["ports"])
    except BaseException:
        err = str(sys.exc_info())
        module.fail_json(msg="Error: %s" % err)

    module.exit_json(**_RESULTS)


if __name__ == "__main__":
    main()
