def fullSHA
def shortSHA
def branch
def commitMessage

pipeline {
    agent any
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
            steps {
                echo "let's run a test for ${shortSHA} in ${branch}"
                echo "running test for ${fullSHA}"
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
        stage('Deploy Image') {
            steps {
                echo "Let's deploy the image"
                echo "Deploying our image ${fullSHA} to the cluster"
            }
        }
    }
    post {
        always {
            echo 'Job finished. Sending slack notifications ..'
        }
        success {
            echo 'Build Success, Notifying to slack..'
            echo 'Your pipeline has been completed'
            echo "Commit Message: ${commitMessage}"
            echo "Tags: ${shortSHA}, ${fullSHA}"
        }
        failure {
            echo 'Build Failed, Notifying to slack..'
            echo 'Your pipeline has been failed'
            echo "Commit Message: ${commitMessage}"
            echo "Tags: ${shortSHA}, ${fullSHA}"
        }
        aborted {
            echo 'Build Aborted, Notifying to slack..'
            echo 'Your pipeline has been aborted'
            echo "Commit Message: ${commitMessage}"
            echo "Tags: ${shortSHA}, ${fullSHA}"
        }
    }
}
