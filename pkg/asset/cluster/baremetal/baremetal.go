// Package baremetal extracts bare metal metadata from install
// configurations.
package baremetal

import (
	"context"
	"github.com/pkg/errors"
	//"fmt"
	"github.com/openshift/installer/pkg/terraform"
	"github.com/openshift/installer/pkg/types"
	"github.com/openshift/installer/pkg/types/baremetal"
	"github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"

	"github.com/openshift/installer/pkg/asset/installconfig"
)

// Metadata converts an install configuration to bare metal metadata.
func Metadata(config *types.InstallConfig) *baremetal.Metadata {
	return &baremetal.Metadata{
		LibvirtURI: config.Platform.BareMetal.LibvirtURI,
	}
}

// PostTerraform gathers information about the masters and updates the
// baremetalhost CR.
func PostTerraform(ctx context.Context, tfStateFile string, clusterID string, installConfig *installconfig.InstallConfig) error {

	logrus.Debugf("In bmh_update - file %s", tfStateFile)

	tfstate, err := terraform.ReadState(tfStateFile)
	mrs, err := terraform.LookupResource(tfstate, "module.masters", "ironic_introspection", "openshift-master-introspection")
	//mrs, err := terraform.LookupResource(tfstate, "module.masters")
	logrus.Debugf("In bmh_update - file %s - data %s", tfStateFile, tfstate)
	logrus.Debugf("mrs is %s", mrs)

	if err != nil {
		return errors.Wrap(err, "failed to lookup masters introspection data")
	}

	var errs []error
	var masters []string
	for idx, inst := range mrs.Instances {
		interfaces, _, err := unstructured.NestedSlice(inst.Attributes, "interfaces")
		if err != nil {
			errs = append(errs, errors.Wrapf(err, "could not get interfaces for master-%d", idx))
		}
		ip, _, err := unstructured.NestedString(interfaces[0].(map[string]interface{}), "ip")
		masters = append(masters, ip)
	}
	logrus.Debugf("In bmh_update - master ips are %s", masters)

	for _, host := range installConfig.Config.Platform.BareMetal.Hosts {
		logrus.Debugf("In bmh_update - host struct %+v", host)
	}

	return nil
}
