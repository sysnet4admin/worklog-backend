FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS uv_builder

COPY ./pyproject.toml ./uv.lock /
RUN uv export --no-dev --no-hashes --no-emit-project -o requirements.txt

FROM python:3.14-slim-bookworm

WORKDIR /app/worklog
COPY ./src/worklog /app/worklog
COPY --from=uv_builder /requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt
# 앱은 실행할 때 pip가 필요 없다. pip와 pip가 _vendor에 담아 둔 urllib3, msgpack, setuptools를
# 런타임 이미지에서 지운다(Trivy HIGH). ensurepip에는 pip 설치 파일(whl)이 남아 있어 함께 지운다.
RUN pip uninstall -y pip setuptools && rm -rf /usr/local/lib/python3.14/ensurepip

ENTRYPOINT ["fastapi"]
CMD ["run", "main.py", "--port", "80"]
