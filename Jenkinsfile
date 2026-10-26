// Jenkinsfile — Zomato DevSecOps pipeline (Project 4, Azure VM)
// Repo: https://github.com/jeetvpatel108/zomato-devops-azure (branch: master)
// Order of checks: code quality -> dependencies -> files -> image, and the image
// is scanned BEFORE it is pushed to Docker Hub.

pipeline {
    agent any

    options {
        skipDefaultCheckout(true)          // we check out ourselves, after cleaning the workspace
        timestamps()                       // time on every log line (helps find slow stages)
        timeout(time: 60, unit: 'MINUTES') // a stuck build can't hold the only executor forever
        buildDiscarder(logRotator(numToKeepStr: '10'))  // keep disk usage bounded
    }

    tools {
        jdk    'jdk17'    // Manage Jenkins -> Tools (names must match exactly)
        nodejs 'node20'
    }

    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        IMAGE        = 'jeetpatel18109/zomato'
        // Trivy gate: '0' = report only, '1' = fail the build on fixable CRITICAL vulns.
        // Start with '0' to get a first green build, then switch to '1'.
        TRIVY_GATE   = '1'
    }

    stages {

        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout') {
            steps {
                script {
                    def scmVars = checkout scm
                    // Image tag = build number + short commit id, e.g. 7-a1b2c3d
                    env.TAG = "${env.BUILD_NUMBER}-${scmVars.GIT_COMMIT.take(7)}"
                }
                echo "Image will be ${IMAGE}:${TAG}"
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('mysonar') {
                    sh '''
                        "$SCANNER_HOME/bin/sonar-scanner" \
                          -Dsonar.projectKey=zomato \
                          -Dsonar.projectName=zomato \
                          -Dsonar.sources=src \
                          -Dsonar.exclusions=**/node_modules/**,**/build/**
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // Waits for SonarQube's webhook. If nothing arrives in 5 min, check
                // SonarQube -> Administration -> Webhooks -> "Last delivery".
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'node --version && npm --version'
                sh 'npm install --no-audit --no-fund'
            }
        }

        stage('OWASP Dependency-Check') {
            steps {
                withCredentials([string(credentialsId: 'nvd-api-key', variable: 'NVD_API_KEY')]) {
                    dependencyCheck odcInstallation: 'DP-Check',
                        additionalArguments: '--scan ./ --format XML --format HTML ' +
                                             '--disableYarnAudit --disableNodeAudit ' +
                                             '--nvdApiKey ' + env.NVD_API_KEY
                }
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }

        stage('Trivy FS Scan') {
            steps {
                sh 'trivy fs --scanners vuln,secret --severity HIGH,CRITICAL --format table -o trivy-fs.txt .'
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .'
            }
        }

        stage('Trivy Image Scan') {
            steps {
                // Scan BEFORE pushing: a failing gate stops the image from ever being published.
                sh '''
                    trivy image --scanners vuln --severity HIGH,CRITICAL --format table -o trivy-image.txt "$IMAGE:$TAG"
                    trivy image --scanners vuln --severity CRITICAL --ignore-unfixed --exit-code "$TRIVY_GATE" "$IMAGE:$TAG"
                '''
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withDockerRegistry(credentialsId: 'dockerhub-creds', url: 'https://index.docker.io/v1/') {
                    sh 'docker push "$IMAGE:$TAG"'
                    sh 'docker push "$IMAGE:latest"'
                }
            }
        }

        stage('Deploy Container') {
            steps {
                // Remove the previous container first, so re-runs don't fail with "name already in use".
                sh '''
                    docker rm -f zomato || true
                    docker run -d --name zomato --restart unless-stopped -p 3000:3000 "$IMAGE:$TAG"
                '''
                echo 'App: http://20.25.165.104:3000'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'trivy-*.txt, dependency-check-report.*', allowEmptyArchive: true
            sh 'docker image prune -f || true'   // remove dangling layers so the 30 GB disk doesn't fill up
        }
    }
}