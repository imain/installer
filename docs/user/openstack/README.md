# OpenStack Platform Support

Support for launching clusters on OpenStack is **experimental**.

This document discusses the requirements, current expected behavior, and how to
try out what exists so far.

## OpenStack Requirements

The installer assumes the following about the OpenStack cloud you run against:

* You must create a `clouds.yaml` file with the auth URL and credentials
    necessary to access the OpenStack cloud you want to use.  Information on
    this file can be found at
    https://docs.openstack.org/os-client-config/latest/user/configuration.html

* Swift must be enabled.  The user must have `swiftoperator` permissions and
  `temp-url` support must be enabled.
  * `openstack role add --user <user> --project <project> swiftoperator`
  * `openstack object store account set --property Temp-URL-Key=superkey`

* You may need to increase the security group related quotas from their default
  values.
  * For example: `openstack quota set --secgroups 100 --secgroup-rules 1000
    openshift`

## Current Expected Behavior

As mentioned, OpenStack support is still experimental.  The installer will
launch a cluster on an isolated tenant network.  To access your cluster, you
can create a floating IP address and assign it to the load balancer service VM.

* `openstack floating ip create ${EXTERNAL_NETWORK}`
* `openstack floating ip set --port lb-port ${FLOATING_IP_ADDRESS}`

The service VM also hosts a DNS server that has enough records to bring up the
cluster.  If you add the `${FLOATING_IP_ADDRESS}` as your first `nameserver`
entry in `/etc/resolv.conf`, the installer will be able to look up the address
needed to reach the API.

If you don’t expose the cluster and add a hosts entry, the installer will hang
trying to reach the API.  However, the cluster should still come up
successfully within the isolated network.

If you do expose the cluster, the installer should make it far enough along to
bring up the HA control plane and tear down the bootstrap node.  It will then
hang waiting for the console to come up.

`DEBUG Still waiting for the console route: the server is currently unable to
handle the request (get routes.route.openshift.io)`

## Using an External Load Balancer

This documents how to shift from the api VM load balancer (which is not
HA) to an external load balancer.

The load balancer must serve ports 6443, 443, and 80 to any users of
the system.  Port 49500 is for serving ignition startup configurations
to the OpenShift nodes and should not be reachable by the outside world.

The first step is to add floating IPs to all the master nodes. Usually
the public network here is named 'public':

* `openstack floating ip create --port master-port-0 <public network>`
* `openstack floating ip create --port master-port-1 <public network>`
* `openstack floating ip create --port master-port-2 <public network>`

Once complete you can see your floating IPs using:

* `openstack server list`

These floating IPs can then be used by the load balancer to access
the cluster.  An example haproxy configuration for port 6443 is below.
The other port configurations are identical.

```
listen <cluster name>-api-6443
    bind 0.0.0.0:6443
    mode tcp
    stats enable
    stats uri /haproxy?status
    balance roundrobin
    server ostest-master-2 <floating ip>:6443 check
    server ostest-master-0 <floating ip>:6443 check
    server ostest-master-1 <floating ip>:6443 check
```

Next step is to allow access to the network the load balancer is on:

* `openstack security group rule create master --remote-ip <subnet CIDR> --ingress --protocol tcp --dst-port 6443`
* `openstack security group rule create master --remote-ip <subnet CIDR> --ingress --protocol tcp --dst-port 443`
* `openstack security group rule create master --remote-ip <subnet CIDR> --ingress --protocol tcp --dst-port 80`

Where subnet CIDR is the network the load balancer is on.  You could
also specify a specific IP address with /32 if you wish.

You can verify the operation of the load balancer now if you wish, using the
curl commands given below.

Now the DNS entry for <cluster name>-api.<base domain> needs to be updated
to point to the new load balancer.  In our case the cluster name is
'ostest' and the domain is 'shiftstack.com':

* `<load balancer ip> ostest-api.shiftstack.com`

The external load balancer should now be operation along with your own
DNS solution.  It's best to test this configuration before removing
the api. The following curl command is an example of how
to check functionality:

`curl https://<loadbalancer-ip>:6443/version --insecure`

Result:

```json
{
  "major": "1",
  "minor": "11+",
  "gitVersion": "v1.11.0+ad103ed",
  "gitCommit": "ad103ed",
  "gitTreeState": "clean",
  "buildDate": "2019-01-09T06:44:10Z",
  "goVersion": "go1.10.3",
  "compiler": "gc",
  "platform": "linux/amd64"
}
```

Another useful thing to check is that the ignition configurations are only
available from within the deployment:

* `curl https://<loadbalancer ip>:49500/config/master --insecure`

Now that the DNS and load balancer has been moved, we can take down the existing
api VM:

* `openstack server delete <cluster name>-api`


## Reporting Issues

Please see the [Issue Tracker][issues_openstack] for current known issues.
Please report a new issue if you do not find an issue related to any trouble
you’re having.

[issues_openstack]: https://github.com/openshift/installer/issues?utf8=%E2%9C%93&q=is%3Aissue+is%3Aopen+openstack
