pipeline {
    // docker, aws, kubectl, argocd가 든 에이전트 이미지에서 실행한다. agent any면 도구가 없는 컨트롤러로 갈 수 있다.
    // stage별로 agent를 다시 선언하지 않는다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
        AWS_ACCESS_KEY_ID = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
        AWS_REGION = 'ap-southeast-2'
        EKS_CLUSTER_NAME = 'cicd-learning-eks'
        ARGOCD_APP_NAME = 'worklog-backend'
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
                // 자격 증명은 셸 변수로만 쓴다. Groovy 보간을 거치지 않아 로그에 남지 않는다.
                // EKS 노드가 amd64라 linux/amd64만 빌드한다.
                sh '''
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo "$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                    docker buildx build --platform linux/amd64 \\
                        -t "$DOCKER_REPOSITORY:$SHORT_SHA" \\
                        --push .
                    echo "build successful: $SHORT_SHA"
                '''
            }
        }
        stage('Configure AWS') {
            steps {
                sh '''
                    aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME}
                '''
            }
        }
        stage('Update Manifest') {
            steps {
                // 배포는 Argo CD가 한다. 여기서는 매니페스트의 이미지 태그만 고쳐 Git에 올리고 kubectl apply는 하지 않는다.
                sh '''
                    sed -i "s|image: .*worklog-backend:.*|image: $DOCKER_REPOSITORY:$SHORT_SHA|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git add deploy_manifest/worklog-backend.yaml
                    git diff --staged --quiet || git commit -m "deploy: update image tag to $SHORT_SHA"
                    git remote set-url origin "https://$GITHUB_CREDENTIALS_USR:$GITHUB_CREDENTIALS_PSW@github.com/sysnet4admin/worklog-backend.git"
                    git pull --rebase origin "$BRANCH_NAME"
                    git push origin HEAD:"$BRANCH_NAME"
                '''
            }
        }
        stage('Sync Argo CD') {
            steps {
                sh '''
                    ARGOCD_SERVER=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
                    argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_ADMIN_PASSWORD" --plaintext
                    argocd app sync "$ARGOCD_APP_NAME"
                    argocd app wait "$ARGOCD_APP_NAME" --health --timeout 120
                    echo "Argo CD sync completed for $ARGOCD_APP_NAME"
                '''
            }
        }
    }
    post {
        success {
            echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} ${env.SHORT_SHA}를 Argo CD로 EKS(${env.EKS_CLUSTER_NAME})에 배포했습니다"
        }
        failure {
            echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} Argo CD 배포가 실패했습니다"
        }
    }
}
