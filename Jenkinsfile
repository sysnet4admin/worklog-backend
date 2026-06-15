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
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트(JCasC kubernetes cloud)에서 실행.
    // label은 ch4.5 jenkins-config.yaml의 podTemplate label과 일치해야 함.
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
                sh '''
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                    export PATH="$HOME/.local/bin:$PATH"
                    uv sync --extra dev
                    TESTING=true uv run coverage run --source ./src/worklog -m pytest --disable-warnings -v
                    uv run coverage report
                '''
            }
        }
        // 주의(#93): Declarative `steps`의 sh GString은 top-level `def`(fullSHA/shortSHA)을
        // 보간하지 못해 빈 값이 될 수 있다. 변수를 쓰는 sh는 반드시 `script { ... }`로 감싼다.
        stage('Build Image') {
            steps {
                script {
                    sh """
                        docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                        docker buildx rm backend-builder 2>/dev/null || true
                        docker buildx create --name backend-builder --driver docker-container --use
                        echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login --username ${DOCKERHUB_CREDENTIALS_USR} --password-stdin
                        docker buildx build --platform linux/amd64,linux/arm64 \\
                            -t ${DOCKER_REPOSITORY}:${fullSHA} \\
                            -t ${DOCKER_REPOSITORY}:${shortSHA} \\
                            --push .
                    """
                    echo "Built: ${shortSHA}"
                }
            }
        }
        stage('Update Manifest') {
            steps {
                script {
                    sh """
                        sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${shortSHA}|" deploy_manifest/worklog-backend.yaml
                        sed -i "s|value: .* # IMAGE_TAG|value: \"${shortSHA}\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                        git config user.name "jenkins"
                        git config user.email "jenkins@myk8s.local"
                        git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/${GITHUB_CREDENTIALS_USR}/worklog-backend.git
                        git add deploy_manifest/
                        git diff --staged --quiet || git commit -m "deploy: update image tag to ${shortSHA}"
                        git pull --rebase origin main || true
                        git push origin HEAD:main
                    """
                    echo "Manifest updated: ${shortSHA}"
                }
            }
        }
        stage('Sync Argo CD') {
            steps {
                script {
                    sh """
                        ARCH=\$(uname -m)
                        if [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then BIN="argocd-linux-arm64"; else BIN="argocd-linux-amd64"; fi
                        curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/\$BIN
                        chmod +x /tmp/argocd
                        /tmp/argocd login ${ARGOCD_SERVER} \\
                            --username admin \\
                            --password ${ARGOCD_ADMIN_PASSWORD} \\
                            --plaintext --insecure
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
