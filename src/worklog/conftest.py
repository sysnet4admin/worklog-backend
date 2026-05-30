import pytest
from httpx import ASGITransport, AsyncClient

from worklog.main import app


@pytest.fixture()
async def test_client() -> AsyncClient:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test", follow_redirects=True) as client:
        yield client
