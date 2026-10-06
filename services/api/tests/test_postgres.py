from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from mono.main import create_app
from mono.models import Event, Sale, Variant
from tests.conftest import catalog_event, sale_event


def test_postgresql_concurrent_replay(system):
    client, engine, terminal, settings = system
    if engine.dialect.name != "postgresql":
        pytest.skip("Requires real PostgreSQL; executed by the CI service container")
    catalog = catalog_event(terminal)
    assert client.post("/api/private/sync/events", json=catalog).status_code == 200
    sale = sale_event(catalog)

    def send(_):
        with TestClient(create_app(settings, engine)) as parallel:
            return parallel.post(
                "/api/private/sync/events",
                json=sale,
                headers={"Authorization": f"Bearer {settings.sync_token.get_secret_value()}"},
            )

    with ThreadPoolExecutor(max_workers=6) as pool:
        responses = list(pool.map(send, range(6)))
    assert [r.status_code for r in responses] == [200] * 6
    assert all(r.json() == responses[0].json() for r in responses)
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(Sale)) == 1
        assert session.scalar(select(func.count()).select_from(Event)) == 2
        assert session.scalar(select(Variant.stock)) == 3
