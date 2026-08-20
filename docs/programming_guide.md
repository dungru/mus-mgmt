# Programming Guide

## Commit The Code
```shell
git add -u
cz commit
git push origin <BRANCH_NAME>
```
<br/>


## Commit Style

* Using The tool [Commitizen](https://github.com/commitizen/cz-cli) as commit assistant

  ```shell
  cz commit
  ```


* The format of a commitment

  ```
  <TYPE>(<SCOPE>): <ISSUE_ID> YOUR_MESSAGE
  ```

  * TYPE
    * `fix`: A bug fix. Correlates with PATCH in SemVer
    * `feat`: A new feature. Correlates with MINOR in SemVer
    * `docs`: Documentation only changes
    * `style`: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
    * `refactor`: A code change that neither fixes a bug nor adds a feature
    * `perf`: A code change that improves performance
    * `test`: Adding missing or correcting existing tests
    * `build`: Changes that affect the build system or external dependencies (example scopes: pip, docker, npm)
    * `ci`: Changes to our CI configuration files and scripts (example scopes: GitLabCI)

  * SCOPE
    * The scope of this change (class or file name)
    * e.g. `apis`, `sdk`, `protocol`

  * [OPTION] ISSUE_ID
    * A given id from JIRA with `UPPER CASE`


* Example

  > feat(apis): add show_lldp_neighbors()

  > refactor(protocol): replace the statement `radv` by `arp_update`

  > feat(protocol): [SV-286] l3_routing/dhcp_relay/test_2

  > ci(sdk): Change jenkins clingenv path

<br/>


## Coding Style

### New Test Plan
* Naming of file and function:
  * must start with "test" in pytest
  * all lowercase
  * symbol / space to underscore


* Example :
  * The title of a test plan is `Test 1 – Untagged Frame Classification Test`, the file naming as `test_1_untagged_frame_classification_test.py`
  * The item in a test plan is "`A. Check VLAN setting`", the test function naming as `test_a_check_vlan_setting()`

<br/>


### Rule of Merge Request
* New apis in a branch of parent JIRA id, test flow in subtasks JIRA id e.g. [cli.py](http://cli.py) in feat/sv-185, test_1_...py in feat/sv-188
* Multi-tasks → Multiple commits (Do not commit once)
* Short summary in commit title, details in commit description, and add lines of comments in Gitlab
* Add scope for different files in commit
* In order to make reviewer **do cherry-pick correctly**, put same function set in single commit, do not put complex, combined functions in single commit
e.g.

    > commit 3 - fix: remove typo in function a()  # → reviewer can cherry-pick commit 1&3
    commit 2 - feat: add function b()
    commit 1 - feat: add function a()
    >

<br/>


### Programming Principles

#### Use fixtures for handling test dependencies, state, and reusable functionality

pytest fixtures are a way of providing data, test doubles, or state setup to your tests.

Fixtures are functions that can return a wide range of values. Each test that depends on a fixture must explicitly accept that fixture as an argument.

As a simple example, we want to test on Traffic Generator.
We make topo, then send to test function which need the traffic generator.

Here’s what that might look like:

```python
@pytest.fixture(scope="session")
def topo(request, monkeypatch_session, adhoc):
    topo = AttrDict()

    handler_chain = (
        request.config.getoption("--handler_chain").upper().split(",")
    )

    for host in adhoc.hosts:
        topo[host.name] = Dut(adhoc, host, handler_chain)

    topo["tg"] = TrafficGenerator(
        Setting(**adhoc.group_vars["traffic_generator"])
    )

    yield topo

    if not request.config.getoption("--skip_tg_teardown"):
        topo.tg.teardown()
  ```
Reference: [protocol_tests/conftest.py](protocol_tests/conftest.py)

```python
def test_a_check_vlan_setting(topo):
    """
    Steps:
      1. Reset the switch to the default and remove IP address of all interfaces.
      2. Stop LLDP service.
            # sudo systemctl stop lldp.service
      3. Create a VLAN and add DUT P101, P102 to the VLAN with tagged port.
            # sudo config vlan add 600
            # sudo config vlan member add 600 P101
            # sudo config vlan member add 600 P102
         Create another VLAN and add DUT P103 to the VLAN with tagged port.
            # sudo config vlan add 700
            # sudo config vlan member add 700 P103
      4. Check VLAN table
            # show vlan brief
    """
    # Step 1
    topo.dut1.factory_reset()
    wait_for(topo.dut1.is_ready, timeout=300)

    # Step 2.
    topo.dut1.disable_feature("lldp")
    wait_for(lambda: topo.dut1.is_feature_stopped("lldp"), timeout=15)

    # Step 3.
    vlan600 = VLAN(vlanid="600")
    p101 = VLAN_MEMBER(
        port_name=topo.dut1.p101.name, vlan=vlan600, tagging_mode="tagged"
    )
    p102 = VLAN_MEMBER(
        port_name=topo.dut1.p102.name, vlan=vlan600, tagging_mode="tagged"
    )
    topo.dut1.add(vlan600).add(p101).add(p102)

    vlan700 = VLAN(vlanid="700")
    p103 = VLAN_MEMBER(
        port_name=topo.dut1.p103.name, vlan=vlan700, tagging_mode="tagged"
    )
    topo.dut1.add(vlan700).add(p103)

    # Step 4.
    vlans, members, _ = topo.dut1.show_vlan_brief()
    assert set(vlans.values()) == {vlan600, vlan700} and set(
        members.values()
    ) == {
        p101,
        p102,
        p103,
    }, """The VLAN should be created and P101, P102 should be added to Vlan600
           and P103 should be added to Vlan700."""
```
Reference: [protocol_tests/l2_switching/vlan/test_2_tagged_frame_classification_test.py](protocol_tests/l2_switching/vlan/test_2_tagged_frame_classification_test.py)

<br/>


#### Use marks for categorizing tests and limiting access to external resources

pytest enables you to define categories for your tests and provides options for including or excluding categories when you run your suite.

You can mark a test with any number of categories. Because you can give your marks any name you want, it can be easy to mistype or misremember the name of a mark.

pytest will warn you about marks that it doesn’t recognize.
The `--strict-markers` flag to the pytest command ensures that all marks in your tests are registered in your pytest configuration.

It will prevent you from running your tests until you register any unknown marks.

For more information on registering marks, check out the [pytest documentation](https://docs.pytest.org/en/latest/how-to/mark.html#registering-marks). `pytest` provides a few marks out of the box:

* `skip` skips a test unconditionally.

  ```python
  def test_a_check_vlan_setting():
    pytest.skip("SONiC not support PVID, skipped.")
  ```
  Reference: [protocol_tests/l2_switching/vlan/test_3_pvid_test.py](protocol_tests/l2_switching/vlan/test_3_pvid_test.py)


* `skipif` skips a test if the expression passed to it evaluates to `True`.

* `xfail` indicates that a test is expected to fail, so if the test does fail, the overall suite can still result in a passing status.

* `parametrize` (note the spelling) creates multiple variants of a test with different values as arguments. You’ll learn more about this mark shortly.

<br/>


#### Use parametrization for reducing duplicated code between tests.

When you have several tests with slightly different inputs and expected outputs, you should parametrize a single test definition, and pytest will create variants of the test for you with the parameters you specify.

For example, you’ve written a function to create overlapping ip address on port P101. An initial set of tests could look like this:
```python
def test_d_ip_address_overlapping1(topo):
    with pytest.raises(SonicError):
      topo.dut1.add(INTERFACE(ifname=topo.dut1.p101.name, ip_addr="10.10.10.1/24"))

def test_d_ip_address_overlapping2(topo):
    with pytest.raises(SonicError):
      topo.dut1.add(INTERFACE(ifname=topo.dut1.p101.name, ip_addr="10.10.1.2/24"))

def test_d_ip_address_overlapping3(topo):
    with pytest.raises(SonicError):
      topo.dut1.add(INTERFACE(ifname=topo.dut1.p101.name, ip_addr="10.10.1.3/16"))
```

You can use `@pytest.mark.parametrize()` to fill in this shape with different values, reducing your test code significantly:
```python
@pytest.mark.parametrize(
    "ip_addr",
    [
        "10.10.10.1/24",
        "10.10.1.2/24",
        "10.10.1.3/16",
    ],
)
def test_d_ip_address_overlapping(topo, ip_addr):
    """
    Steps:
      8. Create overlapping ip address on port P101.
            # sudo config interface ip add P101 10.10.10.1/24
            # sudo config interface ip add P101 10.10.1.2/24
            # sudo config interface ip add P101 10.10.1.3/16
    """
    # Step 8.
    # FIXME all criteria cannot pass due to no error message here
    with pytest.raises(SonicError):
        topo.dut1.add(INTERFACE(ifname=topo.dut1.p101.name, ip_addr=ip_addr))
```
Reference: [protocol_tests/l3_routing/ipv4_port_route/test_2_netmask_configuration.py](protocol_tests/l3_routing/ipv4_port_route/test_2_netmask_configuration.py)
