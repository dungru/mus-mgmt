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
    booleanParam(
      name: 'CONTINUE_ON_FAILURE',
      defaultValue: true,
      description: 'For functional tests, run all selected cases after a failure'
    )
  }

  stages {
    stage('Run tests') {
      steps {
        sh '''#!/bin/bash
          set -euo pipefail
          opts=""
          if [ "$TEST_TYPE" = "functional_tests" ] && \
             [ "$CONTINUE_ON_FAILURE" = "true" ]; then
            opts="--continue-on-failure"
          fi
          make test \
            TYPE="$TEST_TYPE" \
            ENV="$ENV" \
            TESTCASE="$TESTCASE" \
            OPTS="$opts" \
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
