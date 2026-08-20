# -*- coding: utf-8 -*-
import multiprocessing
import re
import time
from ipaddress import ip_network
from pathlib import Path


def wait_for(*func, condition_str=None, interval=1, timeout=60, delay=0):
    """
    Keeps calling the `func` until it returns true or `timeout` occurs
    every `interval`. `condition_str` should be a constant string
    implying the actual condition being tested.

    Args:
      func:
      condition_str:
      interval: Number of seconds to sleep between checks.
      timeout: Maximum number of seconds to wait for, when used with another
          condition it will force an error.
      delay: Number of seconds to wait before starting to poll.
    """
    time.sleep(delay)

    if not condition_str:
        condition_str = ", ".join(set(f.__name__ for f in func))

    def _wrapper():
        while True:
            res = all(f() for f in func)
            if res:
                break
            elif res is None:
                raise Exception(f"Wait aborted for {condition_str}")

            time.sleep(interval)

    p = multiprocessing.Process(target=_wrapper)
    p.start()
    p.join(timeout)
    if p.is_alive():
        p.kill()
        raise TimeoutError(
            f"Time out occurred while waiting for {condition_str}"
        )


def mac_str_to_int(macstr):
    return int(macstr.replace(":", ""), 16)


def mac_int_to_str(macint):
    return ":".join(re.findall("..", "%012x" % macint))


def gen_allure_env(request, properties_str):
    env_prop = Path(
        request.config.getoption("--alluredir"),
        "environment.properties",
    )
    with open(env_prop, "w") as fp:
        fp.write(properties_str)


def get_host_ips(adhoc, ip_type="ipv4"):
    ip_type = ip_type.lower()
    localhost_facts = adhoc.run(
        ["localhost"],
        "setup",
        gather_subset="network",
    )["localhost"]["ansible_facts"]
    mgmt_nets = adhoc.run(["dut1"], "setup", filter="ansible_eth0")["dut1"][
        "ansible_facts"
    ]["ansible_eth0"][ip_type]
    if not isinstance(mgmt_nets, list):
        mgmt_nets = [mgmt_nets]

    # get all available ip addresses
    networks = []
    for iface_name in localhost_facts.get("ansible_interfaces", []):
        inf = localhost_facts.get(f"ansible_{iface_name}", {})
        if ip_type == "ipv4":
            networks.append(inf.get(f"{ip_type}", None))
            networks.extend(inf.get(f"{ip_type}_secondaries", [None]))
        else:
            networks.extend(inf.get(f"{ip_type}", [None]))

    def _is_same_network(network):
        key = "prefix" if ip_type == "ipv6" else "netmask"
        return any(
            ip_network(f"{n['address']}/{n[key]}", strict=False)
            == ip_network(f"{network['address']}/{network[key]}", strict=False)
            for n in mgmt_nets
        )

    ip_addresses = []
    for net in filter(None, networks):
        # ignore ipv6 link local
        if ip_type == "ipv6" and net["scope"] == "link":
            continue

        if not _is_same_network(net):
            continue

        ip_addresses.append(net["address"])

    return ip_addresses
