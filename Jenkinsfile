def fullSHA
def shortSHA
def branch
def commitMessage

def sendSlackMessage(statusMessage, commitMessage, shortSHA, fullSHA) {
    echo "Your pipeline has been ${statusMessage}"
    echo "Commit Message: ${commitMessage}"
    echo "Tags: ${shortSHA}, ${fullSHA}"
}

pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트(JCasC kubernetes cloud)에서 실행.
    // docker.build()/withRegistry()가 동작하려면 이 에이전트가 필수. label은 ch4.5 jenkins-config.yaml과 일치.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
    }
    stages {
        stage('Init Variables') {
            steps {
                script {
                    fullSHA = sh(script: "git log -n 1 --pretty=format:'%H'", returnStdout: true)
                    shortSHA = fullSHA[0..8]
                    branch = env.BRANCH_NAME
                    commitMessage = sh(script: "git log -1 --format='*%s* by _%an_'", returnStdout: true)
                }
            }
        }
        stage('Run Test') {
            // 에이전트 pod에 uv를 직접 설치해 실행(중첩 docker agent 대신 — 환경에 따라 불안정).
            steps {
                echo "let's run a test for ${shortSHA} in ${branch}"
                echo "running test for ${fullSHA}"
                sh '''
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                    export PATH=$HOME/.local/bin:$PATH
                    uv sync --extra dev
                '''
                echo 'Test Passed!'
            }
        }
        stage('Build and Push Image') {
            steps {
                script {
                    echo "Let's build the image for ${shortSHA} in ${branch}"
                    echo "The change commit message to build is '${commitMessage}'"

                    def app = docker.build("${DOCKER_REPOSITORY}:${shortSHA}")

                    docker.withRegistry('https://index.docker.io/v1/', 'dockerhub-credentials') {
                        app.push("${shortSHA}")
                        app.push("${fullSHA}")
                    }

                    echo 'build successful and published image with the following tags:'
                    echo "Tags: ${shortSHA}, ${fullSHA}"
                }
            }
        }
    }
    post {
        always {
            echo 'Job finished. Sending slack notifications ..'
        }
        success {
            echo 'Build Success, Notifying to slack..'
            sendSlackMessage('completed', commitMessage, shortSHA, fullSHA)
        }
        failure {
            echo 'Build Failed, Notifying to slack..'
            sendSlackMessage('failed', commitMessage, shortSHA, fullSHA)
        }
        aborted {
            echo 'Build Aborted, Notifying to slack..'
            sendSlackMessage('aborted', commitMessage, shortSHA, fullSHA)
        }
    }
}
