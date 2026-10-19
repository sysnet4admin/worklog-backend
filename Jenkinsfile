def shortSHA

pipeline {
    // 컨트롤러에는 docker가 없으므로 docker.sock을 가진 k8s 에이전트에서 실행한다.
    agent { label 'jenkins-jenkins-agent' }
    environment {
        IMAGE_NAME = 'worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }
    stages {
        stage('Init') {
            steps {
                script {
                    shortSHA = sh(script: "git rev-parse --short=8 HEAD", returnStdout: true).trim()
                    echo "Image tag: ${shortSHA}"
                }
            }
        }
        stage('Run Test') {
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
        // backend(Python/uv)는 가벼워서 QEMU로 다른 아키텍처를 함께 빌드해도 된다.
        stage('Build Image') {
            steps {
                script {
                    sh """
                        docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                        docker buildx rm backend-builder 2>/dev/null || true
                        docker buildx create --name backend-builder --driver docker-container --use
                        echo "\$DOCKERHUB_CREDENTIALS_PSW" | docker login --username "\$DOCKERHUB_CREDENTIALS_USR" --password-stdin
                        docker buildx build --platform linux/amd64,linux/arm64 \\
                            -t "\$DOCKERHUB_CREDENTIALS_USR/${IMAGE_NAME}:${shortSHA}" \\
                            --push .
                    """
                }
            }
        }
        stage('Update Manifest') {
            steps {
                script {
                    sh """
                        sed -i "s|image: .*/worklog-backend:.*|image: \$DOCKERHUB_CREDENTIALS_USR/${IMAGE_NAME}:${shortSHA}|" deploy_manifest/worklog-backend.yaml
                        sed -i "s|value: .* # IMAGE_TAG|value: \\"${shortSHA}\\" # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                        git config user.name "jenkins"
                        git config user.email "jenkins@myk8s.local"
                        git remote set-url origin "https://\$GITHUB_CREDENTIALS_USR:\$GITHUB_CREDENTIALS_PSW@github.com/\$GITHUB_CREDENTIALS_USR/worklog-backend.git"
                        git add deploy_manifest/
                        git diff --staged --quiet || git commit -m "deploy: update backend image to ${shortSHA}"
                        git pull --rebase -X theirs origin main
                        git push origin HEAD:main
                    """
                    echo "Manifest updated: ${shortSHA}"
                }
            }
        }
    }
}
