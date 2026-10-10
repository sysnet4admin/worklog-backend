pipeline {
    // docker, aws, kubectl, argocd가 든 에이전트 이미지에서 실행한다. agent any면 컨트롤러로 갈 수 있고 그때 'docker: not found'로 실패한다.
    // stage별로 다시 선언하지 않는다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
        ARGOCD_APP_NAME = 'worklog-backend'
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
        stage('Update Manifest') {
            steps {
                // 매니페스트를 Git에 커밋하고 push한다. kubectl apply는 하지 않는다. 배포는 Argo CD가 한다.
                // 토큰은 Groovy가 아니라 셸이 읽도록 \$로 이스케이프하고, 원격 URL에도 저장하지 않는다.
                sh """
                    sed -i "s|image: .*worklog-backend:.*|image: ${env.DOCKER_REPOSITORY}:${env.SHORT_SHA}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"${env.SHORT_SHA}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git add deploy_manifest/worklog-backend.yaml
                    git diff --staged --quiet || git commit -m "deploy: worklog-backend ${env.SHORT_SHA}"
                    REPO_URL="https://\$GITHUB_CREDENTIALS_USR:\$GITHUB_CREDENTIALS_PSW@github.com/sysnet4admin/worklog-backend.git"
                    git pull --rebase "\$REPO_URL" ${env.BRANCH_NAME}
                    git push "\$REPO_URL" HEAD:${env.BRANCH_NAME}
                """
            }
        }
        stage('Sync Argo CD') {
            steps {
                sh """
                    ARGOCD_SERVER=\$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                    argocd login "\$ARGOCD_SERVER" --username admin --password "\$ARGOCD_ADMIN_PASSWORD" --plaintext
                    argocd app sync ${env.ARGOCD_APP_NAME}
                    argocd app wait ${env.ARGOCD_APP_NAME} --health --timeout 120
                """
            }
        }
    }
    post {
        success {
            echo "EKS + Argo CD pipeline succeeded: ${env.DOCKER_REPOSITORY}:${env.SHORT_SHA}"
        }
        failure {
            echo "EKS + Argo CD pipeline failed: ${env.SHORT_SHA ?: 'unknown'}"
        }
    }
}
