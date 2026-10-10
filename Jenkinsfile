def notify(String result) {
    echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} 빌드가 ${result}"
}

pipeline {
    // label은 ch4.5 jenkins-config.yaml의 podTemplate label과 일치해야 한다.
    // docker.sock을 가진 k8s 에이전트에서만 docker buildx가 동작한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    // sh 안의 GString은 지역 변수를 보간하지 못할 수 있어 env에 둔다.
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    env.IMAGE = "${env.DOCKERHUB_CREDENTIALS_USR}/${env.DOCKER_REPOSITORY}"
                    echo "Image: ${env.IMAGE}:${env.SHORT_SHA}"
                }
            }
        }
        stage('Run Test') {
            steps {
                // 에이전트 pod에 uv를 직접 설치해 테스트 환경을 준비한다.
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report
                '''
            }
        }
        stage('Build Image') {
            steps {
                // 자격 증명은 셸 변수로만 쓴다. Groovy 보간을 거치지 않아 로그에 남지 않는다.
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform linux/amd64,linux/arm64 \
                        -t "$IMAGE:$SHORT_SHA" \
                        --push .
                '''
            }
        }
        stage('Update Manifest') {
            steps {
                // 토큰이 .git/config에 남지 않도록 pull과 push URL에만 넣는다.
                // pull --rebase가 충돌하면 여기서 빌드를 실패시킨다.
                sh '''
                    sed -i "s|image: .*worklog-backend:.*|image: $IMAGE:$SHORT_SHA|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to $SHORT_SHA"
                    REMOTE="https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/${GITHUB_CREDENTIALS_USR}/worklog-backend.git"
                    git pull --rebase "$REMOTE" main
                    git push "$REMOTE" HEAD:main
                '''
            }
        }
    }
    post {
        success {
            notify('성공했습니다')
        }
        failure {
            notify('실패했습니다')
        }
    }
}
