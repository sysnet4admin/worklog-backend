pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트(JCasC kubernetes cloud)에서 실행.
    // agent any면 컨트롤러 실행기(numExecutors: 2)로 갈 수 있고 그때 'docker: not found'로 실패한다(run-38 7.9).
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
                    // Jenkins가 남긴 배포 커밋(deploy_manifest만 변경)이면 다시 빌드하지 않는다.
                    // 없으면 스캔할 때마다 배포 커밋을 빌드해 또 배포 커밋을 만든다(run-38 8.5에서 확인).
                    // 태그는 건너뛰지 않는다. main 최신 커밋(대개 배포 커밋)에 태그를 붙이기 때문이다.
                    if (!env.TAG_NAME && sh(script: 'git log -1 --format=%an', returnStdout: true).trim() == 'jenkins') {
                        currentBuild.result = 'NOT_BUILT'
                        error('skip: deploy commit by jenkins')
                    }
                    // 환경과 이미지 태그 규칙은 8.6과 같다(태그 v* → prod, release/* → staging, 나머지 → dev)
                    env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    if (env.TAG_NAME) {
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
                }
            }
        }
        stage('Lint') {   // 9.3
            steps {
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    uv run ruff check src/
                '''
            }
        }
        stage('Security Scan') {   // 9.4
            steps {
                sh '''
                    export PATH="$HOME/.local/bin:$PATH"
                    uv run pip-audit

                    # gitleaks: 노드 아키텍처에 맞는 바이너리를 받는다
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
        stage('Test') {   // 9.5
            steps {
                sh '''
                    export PATH="$HOME/.local/bin:$PATH"
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report --fail-under=80
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
                """
            }
        }
        stage('Scan') {   // 9.6: HIGH 이상이 있으면 여기서 멈추고 매니페스트를 고치지 않는다
            steps {
                sh """
                    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /tmp
                    /tmp/trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed --format table ${DOCKER_REPOSITORY}:${IMAGE_TAG}
                """
            }
        }
        stage('Update Manifest') {
            steps {
                script {
                    def imageTag = env.IMAGE_TAG
                    def targetEnv = env.TARGET_ENV
                    // 태그 빌드는 태그에 push할 수 없으므로 main의 매니페스트를 고친다(prod Application이 main을 본다)
                    def branch = env.TAG_NAME ? 'main' : env.BRANCH_NAME
                    sh """
                        git rebase --abort 2>/dev/null || true
                        sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${imageTag}|" deploy_manifest/worklog-backend.yaml
                        sed -i "s|value: .* # IMAGE_TAG|value: \\"${imageTag}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                        git config user.name "jenkins"
                        git config user.email "jenkins@myk8s.local"
                        git remote set-url origin "https://\$GITHUB_CREDENTIALS_USR:\$GITHUB_CREDENTIALS_PSW@github.com/${GITHUB_CREDENTIALS_USR}/worklog-backend.git"
                        git add deploy_manifest/
                        git diff --staged --quiet || git commit -m "deploy: update image tag to ${imageTag} for ${targetEnv}"
                        git pull --rebase origin ${branch} || git rebase --abort
                        git push origin HEAD:${branch}
                    """
                }
            }
        }
    }
    post {
        success { echo "Deploy to ${env.TARGET_ENV} (${env.ARGOCD_APP}) completed" }
        failure { echo "Pipeline failed for ${env.TARGET_ENV}" }
    }
}
