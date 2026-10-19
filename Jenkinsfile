def fullSHA
def shortSHA
def branch
def commitMessage

def sendSlackMessage(statusMessage, commitMessage, shortSHA, fullSHA) {
    echo "Your pipeline has been ${statusMessage}"
    echo "Commit Message: ${commitMessage}"
    echo "Tags: ${shortSHA}, ${fullSHA}"
}

pipeline {
    // 컨트롤러에는 uv와 docker가 없다. 4.5의 podTemplate으로 뜨는 쿠버네티스 에이전트에서 실행한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
        ARGOCD_SERVER = 'argocd-server.argocd.svc.cluster.local'
        ARGOCD_APP_NAME = 'worklog-backend'
        ARGOCD_ADMIN_PASSWORD = credentials('argocd-admin-password')
    }
    stages {
        stage('Init Variables') {
            steps {
                script {
                    fullSHA = sh(script: "git log -n 1 --pretty=format:'%H'", returnStdout: true).trim()
                    shortSHA = fullSHA[0..7]
                    branch = env.BRANCH_NAME
                    commitMessage = sh(script: "git log -1 --format='*%s* by _%an_'", returnStdout: true).trim()
                }
            }
        }
        stage('Run Test') {
            steps {
                echo "let's run a test for ${shortSHA} in ${branch}"
                sh '''
                    curl -LsSf https://astral.sh/uv/0.11.18/install.sh | sh
                    export PATH=$HOME/.local/bin:$PATH
                    uv sync --extra dev
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report
                '''
            }
        }
        // fullSHA, shortSHA를 쓰는 sh는 script { }로 감싼다. 감싸지 않으면 빈 값으로 풀린다(#93).
        // 비밀값은 \$로 넘겨 Groovy가 아니라 셸이 환경 변수로 읽게 한다.
        stage('Build Image') {
            steps {
                script {
                    sh """
                        docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                        docker buildx rm backend-builder 2>/dev/null || true
                        docker buildx create --name backend-builder --driver docker-container --use
                        echo "\$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "\$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                        docker buildx build --platform linux/amd64,linux/arm64 \\
                            -t ${DOCKER_REPOSITORY}:${fullSHA} \\
                            -t ${DOCKER_REPOSITORY}:${shortSHA} \\
                            --push .
                    """
                    echo "Tags: ${shortSHA}, ${fullSHA}"
                }
            }
        }
        stage('Update Manifest') {
            steps {
                script {
                    sh """
                        sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${shortSHA}|" deploy_manifest/worklog-backend.yaml
                        sed -i "s|value: .* # IMAGE_TAG|value: \\"${shortSHA}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                        git config user.name "jenkins"
                        git config user.email "jenkins@myk8s.local"
                        git remote set-url origin "https://\$GITHUB_CREDENTIALS_USR:\$GITHUB_CREDENTIALS_PSW@github.com/\$GITHUB_CREDENTIALS_USR/worklog-backend.git"
                        git add deploy_manifest/
                        git diff --staged --quiet || git commit -m "deploy: update image tag to ${shortSHA}"
                        git pull --rebase -X theirs origin main
                        git push origin HEAD:main
                    """
                    echo "Manifest updated: ${shortSHA}"
                }
            }
        }
        stage('Sync Argo CD') {
            steps {
                script {
                    // 6.3에서 server.insecure로 TLS를 껐으므로 --plaintext로 접속한다.
                    sh """
                        ARCH=\$(uname -m)
                        if [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then BIN="argocd-linux-arm64"; else BIN="argocd-linux-amd64"; fi
                        curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/download/v3.4.3/\$BIN
                        chmod +x /tmp/argocd
                        /tmp/argocd version --client
                        /tmp/argocd login ${ARGOCD_SERVER} \\
                            --username admin \\
                            --password "\$ARGOCD_ADMIN_PASSWORD" \\
                            --plaintext
                        /tmp/argocd app sync ${ARGOCD_APP_NAME}
                        /tmp/argocd app wait ${ARGOCD_APP_NAME} --health --timeout 120
                    """
                    echo "Argo CD sync completed"
                }
            }
        }
    }
    post {
        always {
            echo 'Job finished. Sending slack notifications ..'
        }
        success {
            echo 'Build Success, Notifying to slack..'
            sendSlackMessage('completed', commitMessage, shortSHA, fullSHA)
        }
        failure {
            echo 'Build Failed, Notifying to slack..'
            sendSlackMessage('failed', commitMessage, shortSHA, fullSHA)
        }
        aborted {
            echo 'Build Aborted, Notifying to slack..'
            sendSlackMessage('aborted', commitMessage, shortSHA, fullSHA)
        }
    }
}
