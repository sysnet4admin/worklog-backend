pipeline {
    agent any
    stages {
        stage('Run Test') {
            steps {
                echo "Let's run a test"
            }
        }
        stage('Build Image') {
            steps {
                echo "Let's build the image"
                error("Build Image 단계를 일부러 실패시킵니다")
            }
        }
        stage('Deploy Image') {
            steps {
                echo "Let's deploy the image"
            }
        }
    }
    post {
        success {
            echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} 빌드가 성공했습니다"
        }
        failure {
            echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} 빌드가 실패했습니다"
        }
    }
}
