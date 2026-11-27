# Policy as code for the infrastructure PLAN. Terraform prints what it is ABOUT to do as JSON; these rules read that JSON and
# refuse the change BEFORE anything touches the cluster. (The cluster has its own last line of defence: Pod Security and the
# admission policies you meet in the production-ready project. This is the earlier, cheaper gate.)
#
#   terraform show -json plan.tfplan > plan.json
#   conftest test --policy policy plan.json
package main

import rego.v1

# Everything the plan will create or update (a destroy has no "after").
changes contains rc if {
	some rc in input.resource_changes
	rc.change.after != null
}

namespaces contains rc if {
	some rc in changes
	rc.type == "kubernetes_namespace_v1"
}

releases contains rc if {
	some rc in changes
	rc.type == "helm_release"
}

# The values we pass to the chart are one YAML string inside the plan.
release_values(rc) := yaml.unmarshal(rc.change.after.values[0])

# 1. Every namespace says WHO owns it and WHO pays: otherwise nobody can be called at 3 a.m., and the bill has no name on it.
deny contains msg if {
	some rc in namespaces
	some label in ["z2h/owner", "z2h/cost-center"]
	object.get(rc.change.after.metadata[0].labels, label, "") == ""
	msg := sprintf("%s: the namespace has no %q label (who owns it? who pays?)", [rc.address, label])
}

# 2. Every namespace enforces Pod Security "restricted".
deny contains msg if {
	some rc in namespaces
	rc.change.after.metadata[0].labels["pod-security.kubernetes.io/enforce"] != "restricted"
	msg := sprintf("%s: Pod Security 'restricted' is not enforced", [rc.address])
}

# 3. A namespace never exists without a ResourceQuota next to it (fair share).
deny contains msg if {
	count(namespaces) > 0
	quotas := [rc | some rc in changes; rc.type == "kubernetes_resource_quota_v1"]
	count(quotas) < count(namespaces)
	msg := sprintf("the plan creates %d namespace(s) but only %d ResourceQuota(s)", [count(namespaces), count(quotas)])
}

# 4. An image tag names ONE build. "latest" names whatever someone pushed last (Lab D10).
deny contains msg if {
	some rc in releases
	tag := release_values(rc).image.tag
	tag in {"", "latest"}
	msg := sprintf("%s: image tag %q is not allowed: use a version such as 1.0.7", [rc.address, tag])
}

# 5. Production runs at least two Pods, and keeps a PodDisruptionBudget.
deny contains msg if {
	some rc in releases
	release_values(rc).env == "prod"
	release_values(rc).replicaCount < 2
	msg := sprintf("%s: production must run at least 2 replicas", [rc.address])
}

deny contains msg if {
	some rc in releases
	release_values(rc).env == "prod"
	not release_values(rc).podDisruptionBudget.enabled
	msg := sprintf("%s: production needs a PodDisruptionBudget", [rc.address])
}

# 6. A typo must not be able to spend the whole cluster: the autoscaler has a ceiling.
deny contains msg if {
	some rc in releases
	v := release_values(rc)
	v.autoscaling.enabled
	v.autoscaling.maxReplicas > 10
	msg := sprintf("%s: autoscaling maxReplicas %d is above the allowed 10", [rc.address, v.autoscaling.maxReplicas])
}

# A nudge, not a block.
warn contains msg if {
	some rc in releases
	release_values(rc).otlpEndpoint == ""
	msg := sprintf("%s: no traces are sent anywhere (otlp_endpoint is empty)", [rc.address])
}
