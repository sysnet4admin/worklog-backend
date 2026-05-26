pipeline {
    agent any
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
        ARGOCD_SERVER = 'argocd-server.argocd.svc.cluster.local'
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    if (env.TAG_NAME) {
                        env.TARGET_ENV = 'prod'
                        env.ARGOCD_APP = 'worklog-backend-prod'
                    } else if (env.BRANCH_NAME.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.ARGOCD_APP = 'worklog-backend-staging'
                    } else {
                        env.TARGET_ENV = 'dev'
                        env.ARGOCD_APP = 'worklog-backend-dev'
                    }
                }
            }
        }
        stage('Test') {
            agent any
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
        stage('Build') {
            steps {
                sh """
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login --username ${DOCKERHUB_CREDENTIALS_USR} --password-stdin
                    docker buildx build --platform linux/amd64,linux/arm64 \\
                        -t ${DOCKER_REPOSITORY}:${SHORT_SHA} \\
                        --push .
                """
            }
        }
        stage('Update Manifest') {
            steps {
                sh """
                    git rebase --abort 2>/dev/null || true
                    git checkout -- . 2>/dev/null || true
                    sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${SHORT_SHA}|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/sysnet4admin/worklog-backend.git
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to ${SHORT_SHA} for ${TARGET_ENV}"
                    git pull --rebase origin ${BRANCH_NAME} || git rebase --abort
                    git push origin HEAD:${BRANCH_NAME}
                """
            }
        }
        stage('Sync Argo CD') {
            steps {
                sh """
                    curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.4.2/argocd-linux-arm64
                    chmod +x /tmp/argocd
                    /tmp/argocd login 10.110.218.22 --username admin --password ${ARGOCD_ADMIN_PASSWORD_PSW} --insecure --plaintext
                    /tmp/argocd app sync ${ARGOCD_APP}
                    /tmp/argocd app wait ${ARGOCD_APP} --health --timeout 120
                """
            }
        }
    }
    post {
        success { echo "Argo CD deploy to ${env.TARGET_ENV} succeeded" }
        failure { echo "Argo CD deploy to ${env.TARGET_ENV} failed" }
    }
}
