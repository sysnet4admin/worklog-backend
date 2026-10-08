pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트(JCasC kubernetes cloud)에서 실행.
    // agent any면 컨트롤러 실행기(numExecutors: 2)로 갈 수 있고 그때 'docker: not found'로 실패한다.
    // stage마다 agent를 다시 선언하면 Init에서 정한 env 값이 사라지므로 여기 한 번만 둔다.
    agent { label 'jenkins-jenkins-agent' }

    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        // backend(Python/uv)는 QEMU 에뮬레이션 빌드가 가벼워 로컬 에이전트에서도 멀티아치가 된다.
        BUILD_PLATFORMS = 'linux/amd64,linux/arm64'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }

    stages {
        stage('Init') {
            steps {
                script {
                    // Jenkins가 남긴 배포 커밋(deploy_manifest만 변경)이면 다시 빌드하지 않는다.
                    // 없으면 스캔할 때마다 배포 커밋을 빌드해 또 배포 커밋을 만든다.
                    // 태그는 건너뛰지 않는다. main 최신 커밋(대개 배포 커밋)에 태그를 붙이기 때문이다.
                    env.LAST_AUTHOR = sh(script: 'git log -1 --format=%an', returnStdout: true).trim()
                    env.SKIP_BUILD = (!env.TAG_NAME && env.LAST_AUTHOR == 'jenkins') ? 'true' : 'false'
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()

                    if (env.TAG_NAME && env.TAG_NAME.startsWith('v')) {
                        env.TARGET_ENV = 'prod'
                        env.NAMESPACE = 'prod'
                        env.IMAGE_TAG = env.TAG_NAME
                    } else if (env.BRANCH_NAME == 'develop') {
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                    } else if (env.BRANCH_NAME.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.NAMESPACE = 'staging'
                        env.IMAGE_TAG = "staging-${env.SHORT_SHA}"
                    } else {
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                    }
                    // 태그 빌드는 BRANCH_NAME에도 태그 이름이 들어가 그대로 push하면 거절된다.
                    // prod Application이 main을 보므로 태그 빌드는 main의 매니페스트를 고친다.
                    env.PUSH_BRANCH = env.TAG_NAME ? 'main' : env.BRANCH_NAME

                    if (env.SKIP_BUILD == 'true') {
                        currentBuild.result = 'NOT_BUILT'
                        echo 'skip: deploy commit by jenkins'
                    }
                }
                echo "TARGET_ENV=${env.TARGET_ENV} NAMESPACE=${env.NAMESPACE} IMAGE_TAG=${env.IMAGE_TAG} PUSH_BRANCH=${env.PUSH_BRANCH}"
            }
        }

        stage('Test') {
            when { expression { env.SKIP_BUILD != 'true' } }
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

        stage('Build') {
            when { expression { env.SKIP_BUILD != 'true' } }
            // 작은따옴표 sh라 비밀값을 Groovy가 아니라 셸이 푼다(로그와 프로세스 인자에 남지 않는다).
            steps {
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform "$BUILD_PLATFORMS" \\
                        -t "$DOCKER_REPOSITORY:$IMAGE_TAG" \\
                        --push .
                '''
                echo "Built: ${env.DOCKER_REPOSITORY}:${env.IMAGE_TAG}"
            }
        }

        stage('Update Manifest') {
            when { expression { env.SKIP_BUILD != 'true' } }
            steps {
                sh '''
                    git rebase --abort 2>/dev/null || true
                    sed -i "s|image: .*/worklog-backend:.*|image: $DOCKER_REPOSITORY:$IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$IMAGE_TAG\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin "https://$GITHUB_CREDENTIALS_USR:$GITHUB_CREDENTIALS_PSW@github.com/sysnet4admin/worklog-backend.git"
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to $IMAGE_TAG for $TARGET_ENV"
                    git pull --rebase -X theirs origin "$PUSH_BRANCH"
                    git push origin "HEAD:$PUSH_BRANCH"
                '''
                echo "Manifest updated: ${env.IMAGE_TAG} -> ${env.PUSH_BRANCH}"
            }
        }
    }

    post {
        success { echo "Deploy to ${env.TARGET_ENV} completed: ${env.DOCKER_REPOSITORY}:${env.IMAGE_TAG}" }
        failure { echo "Pipeline failed for ${env.TARGET_ENV}: ${env.IMAGE_TAG}" }
        always { sh 'docker buildx rm backend-builder 2>/dev/null || true' }
    }
}
