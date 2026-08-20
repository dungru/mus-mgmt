#!/usr/bin/python
# -*- coding: utf-8 -*-
import re
import sys
from threading import Thread

from ansible.module_utils.basic import AnsibleModule

DOCUMENTATION = """
module: container_checker
version_added:  "1.0"

short_description: To checking the status of the necessary components in SONiC

Options:
    - option-name: features
      description: the name of daemon in the containers
      required: True
      type: list

"""

_RESULTS = {}


def exec_command(module, cmd, ignore_error=False, msg="executing command"):
    rc, out, err = module.run_command(cmd, use_unsafe_shell=True)
    if not ignore_error and rc != 0:
        module.fail_json(
            msg="Failed %s: rc=%d, out=%s, err=%s" % (msg, rc, out, err)
        )
    return rc, out, err


def is_feature_stopped(module, name):
    _, out, _ = exec_command(
        module,
        "docker ps -f status=exited -f name=%s -q" % name,
        msg="check critical feature",
    )
    return "" != out


def container_checker(module, features):
    exec_command(module, "container_checker", msg="container checker")

    failed = []

    def _is_ready(feature):
        if is_feature_stopped(module, feature):
            return

        # get critical processes list
        path = "/etc/supervisor/critical_processes"
        rc, out, err = exec_command(
            module,
            "docker exec %s sh -c 'test -f %s && cat %s'"
            % (feature, path, path),
            msg="get critical processes list",
        )

        critical_processes = set(
            re.findall(
                r"program:(\S+)",
                out,
            )
        )

        # Skip 'dsserve' process since it was not managed by supervisord
        critical_processes.discard("dsserve")

        if not critical_processes:
            _RESULTS["get_critical_processes_list"] = {
                "rc": False,
                "message": out,
                "error": "critical process not found",
            }
            return

        # check critical processes status
        rc, out, err = exec_command(
            module,
            "docker exec %s sh -c 'supervisorctl status || exit 0'" % feature,
            msg="check critical processes status",
        )

        status = re.findall(
            r"(\S+)\s+(\S+)\s+.*",
            out,
        )
        if not critical_processes.issubset(
            set(p for p, s in status if s == "RUNNING")
        ):
            failed.append(feature)

    tasks = []
    for f in features:
        task = Thread(target=_is_ready, args=(f,))
        task.start()
        tasks.append(task)

    try:
        for t in tasks:
            t.join()
    except Exception as e:
        _RESULTS["task_critical_processes"] = (
            "Error occurred while check container status, Details: %s" % e
        )
    return 0, _RESULTS, ""


def main():
    module = AnsibleModule(
        argument_spec=dict(
            features=dict(required=True, type="list"),
        ),
        supports_check_mode=False,
    )
    try:
        container_checker(module, module.params["features"])
    except BaseException:
        err = str(sys.exc_info())
        module.fail_json(msg="Error: %s" % err)

    module.exit_json(**_RESULTS)


if __name__ == "__main__":
    main()
