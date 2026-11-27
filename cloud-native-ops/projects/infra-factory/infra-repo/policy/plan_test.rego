# Unit tests for plan.rego: tiny fake plans, no cluster, no Terraform.   conftest verify --policy policy
package main

import rego.v1

ns(labels) := {"address": "module.environment.kubernetes_namespace_v1.this", "type": "kubernetes_namespace_v1", "change": {"after": {"metadata": [{"labels": labels}]}}}

quota := {"address": "q", "type": "kubernetes_resource_quota_v1", "change": {"after": {}}}

release(v) := {"address": "module.app.helm_release.chai_stall", "type": "helm_release", "change": {"after": {"values": [yaml.marshal(v)]}}}

good_labels := {"z2h/owner": "team", "z2h/cost-center": "cc-1", "pod-security.kubernetes.io/enforce": "restricted"}

good_values := {"env": "prod", "image": {"tag": "1.0.3"}, "replicaCount": 2, "podDisruptionBudget": {"enabled": true}, "autoscaling": {"enabled": true, "maxReplicas": 5}, "otlpEndpoint": "x"}

test_a_good_plan_has_no_denials if {
	count(deny) == 0 with input as {"resource_changes": [ns(good_labels), quota, release(good_values)]}
}

test_namespace_without_owner_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [ns(object.remove(good_labels, ["z2h/owner"])), quota]}
}

test_namespace_with_empty_owner_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [ns(object.union(good_labels, {"z2h/owner": ""})), quota]}
}

test_namespace_without_quota_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [ns(good_labels)]}
}

test_latest_tag_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [release(object.union(good_values, {"image": {"tag": "latest"}}))]}
}

test_prod_with_one_replica_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [release(object.union(good_values, {"replicaCount": 1}))]}
}

test_prod_without_pdb_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [release(object.union(good_values, {"podDisruptionBudget": {"enabled": false}}))]}
}

test_dev_with_one_replica_is_fine if {
	count(deny) == 0 with input as {"resource_changes": [release(object.union(good_values, {"env": "dev", "replicaCount": 1, "podDisruptionBudget": {"enabled": false}}))]}
}

test_runaway_autoscaler_is_denied if {
	count(deny) > 0 with input as {"resource_changes": [release(object.union(good_values, {"autoscaling": {"enabled": true, "maxReplicas": 50}}))]}
}
