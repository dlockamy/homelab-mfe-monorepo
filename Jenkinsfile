// Jenkinsfile (CI only)

pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out source for CI validation.'
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    runPlatformCommand('npm install')
                }
            }
        }

        stage('Detect Changes') {
            steps {
                script {
                    def diffCmd = "git diff --name-only HEAD~1"
                    def changedFiles = runPlatformCommand(diffCmd).trim()

                    env.CORE_SHELL_CHANGED = changedFiles.contains("apps/core-shell/") ? "true" : "false"
                    env.BILLING_CHANGED = changedFiles.contains("apps/sub-route-billing/") ? "true" : "false"

                    echo "Core Shell Modified: ${env.CORE_SHELL_CHANGED}"
                    echo "Billing Sub-route Modified: ${env.BILLING_CHANGED}"
                }
            }
        }

        stage('Validate Core Shell') {
            when {
                environment name: 'CORE_SHELL_CHANGED', value: 'true'
            }
            steps {
                dir('apps/core-shell') {
                    script {
                        runPlatformCommand('npm install && npm run build')
                    }
                }
            }
        }

        stage('Validate Billing Sub-Route') {
            when {
                environment name: 'BILLING_CHANGED', value: 'true'
            }
            steps {
                dir('apps/sub-route-billing') {
                    script {
                        runPlatformCommand('npm install && npm run build')
                    }
                }
            }
        }
    }
}

// Keep the CI pipeline cross-platform by adapting shell invocations to the runner OS.
def runPlatformCommand(String command) {
    if (isUnix()) {
        return sh(script: command, returnStdout: true)
    } else {
        return bat(script: command, returnStdout: true)
    }
}
