FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS uv_builder

COPY ./pyproject.toml ./uv.lock /
RUN uv export --no-dev --no-hashes --no-emit-project -o requirements.txt

FROM python:3.14-slim-bookworm

WORKDIR /app/worklog
COPY ./src/worklog /app/worklog
COPY --from=uv_builder /requirements.txt /tmp/requirements.txt

# pip는 설치에만 쓰고 지운다. pip에 번들된 msgpack, urllib3, setuptools가
# 이미지에 남아 Trivy에 걸리는 것을 막는다. 앱 의존성이 아니라 pip의 내부 라이브러리다.
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && pip uninstall -y pip \
    && rm -f /tmp/requirements.txt

ENTRYPOINT ["fastapi"]
CMD ["run", "main.py", "--port", "80"]
