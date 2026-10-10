FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS uv_builder

COPY ./pyproject.toml ./uv.lock /
RUN uv export --no-dev --no-hashes --no-emit-project -o requirements.txt

FROM python:3.14-slim-bookworm

WORKDIR /app/worklog
COPY ./src/worklog /app/worklog
COPY --from=uv_builder /requirements.txt /tmp/requirements.txt

# 베이스 이미지의 pip은 msgpack, urllib3, setuptools(pkg_resources) 사본을 번들한다.
# Trivy는 이 사본까지 별도 패키지로 잡는다. 실행에는 필요 없으므로 설치 후 pip을 지운다.
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && pip uninstall -y pip

ENTRYPOINT ["fastapi"]
CMD ["run", "main.py", "--port", "80"]
