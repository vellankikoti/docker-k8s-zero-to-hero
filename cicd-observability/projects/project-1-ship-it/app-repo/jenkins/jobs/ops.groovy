// DYNAMIC Job DSL: one loop creates the on-call engineer's "operations buttons".
// Each is the same small pipeline (ci/Jenkinsfile.ops) with a fixed ACTION, so there is no SSH and no kubectl to remember.
String gitUrl = System.getenv('GIT_URL') ?: 'http://gitea.cicd.svc.cluster.local:3000/z2h/chai-stall.git'

def opsJob = { String name, String desc, Closure params ->
  pipelineJob("chai-stall/${name}") {
    description(desc)
    definition {
      cpsScm {
        scm { git { remote { url(gitUrl); credentials('gitea') }; branch('*/main') } }
        scriptPath('ci/Jenkinsfile.ops')
        lightweight(false)
      }
    }
    parameters(params)
  }
}

['status', 'state', 'promote', 'rollback', 'retire'].each { action ->
  opsJob("ops-${action}", "Operations button: k8s-deploy.sh ${action}. Created by a loop in ops.groovy.") {
    choiceParam('ACTION', [action], 'fixed for this button')
  }
}

opsJob('ops-canary-any-tag', 'Release ANY tag already in the registry as a canary (a tag from build-info.json).') {
  choiceParam('ACTION', ['canary'], 'fixed for this button')
  stringParam('TAG', '', 'An existing image tag, for example 1.0.3')
  stringParam('PERCENT', '10', 'Percent of traffic')
}

listView('chai-stall/Operations') {
  jobs { regex('ops-.*') }
  columns { status(); weather(); name(); lastSuccess(); lastFailure(); buildButton() }
}
