pipeline {
    agent any

    environment {
        DOCKER_REPOSITORY = 'sysnet4admin/worklog-backend'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        GITHUB_CREDENTIALS = credentials('github-token')
    }

    stages {
        stage('Init Variables') {
            steps {
                script {
                    env.SHORT_SHA = sh(script: "git log -n 1 --pretty=format:'%H'", returnStdout: true).trim()[0..7]
                    env.COMMIT_MESSAGE = sh(script: "git log -1 --format='*%s* by _%an_'", returnStdout: true).trim()

                    if (env.TAG_NAME && env.TAG_NAME.startsWith('v')) {
                        env.TARGET_ENV = 'prod'
                        env.TARGET_NAMESPACE = 'prod'
                        env.IMAGE_TAG = env.TAG_NAME
                    } else if (env.BRANCH_NAME == 'develop') {
                        env.TARGET_ENV = 'dev'
                        env.TARGET_NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                    } else if (env.BRANCH_NAME.startsWith('release/')) {
                        env.TARGET_ENV = 'staging'
                        env.TARGET_NAMESPACE = 'staging'
                        env.IMAGE_TAG = "staging-${env.SHORT_SHA}"
                    } else {
                        env.TARGET_ENV = 'dev'
                        env.TARGET_NAMESPACE = 'dev'
                        env.IMAGE_TAG = "dev-${env.SHORT_SHA}"
                    }

                    echo "Target Environment: ${env.TARGET_ENV}"
                    echo "Target Namespace: ${env.TARGET_NAMESPACE}"
                    echo "Image Tag: ${env.IMAGE_TAG}"
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

        stage('Build Image') {
            steps {
                sh """
                    docker run --privileged --rm tonistiigi/binfmt --install all 2>/dev/null || true
                    docker buildx rm backend-builder 2>/dev/null || true
                    docker buildx create --name backend-builder --driver docker-container --use
                    echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login --username ${DOCKERHUB_CREDENTIALS_USR} --password-stdin
                    docker buildx build --platform linux/amd64,linux/arm64 \\
                        -t ${DOCKER_REPOSITORY}:${IMAGE_TAG} \\
                        --push .
                """
                echo "Build successful: ${env.IMAGE_TAG}"
            }
        }

        stage('Deploy') {
            steps {
                sh """
                    sed -i "s|image: .*worklog-backend:.*|image: ${DOCKER_REPOSITORY}:${IMAGE_TAG}|" deploy_manifest/worklog-backend.yaml
                    sed -i "s|value: .* # IMAGE_TAG|value: ${IMAGE_TAG} # IMAGE_TAG|" deploy_manifest/worklog-backend.yaml
                    git config user.name "jenkins"
                    git config user.email "jenkins@myk8s.local"
                    git remote set-url origin https://${GITHUB_CREDENTIALS_USR}:${GITHUB_CREDENTIALS_PSW}@github.com/sysnet4admin/worklog-backend.git
                    git add deploy_manifest/
                    git diff --staged --quiet || git commit -m "deploy: update image tag to ${IMAGE_TAG} for ${TARGET_NAMESPACE}"
                    git pull --rebase origin ${BRANCH_NAME} || true
                    git push origin HEAD:${BRANCH_NAME}
                """
                echo "Deployed ${env.IMAGE_TAG} to ${env.TARGET_NAMESPACE}"
            }
        }
    }

    post {
        always { echo 'Job finished. Sending notifications ..' }
        success {
            echo "Pipeline completed — Env: ${env.TARGET_ENV}, Tag: ${env.IMAGE_TAG}"
        }
        failure {
            echo "Pipeline failed — Env: ${env.TARGET_ENV}, Tag: ${env.IMAGE_TAG}"
        }
        aborted {
            echo "Pipeline aborted — Env: ${env.TARGET_ENV}"
        }
    }
}
