def shortSHA
def commitMessage

pipeline {
    agent any
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        ARGOCD_SERVER = 'argocd-server.argocd.svc.cluster.local'
        ARGOCD_APP_NAME = 'worklog-backend'
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
        GITHUB_CREDENTIALS = credentials('github-token')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    shortSHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    commitMessage = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
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
        stage('Build and Push Image') {
            steps {
                sh """
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    docker login -u ${DOCKERHUB_CREDENTIALS_USR} -p ${DOCKERHUB_CREDENTIALS_PSW}
                    docker buildx build \\
                        --platform linux/amd64,linux/arm64 \\
                        -t ${DOCKER_REPOSITORY}:${shortSHA} \\
                        --push .
                """
            }
        }
        stage('Update Manifest') {
            steps {
                sh """
                    sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${shortSHA}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: ${shortSHA} # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/sysnet4admin/worklog-backend.git
                    git add deploy_manifest/
                    git commit -m "deploy: update backend image tag to ${shortSHA}"
                    git pull --rebase origin main
                    git push origin HEAD:main
                """
            }
        }
        stage('Sync Argo CD') {
            steps {
                sh """
                    curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.4.2/argocd-linux-arm64
                    chmod +x /tmp/argocd
                    /tmp/argocd login ${ARGOCD_SERVER} \\
                        --username admin \\
                        --password ${ARGOCD_ADMIN_PASSWORD} \\
                        --insecure \\
                        --plaintext
                    /tmp/argocd app sync ${ARGOCD_APP_NAME}
                    /tmp/argocd app wait ${ARGOCD_APP_NAME} --health --timeout 120
                """
                echo "Argo CD sync completed successfully"
            }
        }
    }
    post {
        success { echo "Backend deploy succeeded: ${commitMessage}" }
        failure { echo "Backend deploy failed: ${commitMessage}" }
    }
}
