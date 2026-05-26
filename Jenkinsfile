def fullSHA
def shortSHA
def branch
def commitMessage
def targetEnvironment
def targetNamespace
def imageTag

def determineEnvironment() {
    if (env.TAG_NAME && env.TAG_NAME.startsWith('v')) {
        targetEnvironment = 'prod'
        targetNamespace = 'prod'
        imageTag = env.TAG_NAME
    } else if (env.BRANCH_NAME == 'develop') {
        targetEnvironment = 'dev'
        targetNamespace = 'dev'
        imageTag = "dev-${shortSHA}"
    } else if (env.BRANCH_NAME.startsWith('release/')) {
        targetEnvironment = 'staging'
        targetNamespace = 'staging'
        imageTag = "staging-${shortSHA}"
    } else if (env.BRANCH_NAME == 'main') {
        targetEnvironment = 'dev'
        targetNamespace = 'dev'
        imageTag = "dev-${shortSHA}"
    } else {
        targetEnvironment = 'dev'
        targetNamespace = 'dev'
        imageTag = "dev-${shortSHA}"
    }
}

def sendSlackMessage(statusMessage) {
    echo "Pipeline ${statusMessage}"
    echo "Environment: ${targetEnvironment}"
    echo "Namespace: ${targetNamespace}"
    echo "Image Tag: ${imageTag}"
    echo "Commit: ${commitMessage}"
}

pipeline {
    agent any

    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }

    stages {
        stage('Init Variables') {
            steps {
                script {
                    fullSHA = sh(script: "git log -n 1 --pretty=format:'%H'", returnStdout: true).trim()
                    shortSHA = fullSHA[0..7]
                    branch = env.BRANCH_NAME
                    commitMessage = sh(script: "git log -1 --format='*%s* by _%an_'", returnStdout: true).trim()
                    determineEnvironment()
                    echo "Target Environment: ${targetEnvironment}"
                    echo "Target Namespace: ${targetNamespace}"
                    echo "Image Tag: ${imageTag}"
                }
            }
        }

        stage('Run Test') {
            agent any
            steps {
                script {
                    echo "Running tests for ${shortSHA} on ${branch}"
                    sh '''
                        curl -LsSf https://astral.sh/uv/install.sh | sh
                        export PATH="$HOME/.local/bin:$PATH"
                        uv sync --extra dev
                        TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                        uv run coverage report
                    '''
                }
            }
        }

        stage('Build Image') {
            steps {
                script {
                    echo "Building image for ${branch} with tag ${imageTag}"
                    sh """
                        docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                        docker buildx rm backend-builder 2>/dev/null || true
                        docker buildx create --name backend-builder --driver docker-container --use
                        echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login --username ${DOCKERHUB_CREDENTIALS_USR} --password-stdin
                        docker buildx build --platform linux/amd64,linux/arm64 \\
                            -t ${DOCKER_REPOSITORY}:${imageTag} \\
                            --push .
                    """
                    echo "Build successful: ${imageTag}"
                }
            }
        }

        stage('Deploy') {
            steps {
                script {
                    echo "Deploying ${imageTag} to ${targetNamespace}"
                    sh """
                        sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${imageTag}|" deploy_manifest/worklog-backend.yaml
                        sed -i "s|value: .* # IMAGE_TAG|value: ${imageTag} # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                        git config user.name "jenkins"
                        git config user.email "jenkins@myk8s.local"
                        git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/sysnet4admin/worklog-backend.git
                        git add deploy_manifest/
                        git diff --staged --quiet || git commit -m "deploy: update image tag to ${imageTag} for ${targetNamespace}"
                        git pull --rebase origin HEAD:main || true
                        git push origin HEAD:main
                    """
                    echo "Deployed ${imageTag} to ${targetNamespace}"
                }
            }
        }
    }

    post {
        always {
            echo 'Job finished. Sending notifications ..'
        }
        success {
            echo 'Build Success'
            script { sendSlackMessage('completed') }
        }
        failure {
            echo 'Build Failed'
            script { sendSlackMessage('failed') }
        }
        aborted {
            echo 'Build Aborted'
            script { sendSlackMessage('aborted') }
        }
    }
}
