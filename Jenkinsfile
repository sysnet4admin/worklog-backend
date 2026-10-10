pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트에서 실행한다.
    // agent any면 컨트롤러로 갈 수 있고 그때 'docker: not found'로 실패한다. stage별로 다시 선언하지 않는다.
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
                    // Jenkins가 남긴 배포 커밋이면 빌드하지 않고 끝낸다. 없으면 스캔할 때마다 배포 커밋을 다시 빌드한다.
                    // 태그 빌드는 건너뛰지 않는다. main 최신 커밋(대개 배포 커밋)에 태그를 붙이기 때문이다.
                    env.SKIP_BUILD = 'false'
                    if (!env.TAG_NAME && sh(script: 'git log -1 --format=%an', returnStdout: true).trim() == 'jenkins') {
                        env.SKIP_BUILD = 'true'
                        currentBuild.result = 'NOT_BUILT'
                        echo 'skip: deploy commit by jenkins'
                        return
                    }
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    if (env.TAG_NAME && env.TAG_NAME.startsWith('v')) {
                        env.TARGET_ENV = 'prod'
                        env.NAMESPACE = 'prod'
                        env.IMAGE_TAG = env.TAG_NAME
                    } else if (env.BRANCH_NAME == 'develop') {
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                    } else if (env.BRANCH_NAME?.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.NAMESPACE = 'staging'
                        env.IMAGE_TAG = "staging-${env.SHORT_SHA}"
                    } else {
                        env.TARGET_ENV = 'dev'
                        env.NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
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
                script {
                    // 태그 빌드는 BRANCH_NAME에도 태그 이름이 들어가 push할 수 없다. main에 올린다(prod Application이 main을 본다).
                    env.PUSH_BRANCH = env.TAG_NAME ? 'main' : env.BRANCH_NAME
                }
                sh '''
                    git rebase --abort 2>/dev/null || true
                    sed -i "s|image: .*worklog-backend:.*|image: $DOCKER_REPOSITORY:$IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$IMAGE_TAG\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin "https://$GITHUB_CREDENTIALS_USR:$GITHUB_CREDENTIALS_PSW@github.com/$GITHUB_CREDENTIALS_USR/worklog-backend.git"
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
            script {
                if (env.SKIP_BUILD != 'true') {
                    echo "Deploy to ${env.TARGET_ENV} (${env.IMAGE_TAG}) completed"
                }
            }
        }
        failure {
            echo "Pipeline failed for ${env.TARGET_ENV ?: 'unknown'} (${env.IMAGE_TAG ?: 'no tag'})"
        }
    }
}
