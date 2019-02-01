resource "openstack_networking_network_v2" "openshift-private" {
  name           = "openshift"
  admin_state_up = "true"
  tags           = ["openshiftClusterID=${var.cluster_id}"]
}

resource "openstack_networking_subnet_v2" "nodes" {
  name       = "nodes"
  cidr       = "${var.cidr_block}"
  ip_version = 4
  network_id = "${openstack_networking_network_v2.openshift-private.id}"
  tags       = ["openshiftClusterID=${var.cluster_id}"]
}

resource "openstack_networking_port_v2" "masters" {
  name  = "master-port-${count.index}"
  count = "${var.masters_count}"

  admin_state_up     = "true"
  network_id         = "${openstack_networking_network_v2.openshift-private.id}"
  security_group_ids = ["${openstack_networking_secgroup_v2.master.id}"]
  tags               = ["openshiftClusterID=${var.cluster_id}"]

  fixed_ip {
    "subnet_id" = "${openstack_networking_subnet_v2.nodes.id}"
  }
}

resource "openstack_networking_trunk_v2" "masters" {
  name  = "master-trunk-${count.index}"
  count = "${var.trunk_support ? var.masters_count : 0}"
  tags  = ["openshiftClusterID=${var.cluster_id}"]

  admin_state_up = "true"
  port_id        = "${openstack_networking_port_v2.masters.*.id[count.index]}"
}

resource "openstack_networking_port_v2" "bootstrap_port" {
  name = "bootstrap-port"

  admin_state_up     = "true"
  network_id         = "${openstack_networking_network_v2.openshift-private.id}"
  security_group_ids = ["${openstack_networking_secgroup_v2.master.id}"]
  tags               = ["openshiftClusterID=${var.cluster_id}"]

  fixed_ip {
    "subnet_id" = "${openstack_networking_subnet_v2.nodes.id}"
  }
}

resource "openstack_networking_port_v2" "lb_port" {
  name = "lb-port"

  admin_state_up     = "true"
  network_id         = "${openstack_networking_network_v2.openshift-private.id}"
  security_group_ids = ["${openstack_networking_secgroup_v2.api.id}"]
  tags               = ["openshiftClusterID=${var.cluster_id}"]

  fixed_ip {
    "subnet_id" = "${openstack_networking_subnet_v2.nodes.id}"
  }
}

data "openstack_networking_network_v2" "external_network" {
  name     = "${var.external_network}"
  external = true
}

#resource "openstack_networking_floatingip_v2" "lb_fip" {
#  pool    = "${var.external_network}"
#  port_id = "${openstack_networking_port_v2.lb_port.id}"
#}

resource "openstack_networking_router_v2" "openshift-external-router" {
  name                = "openshift-external-router"
  admin_state_up      = true
  external_network_id = "${data.openstack_networking_network_v2.external_network.id}"
  tags                = ["openshiftClusterID=${var.cluster_id}"]
}

resource "openstack_networking_router_interface_v2" "nodes_router_interface" {
  router_id = "${openstack_networking_router_v2.openshift-external-router.id}"
  subnet_id = "${openstack_networking_subnet_v2.nodes.id}"
}

resource "openstack_lb_loadbalancer_v2" "internal_loadbalancer" {
  name = "internal_loadbalancer"
  description = "A loadbalancer that handles requests from within the cluster only"
  vip_subnet_id = "${openstack_networking_subnet_v2.nodes.id}"
}

resource "openstack_lb_listener_v2" "http_listener"{
  protocol = "HTTP"
  protocol_port = 80
  loadbalancer_id = "${openstack_lb_loadbalancer_v2.internal_loadbalancer.id}"
}

resource "openstack_lb_listener_v2" "https_listener"{
  protocol = "HTTPS"
  protocol_port = 443
  loadbalancer_id = "${openstack_lb_loadbalancer_v2.internal_loadbalancer.id}"
}

resource "openstack_lb_listener_v2" "ignition_listener"{
  protocol = "TCP"
  protocol_port = 49500
  loadbalancer_id = "${openstack_lb_loadbalancer_v2.internal_loadbalancer.id}"
}

resource "openstack_lb_listener_v2" "api_listener"{
  protocol = "HTTPS"
  protocol_port = 6443
  loadbalancer_id = "${openstack_lb_loadbalancer_v2.internal_loadbalancer.id}"
}

resource "openstack_lb_pool_v2" "http_pool"{
  protocol = "HTTP"
  lb_method   = "ROUND_ROBIN"
  listener_id = "${openstack_lb_listener_v2.http_listener.id}"
}

resource "openstack_lb_pool_v2" "https_pool"{
  protocol = "HTTPS"
  lb_method   = "ROUND_ROBIN"
  listener_id = "${openstack_lb_listener_v2.https_listener.id}"
}

resource "openstack_lb_pool_v2" "ignition_pool"{
  protocol = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = "${openstack_lb_listener_v2.ignition_listener.id}"
}

resource "openstack_lb_pool_v2" "api_pool"{
  protocol = "HTTPS"
  lb_method   = "ROUND_ROBIN"
  listener_id = "${openstack_lb_listener_v2.api_listener.id}"
}

resource "openstack_lb_member_v2" "http_member"{
  count = "${var.masters_count}"
  address = "${var.master_ips[count.index]}"
  protocol_port = "80"
  subnet_id = "${openstack_networking_subnet_v2.nodes.id}"
  pool_id = "${openstack_lb_pool_v2.http_pool.id}"
}
