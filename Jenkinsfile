pipeline {
    // docker, aws, kubectl이 든 에이전트 이미지에서 실행한다. agent any면 컨트롤러로 갈 수 있고 그때 'docker: not found'로 실패한다.
    // stage별로 다시 선언하지 않는다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_REGION = 'ap-southeast-2'
        EKS_CLUSTER_NAME = 'cicd-learning-eks'
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
        stage('Build') {
            steps {
                // EKS 노드가 amd64라 linux/amd64만 빌드한다.
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform linux/amd64 \
                        -t "$DOCKER_REPOSITORY:$SHORT_SHA" \
                        --push .
                    echo "build successful: $SHORT_SHA"
                '''
            }
        }
        stage('Configure AWS') {
            steps {
                sh '''
                    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
                '''
            }
        }
        stage('Deploy to EKS') {
            steps {
                // 매니페스트는 워크스페이스에서만 고치고 git push하지 않는다.
                sh '''
                    sed -i "s|image: .*worklog-backend:.*|image: $DOCKER_REPOSITORY:$SHORT_SHA|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    kubectl apply -f deploy_manifest/worklog-backend.yaml
                    kubectl rollout status deployment/worklog-backend --timeout=120s
                '''
            }
        }
    }
    post {
        success {
            echo "EKS deploy succeeded: ${env.DOCKER_REPOSITORY}:${env.SHORT_SHA}"
        }
        failure {
            echo "EKS deploy failed: ${env.SHORT_SHA ?: 'unknown'}"
        }
    }
}
