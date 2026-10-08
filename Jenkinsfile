pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트(JCasC kubernetes cloud)에서 실행.
    // agent any면 컨트롤러 실행기(numExecutors: 2)로 갈 수 있고 그때 'docker: not found'로 실패한다.
    agent { label 'jenkins-jenkins-agent' }

    environment {
        DOCKER_REPOSITORY = 'worklog-backend'
        // backend(Python/uv)는 QEMU 에뮬레이션 빌드가 가벼워 로컬 에이전트에서도 멀티아치가 된다.
        BUILD_PLATFORMS = 'linux/amd64,linux/arm64'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }

    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --pretty=%s', returnStdout: true).trim()
                }
                echo "Image tag: ${env.SHORT_SHA} (${env.COMMIT_MESSAGE})"
            }
        }

        stage('Run Test') {
            // 에이전트 Pod에 uv를 설치해 바로 실행한다. 중첩 docker agent는 환경에 따라 불안정하다.
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
                    echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login --username ${DOCKERHUB_CREDENTIALS_USR} --password-stdin
                    docker buildx build --platform ${BUILD_PLATFORMS} \\
                        -t ${DOCKERHUB_CREDENTIALS_USR}/${DOCKER_REPOSITORY}:${env.SHORT_SHA} \\
                        --push .
                """
                echo "Built: ${DOCKERHUB_CREDENTIALS_USR}/${DOCKER_REPOSITORY}:${env.SHORT_SHA}"
            }
        }

        stage('Update Manifest') {
            steps {
                sh """
                    sed -i "s|image: .*/worklog-backend:.*|image: ${DOCKERHUB_CREDENTIALS_USR}/${DOCKER_REPOSITORY}:${env.SHORT_SHA}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"${env.SHORT_SHA}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/${GITHUB_CREDENTIALS_USR}/worklog-backend.git
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update backend image to ${env.SHORT_SHA}"
                    git pull --rebase origin main || true
                    git push origin HEAD:main
                """
                echo "Deployed: ${env.SHORT_SHA}"
            }
        }
    }

    post {
        success { echo "Backend pipeline succeeded: ${env.SHORT_SHA} (${env.COMMIT_MESSAGE})" }
        failure { echo "Backend pipeline failed: ${env.SHORT_SHA} (${env.COMMIT_MESSAGE})" }
        always { sh 'docker buildx rm backend-builder 2>/dev/null || true' }
    }
}
