FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS uv_builder

COPY ./pyproject.toml ./uv.lock /
RUN uv export --no-dev --no-hashes --no-emit-project -o requirements.txt

FROM python:3.14-slim-bookworm

# 보안 강화(ch9.6): 베이스 이미지의 fix 가능한 OS 패키지 취약점(CVE) 업그레이드
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app/worklog
COPY ./src/worklog /app/worklog
COPY --from=uv_builder /requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt

ENTRYPOINT ["fastapi"]
CMD ["run", "main.py", "--port", "80"]
