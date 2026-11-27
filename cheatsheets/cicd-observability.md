# CI/CD & Observability Cheat Sheet

## Pipelines
| Need | Jenkins (Jenkinsfile) | GitHub Actions | GitLab CI |
|---|---|---|---|
| file | `Jenkinsfile` | `.github/workflows/x.yml` | `.gitlab-ci.yml` |
| run a command | `sh 'cmd'` | `run: cmd` | `script: [cmd]` |
| parallel | `parallel { stage(..){} }` | jobs w/o `needs`, `matrix` | same stage, `parallel: matrix` |
| depend on | stages in order | `needs: [a]` | `stages` + `needs: [a]` |
| only on main | `when { branch 'main' }` | `if: github.ref == 'refs/heads/main'` | `rules: - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` |
| manual gate | `input message: '..'` | `environment:` + reviewers | `when: manual` |
| secret | `withCredentials([string(credentialsId:'x', variable:'V')])` | `${{ secrets.X }}` | masked CI/CD variable |
| keep a file | `archiveArtifacts 'f'` | `actions/upload-artifact@v4` | `artifacts: paths: [f]` |
| cache | (agent disk / plugin) | `actions/cache` / `cache-from: type=gha` | `cache: paths:` |

## Jenkins in this track
```bash
cd cicd-observability/compose-edition/ship-it
cp .env.example .env && docker compose up -d --build     # Jenkins :8080 (admin / z2h-jenkins)
./scripts/verify.sh [N]                                   # did I do the phase?
./deploy/deploy.sh staging|rolling|bluegreen|canary IMAGE [PCT]
./deploy/deploy.sh promote | rollback | status | clean
./scripts/traffic-test.sh http://localhost:8090 15        # did users notice?
./scripts/registry-digest.sh 1.0.1                        # tag -> digest
```

## Deployment strategies
| | downtime | extra capacity | rollback | note |
|---|---|---|---|---|
| recreate | yes | 0 | redeploy | dev/staging |
| rolling | no | small | slow | two versions at once |
| blue/green | no | 2x | instant | flip the router |
| canary | no | small | instant | judge on the canary's OWN error rate |

## Prometheus / PromQL
```
up                                                          # 1 = scrape works
rate(http_requests_total[1m])                               # per-second rate of a counter
sum by (status) (rate(http_requests_total[1m]))             # aggregate, keep a label
sum(rate(x{status=~"5.."}[5m])) / sum(rate(x[5m]))          # ratio
histogram_quantile(0.95, sum by (le) (rate(x_bucket[5m])))  # p95
increase(orders_total[5m])                                  # growth over a window
topk(3, sum by (item) (rate(orders_total[5m])))
... or vector(0)                                            # "no series" -> 0
```
`curl -X POST localhost:9090/-/reload` reloads rules/config (needs `--web.enable-lifecycle`).

## promtool
```bash
promtool check config prometheus.yml
promtool check rules rules/*.yml
promtool test rules tests/rules_test.yml
```

## Alertmanager
`group_by` · `group_wait` · `group_interval` · `repeat_interval` · `routes` + `matchers` · `inhibit_rules` · silences:
```bash
amtool silence add alertname=X --duration=10m --comment="why" --author=me --alertmanager.url=http://localhost:9093
amtool silence query --alertmanager.url=http://localhost:9093
```

## LogQL (Loki)
```
{service="chai-1"}                              # stream selector (always first)
{service=~"chai-.*"} |= "error"                 # contains   (!=  |~  !~)
{service=~"chai-.*"} | json | level="error"     # parse JSON, filter on a field
... | json | __error__="" | status >= 500        # skip unparsable lines
sum by (level) (count_over_time({...} | json | __error__="" [1m]))   # logs -> numbers
```

## SLO maths
error budget = 1 − SLO · burn rate = error ratio ÷ budget · time to exhaust = window ÷ burn rate
99.9% / 30 d ≈ 43 min · 99.99% ≈ 4.3 min · page at 14.4× · ticket at 3×

## Incident
detect → triage (severity) → **mitigate (rollback first)** → resolve → blameless postmortem (timeline, impact, five whys, actions with owners)
