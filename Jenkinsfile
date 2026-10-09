// 알림 helper. 실제 Slack 호출 대신 콘솔에 남긴다(4.6과 같은 방식).
// 함수 정의라 전역 def 변수가 아니다. 값은 모두 env.*로 받는다.
def sendSlackMessage(statusMessage) {
    echo "Your pipeline has been ${statusMessage}"
    echo "Commit Message: ${env.COMMIT_MESSAGE}"
    echo "Tags: ${env.SHORT_SHA}, ${env.FULL_SHA}"
}

pipeline {
    // docker, aws, kubectl이 든 에이전트 이미지(10.7 단계 2)에서 실행한다.
    // agent any면 컨트롤러로 갈 수 있고 그때 'docker: not found', 'aws: not found'로 실패한다.
    // stage마다 agent를 다시 선언하면 Init Variables에서 정한 env 값이 사라지므로 여기 한 번만 둔다.
    agent { label 'jenkins-jenkins-agent' }

    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_USERNAME = 'sysnet4admin'
        DOCKERHUB_TOKEN = credentials('dockerhub-token')
        // aws CLI가 이 두 이름의 환경변수를 그대로 읽는다. 값은 Jenkins Credentials에만 있다.
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_REGION = 'ap-southeast-2'   // 10.3 단계 4에서 정한 리전
        EKS_CLUSTER_NAME = 'cicd-learning-eks'
        // Username with password 타입이라 GITHUB_CREDENTIALS_USR, GITHUB_CREDENTIALS_PSW가 함께 생긴다.
        GITHUB_CREDENTIALS = credentials('github-token')
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
        ARGOCD_APP_NAME = 'worklog-backend'
    }

    stages {
        stage('Init Variables') {
            steps {
                script {
                    env.FULL_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --format=%s', returnStdout: true).trim()
                }
                echo "COMMIT=${env.SHORT_SHA} (${env.COMMIT_MESSAGE})"
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
            // 작은따옴표 sh라 비밀값을 Groovy가 아니라 셸이 푼다(로그와 프로세스 인자에 남지 않는다).
            // EKS 노드는 amd64, 로컬 클러스터는 arm64일 수 있어 두 아키텍처를 함께 올린다.
            steps {
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin
                    docker buildx build --platform linux/amd64,linux/arm64 \\
                        -t "$DOCKER_REPOSITORY:$FULL_SHA" \\
                        -t "$DOCKER_REPOSITORY:$SHORT_SHA" \\
                        --push .
                    echo "build successful: $SHORT_SHA"
                '''
            }
        }

        stage('Configure AWS') {
            // 에이전트의 ~/.kube/config에 EKS 컨텍스트를 추가하고 current-context로 바꾼다.
            // 이 뒤의 kubectl은 로컬 클러스터가 아니라 EKS를 대상으로 동작한다.
            steps {
                sh '''
                    aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
                    kubectl config current-context
                '''
            }
        }

        stage('Update Manifest') {
            // kubectl apply를 직접 하지 않는다. 매니페스트의 태그를 고쳐 Git에 push하면 Argo CD가 그 커밋을 배포한다.
            // 태그 빌드에서는 BRANCH_NAME에 태그 이름이 들어가 push가 거절된다. 이 파이프라인은 브랜치 빌드용이다.
            steps {
                sh '''
                    sed -i "s|image: .*/worklog-backend:.*|image: $DOCKER_REPOSITORY:$SHORT_SHA|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin "https://$GITHUB_CREDENTIALS_USR:$GITHUB_CREDENTIALS_PSW@github.com/sysnet4admin/worklog-backend.git"
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to $SHORT_SHA"
                    git pull --rebase origin "$BRANCH_NAME" || git rebase --abort
                    git push origin "HEAD:$BRANCH_NAME"
                    echo "manifest pushed: $SHORT_SHA"
                '''
            }
        }

        stage('Sync Argo CD') {
            // EKS의 Argo CD는 LoadBalancer로 노출돼 있어 에이전트에서 주소로 바로 닿는다.
            // 10.5의 Argo CD는 TLS 없이 동작하므로 --plaintext를 쓴다(--insecure가 아니다).
            steps {
                script {
                    env.ARGOCD_SERVER = sh(
                        script: "kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
                        returnStdout: true
                    ).trim()
                    if (!env.ARGOCD_SERVER) {
                        error 'argocd-server LoadBalancer 주소가 비어 있다. 10.5의 Argo CD Service 타입을 확인한다.'
                    }
                }
                sh '''
                    argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_ADMIN_PASSWORD" --plaintext
                    argocd app sync "$ARGOCD_APP_NAME"
                    argocd app wait "$ARGOCD_APP_NAME" --health --timeout 120
                    echo "Argo CD sync completed for $ARGOCD_APP_NAME"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker buildx rm backend-builder 2>/dev/null || true'
            sendSlackMessage('finished')
        }
        success {
            sendSlackMessage('completed')
        }
        failure {
            sendSlackMessage('failed')
        }
        aborted {
            sendSlackMessage('aborted')
        }
    }
}
