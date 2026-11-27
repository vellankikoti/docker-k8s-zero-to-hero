# Cloud-Native Ops Cheat Sheet (Terraform, policy, reliability)

## Terraform
| Do | Command |
|---|---|
| install (no sudo) | `./cloud-native-ops/projects/infra-factory/infra-repo/scripts/install-terraform.sh` |
| download providers | `terraform init` |
| format · check | `terraform fmt -recursive` · `terraform validate` |
| the drawing | `terraform plan -out plan.tfplan` |
| build THAT plan | `terraform apply plan.tfplan` |
| remove it all | `terraform destroy` |
| what does it remember | `terraform state list` · `terraform output` |
| adopt / rename | `import { to = ... id = "..." }` · `moved { from = ... to = ... }` |
| drift check (exit 2 = drift) | `terraform plan -detailed-exitcode` |
Plan symbols: `+` create · `~` change · `-` destroy · `-/+` destroy and create again (**read twice**).

## The infra-factory wrapper (same for you and the pipeline)
```bash
cd cloud-native-ops/projects/infra-factory/infra-repo
./scripts/tf.sh dev check|plan|apply|drift|status|output|destroy        # dev | staging | prod
EXTRA_VAR_FILE=/tmp/x.tfvars ./scripts/tf.sh prod plan                  # an experiment, nothing committed
```

## Policy as code
```bash
terraform show -json plan.tfplan > plan.json
conftest test --policy policy plan.json            # the plan inspector
conftest verify --policy policy                    # the policy's own unit tests
kubectl get validatingadmissionpolicy,validatingadmissionpolicybinding    # the cluster's own rules (1.30+)
```

## Reliability and operations
| Do | Command |
|---|---|
| a rush of customers | `production-ready/scripts/rush.sh --seconds 90 --workers 4` |
| kill a Pod mid-rush | `production-ready/scripts/gameday.sh kill` |
| all the drills | `production-ready/scripts/gameday.sh all` |
| backup · disaster · restore | `ledger.sh backup` · `ledger.sh disaster` · `ledger.sh restore` |
| what does it cost | `production-ready/scripts/cost-report.py` |
| close dev at night | `production-ready/scripts/night-shift.sh enable` |
| DORA | `production-ready/scripts/dora.py --ns iac-prod --git ~/infra` |
| Helm release records (Terraform uses ConfigMaps) | `HELM_DRIVER=configmap helm ls -n iac-prod` |
| who may do what | `kubectl auth can-i delete nodes --as=system:serviceaccount:cicd:terraform-runner` |

## Words
**RPO** how much data you may lose · **RTO** how long you may be down · **drift** the cluster differs from the code · **state** Terraform's notebook · **module** a reusable recipe · **blast radius** how much one mistake can break · **FinOps** make cost visible, name it, automate the saving.
