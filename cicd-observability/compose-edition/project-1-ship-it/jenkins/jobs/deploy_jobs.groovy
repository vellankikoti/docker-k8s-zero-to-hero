// DYNAMIC Job DSL: one loop creates many jobs. Add a name to the list, run the seed job, get a new job.
// Each job is a small "operations button" on top of deploy/deploy.sh.

String deployScript = '/repo/cicd-observability/compose-edition/project-1-ship-it/deploy/deploy.sh'

['status', 'rollback', 'promote', 'clean'].each { action ->
  job("chai-stall/ops-${action}") {
    description("Operations button: deploy.sh ${action}. Created by a loop in deploy_jobs.groovy.")
    steps { shell("${deployScript} ${action}") }
  }
}

// A button with a parameter: roll any image tag from the registry out as a canary.
job('chai-stall/ops-canary-any-tag') {
  description('Release ANY tag already in the registry as a canary.')
  parameters {
    stringParam('TAG', '', 'An existing tag, for example 1.0.1 (see http://localhost:5001/v2/chai-stall/tags/list)')
    stringParam('PERCENT', '10', 'Percent of traffic')
  }
  steps { shell("${deployScript} canary localhost:5001/chai-stall:\$TAG \$PERCENT") }
}

listView('chai-stall/Operations') {
  jobs { regex('ops-.*') }
  columns { status(); weather(); name(); lastSuccess(); lastFailure(); buildButton() }
}
