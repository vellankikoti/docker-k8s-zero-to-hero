# O02 · State, modules and environments

> ⏱ 60 min · 🟡 · Needs: [O01](../O01-terraform-first-steps/README.md) done, and the Infra Factory started: `./cloud-native-ops/projects/infra-factory/scripts/up.sh`
> **You will:** look inside Terraform's memory, watch its lock refuse a second writer, see why modules exist, adopt something built by hand, and rename a resource without destroying it.

## 1. State: the architect's notebook
Terraform keeps a record of everything it built. Without it, it cannot tell *"build this"* from *"it is already built"*.
```bash
TF=./cloud-native-ops/projects/infra-factory/infra-repo/scripts/tf.sh   # a short name for the long path (paste again in a new terminal)
$TF dev plan && $TF dev apply
kubectl -n tfstate get secret                   # tfstate-default-iac-dev
$TF dev status                      # what it remembers: 8 resources
```
**Where should the notebook live?**
| Place | Verdict |
|---|---|
| a file on your laptop (`terraform.tfstate`) | lost with the laptop; the teammate does not have it; two people write at once and corrupt it |
| in Git | it contains **secrets in clear text** (you saw it in O01) and merges badly |
| **a shared backend with a lock** | ✔ one copy, one writer at a time, access-controlled. Ours: a Kubernetes **Secret + Lease** (see [`versions.tf`](../projects/infra-factory/infra-repo/terraform/versions.tf)). In the cloud: an S3 bucket + DynamoDB lock, GCS, Azure Blob, Terraform Cloud |

## 2. The lock, live
Two terminals, both in `infra-repo`. In **terminal 1** start an apply and **do not answer** the question:
```bash
cd terraform && terraform init -reconfigure -backend-config=envs/dev.backend.hcl -backend-config=config_path=$HOME/.kube/config >/dev/null
terraform apply -var-file=envs/dev.tfvars -var replicas=2        # stops at "Enter a value:"  (the lock is held)
```
In **terminal 2**:
```bash
$TF dev plan                                    # (paste the TF= line from above in this terminal first)
```
```
Error: Error acquiring the state lock     Lock Info:  Operation: OperationTypeApply  Who: you@laptop
```
Terminal 2 was **refused**. In real life that second "person" is often the pipeline, and the lock stops both from writing the notebook at once. Type `no` in terminal 1, and the lock is released. (A crashed run can leave a stale lock: `kubectl -n tfstate delete lease lock-tfstate-default-iac-dev`, *only* when you are sure nobody is running.)

## 3. Modules: write a recipe once
Open [`main.tf`](../projects/infra-factory/infra-repo/terraform/main.tf). Two blocks build a whole environment: `module "environment"` and `module "app"`. Open [`modules/environment/main.tf`](../projects/infra-factory/infra-repo/terraform/modules/environment/main.tf): the namespace, quota, defaults, network rules, role. A module is a **function**: variables in, resources and outputs out.
Why it matters: dev, staging and prod all call the **same** module with different numbers ([`envs/*.tfvars`](../projects/infra-factory/infra-repo/terraform/envs/)). Fix a bug in the module, and **every** environment gets the fix. Try:
```bash
diff terraform/envs/dev.tfvars terraform/envs/prod.tfvars       # the ONLY differences between environments
```
**One more subtle line:** `namespace = module.environment.namespace` in the `app` module. Using the *output* of one module as the *input* of another is what makes Terraform build the namespace first. Never write "depends on" if a reference can say it.

## 4. Environments: folders, files or workspaces?
| Way | How | Good | Careful |
|---|---|---|---|
| **one file per environment** (ours) | `tf.sh prod plan` picks `envs/prod.tfvars` + its own state Secret | clear, each env has its own state, easy to review | you must not forget the `-var-file` (the script never does) |
| a folder per environment | `envs/prod/main.tf` calls the modules | total freedom per env | copies drift apart |
| **workspaces** | `terraform workspace select prod` | one folder, many states | easy to apply to the wrong one by accident: many teams avoid them for prod |
A rule that has saved many people: **make the environment you are touching impossible to miss** (the script prints it; the namespace is `iac-prod`; production needs approval).

## 5. Adopt something built by hand: `import`
Someone made a namespace with `kubectl`. You want Terraform to own it, **without** recreating it:
```bash
kubectl create ns hand-made
mkdir -p ~/tf-import && cd ~/tf-import
cat > main.tf <<'EOF'
terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
  }
}
provider "kubernetes" { config_path = "~/.kube/config" }

resource "kubernetes_namespace_v1" "found" {
  metadata { name = "hand-made" }
}

import {
  to = kubernetes_namespace_v1.found
  id = "hand-made"
}
EOF
terraform init && terraform plan        # "1 to import, 0 to add, 0 to change, 0 to destroy"
terraform apply                         # the namespace is now in the state: Terraform owns it
```
## 6. Rename without destroying: `moved`
Change `found` to `renamed` in the file, **delete the `import` block**, and add:
```hcl
moved {
  from = kubernetes_namespace_v1.found
  to   = kubernetes_namespace_v1.renamed
}
```
`terraform plan` says *"has moved … 0 to add, 0 to change, 0 to destroy"*. Without `moved`, a rename would be **destroy + create**: for a database, that is a disaster. Read every plan for the words *destroy* and *replace*.
```bash
terraform destroy && cd ~ && rm -rf ~/tf-import
```

## ✅ You can now
Explain what state is and why it needs a lock and access control · see the lock refuse a writer · explain how modules and tfvars give three environments from one blueprint · adopt (`import`) and rename (`moved`) safely.
**Next:** [O03 pipelines for infrastructure](../O03-iac-in-cicd/README.md).

## 🧹 Clean up
`./cloud-native-ops/projects/infra-factory/scripts/cleanup.sh` (and `kubectl delete ns hand-made` if you stopped half way).
