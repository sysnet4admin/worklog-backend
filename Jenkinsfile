def notify(String result) {
    echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} 빌드가 ${result}"
}

pipeline {
    agent any
    stages {
        stage('Run Test') {
            steps {
                echo "Let's run a test"
                script {
                    env.IMAGE_TAG = "build-${env.BUILD_NUMBER}"
                }
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
