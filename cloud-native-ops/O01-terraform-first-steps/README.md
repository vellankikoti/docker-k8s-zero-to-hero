# O01 · Terraform: your first blueprint

> ⏱ 40 min · 🟢→🟡 · Needs: a cluster (`kubectl get nodes` works). Terraform gets installed for you.
> **You will:** write a blueprint for a namespace and a ConfigMap, read a plan, change it, see a Secret (and why it is *not* secret), and tear it down.

## Step 0: install Terraform (1 minute)
```bash
./cloud-native-ops/projects/infra-factory/infra-repo/scripts/install-terraform.sh
export PATH="$HOME/.local/bin:$PATH"          # if the script told you to
terraform version
```
It downloads the official release and **checks its SHA-256**. No sudo, no package manager.

## Step 1: the smallest blueprint
```bash
mkdir -p ~/tf-first && cd ~/tf-first
```
Create `main.tf`:
```hcl
terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"        # the cluster your kubectl already uses
}

variable "stall_name" {
  type    = string
  default = "first"
}

resource "kubernetes_namespace_v1" "stall" {
  metadata {
    name   = "tf-${var.stall_name}"
    labels = { "z2h/owner" = "me" }
  }
}

resource "kubernetes_config_map_v1" "menu" {
  metadata {
    name      = "menu"
    namespace = kubernetes_namespace_v1.stall.metadata[0].name      # a reference: Terraform builds the namespace FIRST
  }
  data = { chai = "10", samosa = "12" }
}

output "where" {
  value = kubernetes_namespace_v1.stall.metadata[0].name
}
```
```bash
terraform init          # downloads the provider (once)
terraform plan          # 🔍 the drawing: read every + line. "Plan: 2 to add, 0 to change, 0 to destroy."
terraform apply         # type yes
kubectl -n tf-first get cm menu -o yaml | head -12
```
Notice **the order**: Terraform worked out that the ConfigMap needs the namespace, because one **references** the other. You never wrote "first this, then that". That is a **dependency graph**.

## Step 2: change it, and read the plan like a detective
Edit `main.tf`: change `chai = "10"` to `chai = "12"`.
```bash
terraform plan
```
```
  ~ resource "kubernetes_config_map_v1" "menu" {
      ~ data = { ~ "chai" = "10" -> "12" }
```
`~` = change in place, `+` = create, `-` = destroy, `-/+` = destroy and create again (**read these twice**: they can mean downtime or lost data). Apply it.
Now run `terraform plan` again: **"No changes."** That is **idempotence**: asking again does nothing.

## Step 3: catch a hand-edit (drift)
```bash
kubectl -n tf-first patch cm menu --type=merge -p '{"data":{"chai":"1"}}'      # "chai at ₹1": someone edited by hand
terraform plan                                                                # Terraform sees "1" -> "12"
terraform apply                                                               # the blueprint wins
```

## Step 4: a Secret is not secret
```hcl
variable "admin_token" {
  type      = string
  sensitive = true                  # hides it in plan output
  default   = "s3cr3t-demo-token"   # a lab value; NEVER commit a real one: pass it with  export TF_VAR_admin_token=...
}

resource "kubernetes_secret_v1" "admin" {
  metadata {
    name      = "admin"
    namespace = kubernetes_namespace_v1.stall.metadata[0].name
  }
  data = { token = var.admin_token }
}
```
```bash
terraform apply
kubectl -n tf-first get secret admin -o jsonpath='{.data.token}' | base64 -d ; echo     # anyone with access reads it
grep -c "s3cr3t-demo-token" terraform.tfstate                                            # ...and it is in the state file, in plain text
```
Two lessons: **(1)** `sensitive = true` only hides it from *screen output*. **(2)** the **state** holds every secret in the clear, so *state is a secret*: this is why the infra-factory keeps it in a Secret in a locked namespace (`tfstate`) that only the pipeline's robot can read, instead of in a file on a laptop. Real teams go further: they keep the secret itself in a vault and let the cluster fetch it (External Secrets, Sealed Secrets, SOPS) so it never appears in Git or in state. See [O05](../O05-backup-security-cost/README.md).

## Step 5: variables per environment, and destroy
```bash
terraform apply -var stall_name=second          # a SECOND stall, from the same blueprint (it replaces the first: why? read the plan)
terraform destroy                                # removes exactly what this folder built, nothing else
kubectl get ns | grep tf- || echo "all gone"
```
That `-var` is how one blueprint becomes three environments. The infra-factory does it with a file per environment (`envs/dev.tfvars`).

## ✅ You can now
Read a plan; explain `+ ~ - -/+`; explain why references create an order; spot drift; explain why state and Secrets need care.
**Next:** [O02 state, modules, environments](../O02-state-modules-environments/README.md), then the real thing in [Infra Factory](../projects/infra-factory/README.md).

## 🧹 Clean up
```bash
cd ~ && rm -rf ~/tf-first          # (terraform destroy above already removed the cluster objects)
```
