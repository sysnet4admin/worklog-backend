pipeline {
    agent any
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                }
            }
        }
        stage('Run Test') {
            steps {
                sh '''
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report
                '''
            }
        }
        stage('Build Image') {
            steps {
                sh """
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    docker login -u ${DOCKERHUB_CREDENTIALS_USR} -p ${DOCKERHUB_CREDENTIALS_PSW}
                    docker buildx build \\
                        --platform linux/amd64,linux/arm64 \\
                        -t ${DOCKER_REPOSITORY}:${SHORT_SHA} \\
                        --push .
                """
            }
        }
        stage('Update Manifest') {
            steps {
                sh """
                    sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${SHORT_SHA}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: ${SHORT_SHA} # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/sysnet4admin/worklog-backend.git
                    git add deploy_manifest/
                    git commit -m "deploy: update backend image tag to ${SHORT_SHA}"
                    git push origin HEAD:main
                """
            }
        }
    }
    post {
        success { echo "Backend deploy succeeded: ${env.COMMIT_MESSAGE}" }
        failure { echo "Backend deploy failed: ${env.COMMIT_MESSAGE}" }
    }
}
