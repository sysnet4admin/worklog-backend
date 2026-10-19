pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트에서 실행한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        IMAGE_NAME = 'worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    env.LAST_AUTHOR = sh(script: 'git log -1 --pretty=%an', returnStdout: true).trim()

                    // 태그 빌드에서는 BRANCH_NAME에도 태그 이름이 들어가므로 태그를 먼저 검사한다.
                    if (env.TAG_NAME?.startsWith('v')) {
                        env.TARGET_ENV = 'prod'
                        env.IMAGE_TAG = env.TAG_NAME
                        env.ARGOCD_APP = 'worklog-backend-prod'
                    } else if (env.BRANCH_NAME.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.IMAGE_TAG = "staging-${env.SHORT_SHA}"
                        env.ARGOCD_APP = 'worklog-backend-staging'
                    } else {
                        env.TARGET_ENV = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                        env.ARGOCD_APP = 'worklog-backend-dev'
                    }

                    // 태그 이름으로 push하면 already exists로 거절된다. prod Application이 보는 main에 올린다.
                    env.PUSH_BRANCH = env.TAG_NAME ? 'main' : env.BRANCH_NAME

                    // Jenkins가 남긴 배포 커밋은 다시 빌드하지 않는다. 태그는 대개 배포 커밋에 붙으므로 예외다.
                    if (env.LAST_AUTHOR == 'jenkins' && !env.TAG_NAME) {
                        env.SKIP_BUILD = 'true'
                        currentBuild.result = 'NOT_BUILT'
                        echo "Skip: last commit is a deploy commit by jenkins"
                    } else {
                        env.SKIP_BUILD = 'false'
                    }

                    echo "TARGET_ENV=${env.TARGET_ENV} ARGOCD_APP=${env.ARGOCD_APP} IMAGE_TAG=${env.IMAGE_TAG} PUSH_BRANCH=${env.PUSH_BRANCH}"
                }
            }
        }
        stage('Test') {
            when { expression { env.SKIP_BUILD != 'true' } }
            steps {
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report
                '''
            }
        }
        // backend(Python/uv)는 가벼워서 QEMU로 다른 아키텍처를 함께 빌드해도 된다.
        stage('Build') {
            when { expression { env.SKIP_BUILD != 'true' } }
            steps {
                sh """
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "\$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "\$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform linux/amd64,linux/arm64 \\
                        -t "\$DOCKERHUB_CREDENTIALS_USR/${IMAGE_NAME}:${env.IMAGE_TAG}" \\
                        -t "\$DOCKERHUB_CREDENTIALS_USR/${IMAGE_NAME}:${env.SHORT_SHA}" \\
                        --push .
                """
            }
        }
        stage('Update Manifest') {
            when { expression { env.SKIP_BUILD != 'true' } }
            steps {
                sh """
                    sed -i "s|image: .*/worklog-backend:.*|image: \$DOCKERHUB_CREDENTIALS_USR/${IMAGE_NAME}:${env.IMAGE_TAG}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"${env.IMAGE_TAG}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin "https://\$GITHUB_CREDENTIALS_USR:\$GITHUB_CREDENTIALS_PSW@github.com/\$GITHUB_CREDENTIALS_USR/worklog-backend.git"
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy(${env.TARGET_ENV}): update backend image to ${env.IMAGE_TAG}"
                    git pull --rebase -X theirs origin ${env.PUSH_BRANCH}
                    git push origin HEAD:${env.PUSH_BRANCH}
                """
                echo "Manifest updated: ${env.TARGET_ENV} ${env.IMAGE_TAG} -> ${env.PUSH_BRANCH}"
            }
        }
    }
    // 배포는 Argo CD 자동 sync가 한다. 배포 커밋을 건너뛴 빌드(NOT_BUILT)에는 알림이 뜨지 않는다.
    post {
        success {
            echo "SUCCESS: TARGET_ENV=${env.TARGET_ENV} ARGOCD_APP=${env.ARGOCD_APP} IMAGE_TAG=${env.IMAGE_TAG}"
            echo "Argo CD automated sync가 ${env.ARGOCD_APP}에 반영한다"
        }
        failure {
            echo "FAILURE: TARGET_ENV=${env.TARGET_ENV} ARGOCD_APP=${env.ARGOCD_APP}"
        }
    }
}
