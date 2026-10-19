// 10.7 Part B: 매니페스트를 고쳐 push하고 EKS의 Argo CD에 sync를 요청한다.
// 배포는 Argo CD가 한다. 이 파이프라인은 kubectl apply를 하지 않는다.
pipeline {
    // aws, kubectl, argocd를 넣은 에이전트 이미지(10.7 단계 2~4)에서 실행한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        IMAGE_NAME = 'worklog-backend'
        AWS_REGION = 'ap-southeast-2'
        EKS_CLUSTER_NAME = 'cicd-learning-eks'
        ARGOCD_APP_NAME = 'worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
        ARGOCD_PASSWORD = credentials('argocd-admin-password')
        // AWS CLI가 읽는 환경 변수 이름 그대로 받는다. aws configure가 필요 없다.
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
                    echo "SHORT_SHA=${env.SHORT_SHA}"
                }
            }
        }
        stage('Test') {
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
        // EKS 노드가 amd64라 amd64만 빌드한다. 로컬 워커(arm64)에서는 QEMU로 에뮬레이션한다.
        stage('Build') {
            steps {
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install amd64 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform linux/amd64 \
                        -t "$DOCKERHUB_CREDENTIALS_USR/$IMAGE_NAME:$SHORT_SHA" \
                        --push .
                '''
            }
        }
        // 배포에는 쓰지 않는다. Sync Argo CD에서 argocd-server 주소를 읽을 때 kubectl이 필요하다.
        stage('Configure AWS') {
            steps {
                sh '''
                    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
                    kubectl config current-context
                '''
            }
        }
        stage('Update Manifest') {
            steps {
                sh '''
                    sed -i "s|image: .*/worklog-backend:.*|image: $DOCKERHUB_CREDENTIALS_USR/$IMAGE_NAME:$SHORT_SHA|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    grep -n -E "image:|# IMAGE_TAG" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin "https://$GITHUB_CREDENTIALS_USR:$GITHUB_CREDENTIALS_PSW@github.com/$GITHUB_CREDENTIALS_USR/worklog-backend.git"
                    git add deploy_manifest/worklog-backend.yaml
                    git diff --staged --quiet || git commit -m "deploy(eks): update backend image to $SHORT_SHA"
                    # Jenkins는 커밋 하나를 브랜치 없이 checkout하므로 HEAD:로 브랜치를 지정한다
                    git pull --rebase origin "$BRANCH_NAME"
                    git push origin "HEAD:$BRANCH_NAME"
                '''
            }
        }
        stage('Sync Argo CD') {
            steps {
                sh '''
                    # 주소는 파일에 적지 않고 argocd-server Service의 hostname을 읽는다. EKS를 다시 만들어도 그대로 쓴다
                    ARGOCD_SERVER=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                    # 10.5의 Argo CD는 TLS 없이 동작해 --plaintext로 접속한다
                    argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_PASSWORD" --plaintext
                    # 자동 sync가 먼저 시작했으면 그 작업이 끝나기를 기다린다. 진행 중에 sync를 요청하면 거절된다
                    argocd app wait "$ARGOCD_APP_NAME" --operation --timeout 120
                    argocd app sync "$ARGOCD_APP_NAME"
                    argocd app wait "$ARGOCD_APP_NAME" --health --timeout 120
                '''
            }
        }
    }
    post {
        success {
            echo "SUCCESS: ${env.IMAGE_NAME}:${env.SHORT_SHA} -> Argo CD ${env.ARGOCD_APP_NAME}"
        }
        failure {
            echo "FAILURE: ${env.IMAGE_NAME}:${env.SHORT_SHA}"
        }
    }
}
