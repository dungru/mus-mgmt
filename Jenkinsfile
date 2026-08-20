pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    choice(
      name: 'TEST_TYPE',
      choices: ['smoke_tests', 'functional_tests'],
      description: 'Test suite to execute'
    )
    string(name: 'ENV', defaultValue: 'dut115', description: 'Environment YAML name')
    string(
      name: 'TESTCASE',
      defaultValue: '',
      description: 'Optional path relative to the selected test suite'
    )
    booleanParam(
      name: 'AUTO_REPORT',
      defaultValue: true,
      description: 'Generate the static Allure report after pytest'
    )
  }

  stages {
    stage('Run tests') {
      steps {
        sh '''#!/bin/bash
          set -euo pipefail
          make test \
            TYPE="$TEST_TYPE" \
            ENV="$ENV" \
            TESTCASE="$TESTCASE" \
            AUTO_REPORT="$([ "$AUTO_REPORT" = "true" ] && echo 1 || echo 0)"
        '''
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/report/**, **/allure-report/**', allowEmptyArchive: true
    }
  }
}
