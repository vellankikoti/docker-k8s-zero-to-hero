// Job DSL: Jenkins jobs written as code (Lab C03). The seed job (00-seed) runs every file in this folder.
// The repository the pipelines build is the one in the in-cluster Git server. (GIT_URL can override it.)
String gitUrl = System.getenv('GIT_URL') ?: 'http://gitea.cicd.svc.cluster.local:3000/z2h/chai-stall.git'

// A closure: a reusable recipe for "a pipeline whose steps live in a Jenkinsfile in Git".
def pipelineFromGit = { String jobName, String file, String desc, boolean poll ->
  pipelineJob("chai-stall/${jobName}") {
    description(desc)
    definition {
      cpsScm {
        scm {
          git {
            remote { url(gitUrl); credentials('gitea') }
            branch('*/main')
          }
        }
        scriptPath(file)
        lightweight(false)
      }
    }
    if (poll) {
      // The Gitea webhook starts builds at once; this poll is the safety net if a webhook is ever missed.
      triggers { scm('H/2 * * * *') }
    }
    logRotator { numToKeep(15) }
  }
}

pipelineFromGit('ci-cd',          'Jenkinsfile',            'Test, scan, build with Kaniko, push, deploy to staging, release to production.', true)
pipelineFromGit('dynamic-checks', 'Jenkinsfile.dynamic',    'Stages generated at run time from pipeline-config.json.', false)
pipelineFromGit('secrets-demo',   'ci/Jenkinsfile.secrets', 'Lab C04: how Jenkins protects a secret, and how easily you can still leak it.', false)
