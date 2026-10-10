def notify(String result) {
    echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} 빌드가 ${result}"
}

pipeline {
    // label은 ch4.5 jenkins-config.yaml의 podTemplate label과 일치해야 한다.
    agent { label 'jenkins-jenkins-agent' }
    stages {
        stage('Run Test') {
            steps {
                echo "Let's run a test"
                script {
                    env.IMAGE_TAG = "build-${env.BUILD_NUMBER}"
                }
                // 에이전트 pod에 uv를 직접 설치해 테스트 환경을 준비한다.
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH=$HOME/.local/bin:$PATH
                    uv sync --extra dev
                '''
            }
        }
        stage('Build Image') {
            steps {
                echo "Let's build the image: ${env.IMAGE_TAG}"
            }
        }
        stage('Deploy Image') {
            steps {
                echo "Let's deploy the image: ${env.IMAGE_TAG}"
            }
        }
    }
    post {
        success {
            notify('성공했습니다')
        }
        failure {
            notify('실패했습니다')
        }
    }
}
