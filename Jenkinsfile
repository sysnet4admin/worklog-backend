pipeline {
    // docker, aws, kubectl, argocd가 든 에이전트 이미지(단계 2)에서 실행한다. agent any면 컨트롤러로 갈 수 있다(run-38 7.9)
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = '<dockerhub_username>/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_REGION = '<aws_region>'   // 10.3 단계 4에서 정한 리전 (기존 계정 ap-northeast-2, 새 가입 방식 ap-southeast-2)
        EKS_CLUSTER_NAME = 'cicd-learning-eks'
    }
    stages {
        stage('Init') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.COMMIT_MESSAGE = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                }
            }
        }
        stage('Test') {
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
            steps {
                sh """
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login --username ${DOCKERHUB_CREDENTIALS_USR} --password-stdin
                    docker buildx build --platform linux/amd64 \\
                        -t ${DOCKER_REPOSITORY}:${SHORT_SHA} \\
                        --push .
                    echo "build successful: ${SHORT_SHA}"
                """
            }
        }
        stage('Configure AWS') {
            steps {
                sh """
                    aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME}
                """
            }
        }
        stage('Deploy to EKS') {
            steps {
                sh """
                    sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${SHORT_SHA}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .*# IMAGE_TAG|value: \"${SHORT_SHA}\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    kubectl apply -f deploy_manifest/worklog-backend.yaml
                    kubectl rollout status deployment/worklog-backend --timeout=120s
                    echo "Deploy to EKS completed for tag ${SHORT_SHA}"
                """
            }
        }
    }
    post {
        success { echo "EKS deploy completed for ${env.SHORT_SHA}" }
        failure { echo "EKS deploy failed for ${env.SHORT_SHA}" }
    }
}
