def notify(String result) {
    echo "알림: ${env.JOB_NAME} #${env.BUILD_NUMBER} 빌드가 ${result}"
}

pipeline {
    // label은 ch4.5 jenkins-config.yaml의 podTemplate label과 일치해야 한다.
    // docker.build()와 withRegistry()는 docker.sock을 가진 이 k8s 에이전트에서만 동작한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        GITHUB_CREDENTIALS = credentials('github-token')
        ARGOCD_SERVER = 'argocd-server.argocd.svc.cluster.local'
        ARGOCD_APP_NAME = 'worklog-backend'
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
    }
    stages {
        stage('Init Variables') {
            steps {
                script {
                    // sh 안의 GString은 지역 변수를 보간하지 못할 수 있어 env에 둔다.
                    env.FULL_SHA = sh(script: "git log -n 1 --pretty=format:'%H'", returnStdout: true).trim()
                    env.SHORT_SHA = env.FULL_SHA[0..7]
                }
            }
        }
        stage('Run Test') {
            steps {
                echo "Let's run a test for ${env.SHORT_SHA}"
                // 에이전트 pod에 uv를 직접 설치해 테스트 환경을 준비한다.
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH=$HOME/.local/bin:$PATH
                    uv sync --extra dev
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report
                '''
            }
        }
        stage('Build Image') {
            steps {
                script {
                    echo "Let's build the image: ${DOCKER_REPOSITORY}:${env.SHORT_SHA}"

                    def app = docker.build("${DOCKER_REPOSITORY}:${env.SHORT_SHA}")

                    docker.withRegistry('https://index.docker.io/v1/', 'dockerhub-credentials') {
                        app.push(env.SHORT_SHA)
                        app.push(env.FULL_SHA)
                    }

                    echo "Tags: ${env.SHORT_SHA}, ${env.FULL_SHA}"
                }
            }
        }
        stage('Update Manifest') {
            steps {
                // 토큰이 .git/config에 남지 않도록 push URL에만 넣는다.
                sh '''
                    sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${SHORT_SHA}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: \\"${SHORT_SHA}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to ${SHORT_SHA}"
                    REMOTE="https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/${GITHUB_CREDENTIALS_USR}/worklog-backend.git"
                    git pull --rebase "$REMOTE" main
                    git push "$REMOTE" HEAD:main
                '''
            }
        }
        stage('Sync Argo CD') {
            steps {
                // argocd CLI는 서버(v3.4.3)와 같은 버전으로 고정해 설치한다. latest를 쓰지 않는다.
                sh '''
                    ARCH=$(uname -m)
                    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then BIN="argocd-linux-arm64"; else BIN="argocd-linux-amd64"; fi
                    curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/v3.4.3/${BIN}"
                    chmod +x /tmp/argocd
                    /tmp/argocd login "$ARGOCD_SERVER" \
                        --username admin \
                        --password "$ARGOCD_ADMIN_PASSWORD" \
                        --plaintext --insecure
                    /tmp/argocd app sync "$ARGOCD_APP_NAME"
                    /tmp/argocd app wait "$ARGOCD_APP_NAME" --health --timeout 120
                '''
            }
        }
    }
    post {
        success {
            notify('성공했습니다')
        }
        failure {
            notify('실패했습니다')
        }
    }
}
