# Worklog Backend API

## 로컬 개발

로컬개발은 크게 [docker compose](https://docs.docker.com/compose/) 를 이용한 방법과 [Virtualenv](https://virtualenv.pypa.io/en/latest/)를 이용한 방법이 있습니다.
### 1. Docker Compose 를 이용한 로컬 개발 및 실행 (추천)

로컬에서 프로젝트를 실행하기 위해서는 다음 커맨드를 입력합니다.
```bash
$ docker compose up
```
만약 전체 리포지토리를 다시 빌드해야 할 경우에는 (예를들어 `Dockerfile`이 변경되었거나 리포지토리의 `./src/` 경로 안의 파일들 이외에 새로운 파일이 생겼을 경우) `--build` 플래그를 추가하면 됩니다.

```bash
$ docker compose up --build
```
정상적으로 `docker compose`가 시작되었다면 해당 로컬주소를 통해 백엔드 서비스의 [Swagger](https://swagger.io/)에 접속할 수 있습니다.

👉 [http://localhost:8000](http://localhost:8000)

Swagger를 통해 [CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) 를 확인 및 실행할 수 있고, `curl -X <method> http://localhost:8000/..` 과 같은 방식을 통해서도 테스트 가능합니다.
로컬의 데이터베이스에 저장하는 모든 데이터는 사용자의 로컬 디스크에 볼륨으로 저장되게 되고, 때문에 위의 커맨드를 종료했다가 다시 실행해도 같은 데이터를 갖고 작업할 수 있습니다.

로컬에서 실행중인 `docker compose`를 종료하기 위해서는 `Ctrl+C` 를 누르면 됩니다.
만약 서비스 종료 뿐 아니라 로컬에 있는 데이터베이스 정보까지 삭제하기 원한다면 해당 커맨드를 입력합니다.
```bash
$ docker compose down --volumes
```

### 2. venv를 이용한 로컬 개발 및 실행
해당 프로젝트는 [Poetry](https://python-poetry.org/docs/)를 이용하여 dependency 관리를 하고 있습니다.
Docker를 사용하지 않고 Virtualenv를 이용해 개발을 원한다면 Poetry를 위의 경로에서 설치 후 다음과 같이 패키지들을 설치합니다.

*(Optional)* 만약 Virtualenv 디렉터리의 위치를 프로젝트내에 위치하고 싶다면 해당 커맨드를 먼저 입력 한 후에 아래 커맨드들을 실행하면 됩니다.
```bash
poetry config virtualenvs.in-project true
poetry config virtualenvs.path .venv
```
위의 커맨드를 실행하지 않을 경우 Virtualenv 디렉터리는 Poetry가 자체적으로 관리하고 해당 정보는 `poetry env info`로 찾아 볼 수 있습니다.

```bash
$ poetry install
```
모든 패키지가 Virtualenv에 설치가 되면 다음의 커맨드로 해당 환경을 활성화 시킵니다.
```bash
$ poetry shell
```
해당 프로젝트를 로컬에서 실행하기 위해서는 [MongoDB](https://www.mongodb.com/)를 직접 로컬환경에 설치하거나 Docker 이미지를 사용해야 합니다.
만약 Docker를 이용하기 원한다면 다음의 커맨드를 실행합니다.

> :warning: **주의:** 만약 아래의 Username과 Password값을 변경하기를 원한다면 `.env.local`에 있는 값을 동일하게 맞춰주어야 합니다.

```bash
$ docker run -d -p 27017:27017 \
    --name worklog_mongodb \
    -e MONGO_HOST=0.0.0.0 \
    -e MONGO_INITDB_ROOT_USERNAME=root \
    -e MONGO_INITDB_ROOT_PASSWORD=mypassw0rd  \
    mongo:7.0.9-jammy

d44a7f1057a359248ea9805e662f0f7de9e6cd8cc7fbe4db8106b8c2f47f8763


$ docker ps
CONTAINER ID   IMAGE               COMMAND                  CREATED         STATUS        PORTS                      NAMES
d44a7f1057a3   mongo:7.0.9-jammy   "docker-entrypoint.s…"   2 seconds ago   Up 1 second   0.0.0.0:27017->27017/tcp   worklog_mongodb
```
해당 mongoDB 이미지가 잘 작동하는걸 확인하면 백엔드 서비스를 개발모드로 실행시켜줍니다.
```bash
$ fastapi dev src/worklog/main.py
```

정상적으로 MongoDB 컨테이너와 FastAPI 서버가 시작되었다면 해당 로컬주소를 통해 백엔드 서비스의 [Swagger](https://swagger.io/)에 접속할 수 있습니다.
Swagger를 통해 [CRUD](https://en.wikipedia.org/wiki/Create,_read,_update_and_delete) 를 확인 및 실행할 수 있고, `curl -X <method> http://localhost:8000/..` 과 같은 방식을 통해서도 테스트 가능합니다.
해당 방식은 현재 volume을 붙이고 있지 않고 있어서 MongoDB 컨테이너가 종료되면 모든 작업이 사라지게 됩니다. 만약 volume을 붙여서 MongoDB 컨테이너에 있는 내용을 유지하고 싶다면 위의 `docker compose`를 이용하거나 [해당 문서](https://docs.docker.com/storage/volumes/#create-and-manage-volumes)를 참고해주세요.

👉 [http://localhost:8000](http://localhost:8000)

모든 개발 작업이 끝나면 `Ctrl+C`를 이용해 FastAPI 개발 서버를 종료시킬 수 있고, MongoDB 컨테이너는 다음과 같이 종료시킬 수 있습니다.
```bash
$ docker kill worklog_mongodb
```


### 테스트
개발이 끝났다면 다음과 같이 test 결과 및 code coverage를 확인 할 수 있습니다.

Unit Test:
```bash
$ TESTING=true poetry run coverage run --source ./src/worklog -m pytest --disable-warnings -v
```

Code Coverage:
```bash
$ poetry run coverage report
```

### 포맷팅
자동 코드 포맷팅:
```bash
$ poetry run black .
```

자동 import 순서 포맷팅:
```bash
$ poetry run isort --profile black .
```
# verify ch8.5
