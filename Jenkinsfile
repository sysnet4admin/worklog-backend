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
                sh 'exit 1'
            }
        }
        stage('Deploy Image') {
            steps {
                echo "Let's deploy the image"
            }
        }
    }
    post {
        always {
            echo 'Job finished. Sending slack notifications ..'
        }
        success {
            echo 'Build Success, Notifying to slack..'
            echo 'Slack: successful'
        }
        failure {
            echo 'Build Failed, Notifying to slack..'
            echo 'Slack: failed'
        }
        aborted {
            echo 'Build Aborted, Notifying to slack..'
            echo 'Slack: aborted'
        }
    }
}
