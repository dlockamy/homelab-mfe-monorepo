// Jenkinsfile — CI. Builds both apps on every branch and PR.
//
// Discovered by the `dlockamy` GitHub org folder (variant '' => `Jenkinsfile`);
// the CD pipeline is `Jenkinsfile.cd`, picked up by the `dlockamy.cd` folder.
//
// Studio conventions followed here (all learned the hard way — see
// quickring/quickring.me/Jenkinsfile.cd for the history):
//   * `agent { label 'linux-build' }`, NOT `agent any`: `any` can land on the
//     controller, which has no docker CLI.
//   * Build inside a stock node image. No workspace write ever happens as
//     root (a later non-root build couldn't clean root-owned files), so the
//     container runs as Jenkins' own UID with HOME pointed at /tmp.
//
// The apps have no dependencies and build in seconds, so CI builds both every
// time rather than diffing for changes (a `git diff HEAD~1` check misses
// multi-commit pushes and fails outright on a first commit). Change detection
// lives in Jenkinsfile.cd, where it decides what to *deploy*.

pipeline {
    agent { label 'linux-build' }

    options {
        timeout(time: 10, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds(abortPrevious: true)
    }

    stages {
        stage('Build') {
            agent {
                docker {
                    image     'node:22-alpine'
                    reuseNode true
                    // HOME=/tmp: the container runs as an arbitrary UID with no
                    // home dir, and npm wants to write its cache/logs there.
                    args      '-e HOME=/tmp -e npm_config_cache=/tmp/.npm'
                }
            }
            steps {
                sh 'node --version && npm --version'
                // Parallel so a break in one app doesn't hide a break in the other.
                script {
                    def apps = ['core-shell', 'sub-route-billing']
                    parallel apps.collectEntries { app ->
                        ["Build ${app}": {
                            dir("apps/${app}") {
                                sh 'npm run build'
                            }
                        }]
                    }
                }
            }
        }

        stage('Check output') {
            steps {
                // A build that "succeeds" but emits nothing is still broken.
                sh '''#!/bin/sh
                    set -eu
                    test -s apps/core-shell/dist/index.html
                    test -s apps/sub-route-billing/dist/main.js
                    # the billing bundle must not still import the monorepo alias
                    # (browsers can't resolve it) — build.js is supposed to inline it
                    if grep -q "@mfe/shared-contracts" apps/sub-route-billing/dist/main.js; then
                        echo "billing bundle still imports @mfe/shared-contracts" >&2
                        exit 1
                    fi
                    echo "build output OK"
                '''
            }
        }
    }
}
