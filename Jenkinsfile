pipeline {
    // label은 ch4.5 jenkins-config.yaml의 podTemplate label과 일치해야 한다.
    // agent any면 docker가 없는 컨트롤러로 갈 수 있다. stage별로 agent를 다시 선언하지 않는다.
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
                    env.SKIP_BUILD = 'false'
                    // Jenkins가 남긴 배포 커밋이면 다시 빌드하지 않는다. 안 막으면 스캔마다 배포 커밋이 또 생긴다.
                    // 태그는 건너뛰지 않는다. main 최신 커밋(대개 배포 커밋)에 태그를 붙이기 때문이다.
                    String author = sh(script: 'git log -1 --format=%an', returnStdout: true).trim()
                    if (!env.TAG_NAME && author == 'jenkins') {
                        env.SKIP_BUILD = 'true'
                        currentBuild.result = 'NOT_BUILT'
                        echo 'skip: deploy commit by jenkins'
                        return
                    }
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    if (env.TAG_NAME) {
                        // 태그 빌드는 BRANCH_NAME에도 태그 이름이 들어와 태그에는 push할 수 없다. main에 push한다.
                        env.TARGET_ENV = 'prod'
                        env.NAMESPACE = 'prod'
                        env.IMAGE_TAG = env.TAG_NAME
                        env.PUSH_BRANCH = 'main'
                    } else if (env.BRANCH_NAME.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.NAMESPACE = 'staging'
                        env.IMAGE_TAG = "staging-${env.SHORT_SHA}"
                        env.PUSH_BRANCH = env.BRANCH_NAME
                    } else {
                        // develop과 그 외 브랜치
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                        env.PUSH_BRANCH = env.BRANCH_NAME
                    }
                    echo "TARGET_ENV=${env.TARGET_ENV} NAMESPACE=${env.NAMESPACE} IMAGE_TAG=${env.IMAGE_TAG}"
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
        stage('Build') {
            when { expression { env.SKIP_BUILD != 'true' } }
            steps {
                // 자격 증명은 셸 변수로만 쓴다. Groovy 보간을 거치지 않아 로그에 남지 않는다.
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform linux/amd64,linux/arm64 \
                        -t "$DOCKER_REPOSITORY:$IMAGE_TAG" \
                        --push .
                '''
            }
        }
        stage('Update Manifest') {
            when { expression { env.SKIP_BUILD != 'true' } }
            steps {
                sh '''
                    git rebase --abort 2>/dev/null || true
                    sed -i "s|image: .*worklog-backend:.*|image: $DOCKER_REPOSITORY:$IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$IMAGE_TAG\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin "https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/sysnet4admin/worklog-backend.git"
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to $IMAGE_TAG for $TARGET_ENV"
                    git pull --rebase -X theirs origin "$PUSH_BRANCH"
                    git push origin HEAD:"$PUSH_BRANCH"
                '''
            }
        }
    }
    post {
        success {
            echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} ${env.TARGET_ENV} 배포가 성공했습니다"
        }
        failure {
            echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} ${env.TARGET_ENV} 배포가 실패했습니다"
        }
    }
}
