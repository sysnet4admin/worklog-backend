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
    // 컨트롤러에는 uv와 docker가 없다. 4.5의 podTemplate으로 뜨는 쿠버네티스 에이전트에서 실행한다.
    agent { label 'jenkins-jenkins-agent' }
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
            // 에이전트 Pod에 uv를 설치하고 테스트 환경만 준비한다. pytest 실행은 6.8부터.
            steps {
                echo "let's run a test for ${shortSHA} in ${branch}"
                echo "running test for ${fullSHA}"
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH=$HOME/.local/bin:$PATH
                    uv sync --extra dev
                '''
                echo 'Test Passed!'
            }
        }
        stage('Build Image') {
            steps {
                echo "Let's build the image for ${shortSHA} in ${branch}"
                echo "The change commit message to build is '${commitMessage}'"
                echo 'build successful and published image with the following tags:'
                echo "Tags: ${shortSHA}, ${fullSHA}"
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
