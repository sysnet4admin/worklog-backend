from fastapi import FastAPI

from worklog.routers.health import health
from worklog.routers.todos import todos
from worklog.settings import settings

app_description = """
Worklog FastAPI backend with MongoDB for [k8s CI/CD course](https://github.com/sungmincs/_Lecture_cicd_learning.kit/tree/main)
"""

app = FastAPI(
    title="Worklog API",
    description=app_description,
    version="0.0.1",
    docs_url="/",
    root_path=settings.root_path,
    license_info={
        "name": "MIT",
        "identifier": "MIT",
    },
)

app.include_router(
    health.router,
    prefix="/health",
)

app.include_router(
    todos.router,
    prefix="/api/v1/todos",
    tags=["todos"],
)
