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
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --format=%s', returnStdout: true).trim()

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
                    // 환경마다 Argo CD Application이 하나씩 있다(8.4에서 만든 worklog-backend-dev/staging/prod).
                    env.ARGOCD_APP = "worklog-backend-${env.TARGET_ENV}"
                    // 태그 빌드는 BRANCH_NAME에도 태그 이름이 들어가 그대로 push하면 거절된다.
                    // prod Application이 main을 보므로 태그 빌드는 main의 매니페스트를 고친다.
                    env.PUSH_BRANCH = env.TAG_NAME ? 'main' : env.BRANCH_NAME

                    if (env.SKIP_BUILD == 'true') {
                        currentBuild.result = 'NOT_BUILT'
                        echo 'skip: deploy commit by jenkins'
                    }
                }
                echo "COMMIT=${env.SHORT_SHA} (${env.COMMIT_MESSAGE})"
                echo "TARGET_ENV=${env.TARGET_ENV} NAMESPACE=${env.NAMESPACE} IMAGE_TAG=${env.IMAGE_TAG} ARGOCD_APP=${env.ARGOCD_APP} PUSH_BRANCH=${env.PUSH_BRANCH}"
            }
        }

        stage('Lint') {
            when { expression { env.SKIP_BUILD != 'true' } }
            // ruff.toml 규칙으로 src/를 검사한다. 위반이 있으면 여기서 실패해 Test, Build로 가지 않는다.
            steps {
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    uv run ruff check src/
                '''
            }
        }

        stage('Security Scan') {
            when { expression { env.SKIP_BUILD != 'true' } }
            // pip-audit은 의존성의 알려진 취약점을, gitleaks는 커밋 이력에 들어간 비밀값을 찾는다.
            // 하나라도 나오면 여기서 실패해 Test, Build로 가지 않는다. uv와 의존성은 Lint에서 설치한 것을 쓴다.
            steps {
                sh '''
                    export PATH="$HOME/.local/bin:$PATH"
                    uv run pip-audit

                    # gitleaks: 버전을 고정하고 노드 아키텍처에 맞는 바이너리를 받는다
                    GITLEAKS_VERSION=8.30.1
                    case "$(uname -m)" in
                        x86_64)        GL_ARCH=x64 ;;
                        aarch64|arm64) GL_ARCH=arm64 ;;
                        *)             GL_ARCH=x64 ;;
                    esac
                    curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \\
                        | tar -xz -C /tmp/ gitleaks
                    /tmp/gitleaks detect --source . --config .gitleaks.toml --no-banner
                '''
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
                    uv run coverage report --fail-under=99
                '''
            }
        }

        stage('Build') {
            when { expression { env.SKIP_BUILD != 'true' } }
            // 작은따옴표 sh라 비밀값을 Groovy가 아니라 셸이 푼다(로그와 프로세스 인자에 남지 않는다).
            // 태그 두 개: IMAGE_TAG는 매니페스트가 가리키는 배포용, SHORT_SHA는 어느 커밋에서 나왔는지 찾는 용도.
            steps {
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform "$BUILD_PLATFORMS" \\
                        -t "$DOCKER_REPOSITORY:$IMAGE_TAG" \\
                        -t "$DOCKER_REPOSITORY:$SHORT_SHA" \\
                        --push .
                '''
                echo "Built: ${env.DOCKER_REPOSITORY}:${env.IMAGE_TAG}, ${env.DOCKER_REPOSITORY}:${env.SHORT_SHA}"
            }
        }

        stage('Update Manifest') {
            when { expression { env.SKIP_BUILD != 'true' } }
            // argocd CLI를 부르지 않는다. push만 하면 Argo CD automated sync가 변경을 가져가 배포한다.
            // (에이전트에서 argocd login을 하면 ~/.config/argocd/config 권한 0660 때문에 실패한다)
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
                echo "Manifest pushed to ${env.PUSH_BRANCH}: ${env.IMAGE_TAG}. Argo CD(${env.ARGOCD_APP}) will sync automatically."
            }
        }
    }

    post {
        success { echo "Pipeline succeeded: ARGOCD_APP=${env.ARGOCD_APP} TARGET_ENV=${env.TARGET_ENV} IMAGE=${env.DOCKER_REPOSITORY}:${env.IMAGE_TAG}" }
        failure { echo "Pipeline failed: ARGOCD_APP=${env.ARGOCD_APP} TARGET_ENV=${env.TARGET_ENV} IMAGE_TAG=${env.IMAGE_TAG}" }
        always { sh 'docker buildx rm backend-builder 2>/dev/null || true' }
    }
}
