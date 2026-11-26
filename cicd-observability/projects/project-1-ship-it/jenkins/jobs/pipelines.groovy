// Job DSL: Jenkins jobs written as code. The seed job runs every file in this folder.
// Which repository and branch the pipelines build comes from the environment (.env), with safe defaults.
String repoUrl    = System.getenv('REPO_URL')    ?: 'file:///repo'
String repoBranch = System.getenv('REPO_BRANCH') ?: '*/main'

String projectPath = 'cicd-observability/projects/project-1-ship-it'

// A pipeline job whose steps live in a Jenkinsfile in Git ("Pipeline script from SCM").
def pipelineFromGit = { String jobName, String file, String desc, boolean poll ->
  pipelineJob("chai-stall/${jobName}") {
    description(desc)
    definition {
      cpsScm {
        scm {
          git {
            remote { url(repoUrl) }
            branch(repoBranch)
          }
        }
        scriptPath("${projectPath}/${file}")
        lightweight(false)
      }
    }
    if (poll) {
      triggers { scm('H/2 * * * *') }     // look for new commits every ~2 minutes
    }
    logRotator { numToKeep(15) }
  }
}

pipelineFromGit('ci-cd',          'Jenkinsfile',          'Test, scan, build, push, deploy. The main pipeline.', true)
pipelineFromGit('dynamic-checks', 'Jenkinsfile.dynamic',  'Stages generated at run time from pipeline-config.json.', false)

// Lab 06: a tiny pipeline written INLINE in the DSL, to experiment with secrets safely.
pipelineJob('chai-stall/secrets-demo') {
  description('Lab 06: how Jenkins protects a secret, and how easily you can still leak it.')
  definition {
    cps {
      sandbox(true)
      script('''
pipeline {
  agent any
  stages {
    stage('Use a secret') {
      steps {
        withCredentials([string(credentialsId: 'deploy-token', variable: 'TOKEN')]) {
          sh 'echo "1) printing it directly:   $TOKEN"'
          sh 'echo "2) length of the secret:   ${#TOKEN}"'
          sh 'echo "3) the same secret, reversed: $(echo $TOKEN | rev)"'
        }
        sh 'echo "4) outside the block:       [${TOKEN:-nothing here}]"'
      }
    }
  }
}
''')
    }
  }
}
