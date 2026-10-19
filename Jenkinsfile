// 10.7 Part A: Jenkins가 EKS에 직접 접속해 kubectl apply로 배포한다.
// 매니페스트는 에이전트의 checkout에서만 고치고 git push하지 않는다. 클러스터만 바뀌고 Git은 그대로다.
pipeline {
    // aws, kubectl을 넣은 에이전트 이미지(10.7 단계 2~4)에서 실행한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        IMAGE_NAME = 'worklog-backend'
        AWS_REGION = 'ap-southeast-2'
        EKS_CLUSTER_NAME = 'cicd-learning-eks'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
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
        stage('Configure AWS') {
            steps {
                sh '''
                    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
                    kubectl config current-context
                '''
            }
        }
        stage('Deploy to EKS') {
            steps {
                sh '''
                    # 에이전트의 checkout에서만 태그를 바꾼다. commit과 push는 하지 않는다
                    sed -i "s|image: .*/worklog-backend:.*|image: $DOCKERHUB_CREDENTIALS_USR/$IMAGE_NAME:$SHORT_SHA|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    grep -n -E "image:|# IMAGE_TAG" deploy_manifest/worklog-backend.yaml
                    kubectl apply -f deploy_manifest/worklog-backend.yaml
                    kubectl rollout status deployment/worklog-backend --timeout=180s
                '''
            }
        }
    }
    post {
        success {
            echo "SUCCESS: ${env.IMAGE_NAME}:${env.SHORT_SHA} -> EKS ${env.EKS_CLUSTER_NAME}"
        }
        failure {
            echo "FAILURE: ${env.IMAGE_NAME}:${env.SHORT_SHA}"
        }
    }
}
