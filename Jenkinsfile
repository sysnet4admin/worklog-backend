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

        stage('Deploy to EKS') {
            // 매니페스트를 Git에 push하지 않는다. 워크스페이스 사본만 고쳐 EKS에 바로 적용한다.
            steps {
                sh '''
                    cd deploy_manifest
                    sed -i "s|image: .*/worklog-backend:.*|image: $DOCKER_REPOSITORY:$SHORT_SHA|" worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"$SHORT_SHA\\" # IMAGE_TAG|" worklog-backend.yaml
                    kubectl apply -f worklog-backend.yaml
                    kubectl rollout status deployment/worklog-backend --timeout=180s
                    echo "Deploy to EKS completed for tag $SHORT_SHA"
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
