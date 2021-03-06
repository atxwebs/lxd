test_container_devices_nic_ipvlan() {
  ensure_import_testimage
  ensure_has_localhost_remote "${LXD_ADDR}"

  if ! lxc info | grep 'network_ipvlan: "true"' ; then
    echo "==> SKIP: No IPVLAN support"
    return
  fi

  ct_name="nt$$"
  ipRand=$(shuf -i 0-9 -n 1)

  # Test ipvlan support to offline container (hot plugging not supported).
  ip link add "${ct_name}" type dummy

  # Record how many nics we started with.
  startNicCount=$(find /sys/class/net | wc -l)

  # Check that starting IPVLAN container.
  sysctl net.ipv6.conf."${ct_name}".proxy_ndp=1
  sysctl net.ipv6.conf."${ct_name}".forwarding=1
  sysctl net.ipv4.conf."${ct_name}".forwarding=1
  lxc init testimage "${ct_name}"
  lxc config device add "${ct_name}" eth0 nic \
    nictype=ipvlan \
    parent=${ct_name} \
    ipv4.address="192.0.2.1${ipRand}" \
    ipv6.address="2001:db8::1${ipRand}" \
    mtu=1400
  lxc start "${ct_name}"

  # Check custom MTU is applied.
  if ! lxc exec "${ct_name}" -- ip link show eth0 | grep "mtu 1400" ; then
    echo "mtu invalid"
    false
  fi

  #Spin up another container with multiple IPs.
  lxc init testimage "${ct_name}2"
  lxc config device add "${ct_name}2" eth0 nic \
    nictype=ipvlan \
    parent=${ct_name} \
    ipv4.address="192.0.2.2${ipRand}, 192.0.2.3${ipRand}" \
    ipv6.address="2001:db8::2${ipRand}, 2001:db8::3${ipRand}"
  lxc start "${ct_name}2"

  # Check comms between containers.
  lxc exec "${ct_name}" -- ping -c2 -W1 "192.0.2.2${ipRand}"
  lxc exec "${ct_name}" -- ping -c2 -W1 "192.0.2.3${ipRand}"
  lxc exec "${ct_name}" -- ping6 -c2 -W1 "2001:db8::2${ipRand}"
  lxc exec "${ct_name}" -- ping6 -c2 -W1 "2001:db8::3${ipRand}"
  lxc exec "${ct_name}2" -- ping -c2 -W1 "192.0.2.1${ipRand}"
  lxc exec "${ct_name}2" -- ping6 -c2 -W1 "2001:db8::1${ipRand}"
  lxc stop -f "${ct_name}2"

  # Check IPVLAN ontop of VLAN parent.
  lxc stop -f "${ct_name}"
  lxc config device set "${ct_name}" eth0 vlan 1234
  lxc start "${ct_name}"

  # Check VLAN interface created
  if ! grep "1" "/sys/class/net/${ct_name}.1234/carrier" ; then
    echo "vlan interface not created"
    false
  fi

  lxc stop -f "${ct_name}"

  # Check parent device is still up.
  if ! grep "1" "/sys/class/net/${ct_name}/carrier" ; then
    echo "parent is down"
    false
  fi

  # Check we haven't left any NICS lying around.
  endNicCount=$(find /sys/class/net | wc -l)
  if [ "$startNicCount" != "$endNicCount" ]; then
    echo "leftover NICS detected"
    false
  fi

  # Cleanup ipvlan checks
  lxc delete "${ct_name}" -f
  lxc delete "${ct_name}2" -f
  ip link delete "${ct_name}" type dummy
}
