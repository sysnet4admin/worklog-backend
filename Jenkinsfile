pipeline {
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    if (env.TAG_NAME) {
                        env.TARGET_ENV = 'prod'
                        env.NAMESPACE = 'prod'
                        env.IMAGE_TAG = env.TAG_NAME
                        env.ARGOCD_APP = 'worklog-backend-prod'
                    } else if (env.BRANCH_NAME.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.NAMESPACE = 'staging'
                        env.IMAGE_TAG = "staging-${env.SHORT_SHA}"
                        env.ARGOCD_APP = 'worklog-backend-staging'
                    } else if (env.BRANCH_NAME == 'develop') {
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                        env.ARGOCD_APP = 'worklog-backend-dev'
                    } else {
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                        env.ARGOCD_APP = 'worklog-backend-dev'
                    }
                }
            }
        }
        stage('Lint') {
            steps {
                sh '''
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    uv run ruff check src/
                '''
            }
        }
        stage('Test') {
            steps {
                sh '''
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
                        -t ${DOCKER_REPOSITORY}:${IMAGE_TAG} \\
                        -t ${DOCKER_REPOSITORY}:${SHORT_SHA} \\
                        --push .
                    echo "build successful: ${IMAGE_TAG}, ${SHORT_SHA}"
                """
            }
        }
        stage('Update Manifest') {
            steps {
                script {
                    def imageTag = env.IMAGE_TAG
                    def targetEnv = env.TARGET_ENV
                    def branch = env.BRANCH_NAME
                    sh """
                        git rebase --abort 2>/dev/null || true
                        git config user.name "jenkins"
                        git config user.email "jenkins@myk8s.local"
                        git remote set-url origin "https://\$GITHUB_CREDENTIALS_USR:\$GITHUB_CREDENTIALS_PSW@github.com/${GITHUB_CREDENTIALS_USR}/worklog-backend.git"
                        git fetch origin ${branch}
                        git reset --hard origin/${branch}
                        sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${imageTag}|" deploy_manifest/worklog-backend.yaml
                        sed -i "s|value: .* # IMAGE_TAG|value: \\\"${imageTag}\\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                        git add deploy_manifest/
                        git diff --staged --quiet || git commit -m "deploy: update image tag to ${imageTag} for ${targetEnv}"
                        git push origin HEAD:${branch}
                    """
                }
            }
        }
    }
    post {
        success { echo "Deploy to ${env.TARGET_ENV} (${env.ARGOCD_APP}) — Argo CD automated sync will pick up the manifest change" }
        failure { echo "Pipeline failed for ${env.TARGET_ENV}" }
    }
}
