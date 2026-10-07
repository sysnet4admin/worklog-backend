FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS uv_builder

COPY ./pyproject.toml ./uv.lock /
RUN uv export --no-dev --no-hashes --no-emit-project -o requirements.txt

FROM python:3.14-slim-bookworm

WORKDIR /app/worklog
COPY ./src/worklog /app/worklog
COPY --from=uv_builder /requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt
# 런타임에는 pip가 필요 없다. 베이스 이미지 pip가 담아 둔 옛 라이브러리(pip/_vendor)가 Trivy에 걸리므로 지운다
RUN pip uninstall -y pip setuptools && rm -rf /usr/local/lib/python3.14/ensurepip

ENTRYPOINT ["fastapi"]
CMD ["run", "main.py", "--port", "80"]
