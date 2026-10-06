import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from pydantic import SecretStr
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateSchema, DropSchema

from mono.config import Settings
from mono.database import open_engine
from mono.main import create_app
from mono.models import Actor, Terminal


@pytest.fixture
def system(tmp_path, monkeypatch):
    external = os.getenv("MONO_TEST_DATABASE_URL")
    parent = None
    schema = None
    if external:
        parent = open_engine(external)
        if parent.dialect.name != "postgresql":
            raise RuntimeError("MONO_TEST_DATABASE_URL must use PostgreSQL")
        schema = "mono_test_" + uuid4().hex
        with parent.begin() as connection:
            connection.execute(CreateSchema(schema))
        url = (
            make_url(external)
            .update_query_dict({"options": f"-csearch_path={schema}"})
            .render_as_string(hide_password=False)
        )
    else:
        url = f"sqlite:///{(tmp_path / 'test.db').as_posix()}"
    monkeypatch.setenv("MONO_DATABASE_URL", url)
    command.upgrade(Config("alembic.ini"), "head")
    engine = open_engine(url)
    terminal = str(uuid4())
    token = uuid4().hex + uuid4().hex
    settings = Settings(
        database_url=url,
        recette_mode=True,
        terminal_id=terminal,
        sync_token=SecretStr(token),
        token_expires_at=datetime.now(UTC) + timedelta(minutes=15),
    )
    with Session(engine) as session, session.begin():
        session.add(
            Terminal(slot=1, id=terminal, prefix=f"T{terminal.replace('-', '')[:8].upper()}")
        )
        session.add_all([Actor(id="admin", role="admin"), Actor(id="seller", role="seller")])
    with TestClient(create_app(settings, engine)) as client:
        client.headers["Authorization"] = f"Bearer {token}"
        yield client, engine, terminal, settings
    engine.dispose()
    if parent is not None:
        with parent.begin() as connection:
            connection.execute(DropSchema(schema, cascade=True))
        parent.dispose()


def catalog_event(terminal: str) -> dict:
    return {
        "id": str(uuid4()),
        "terminal_id": terminal,
        "sequence": 1,
        "version": 1,
        "kind": "catalog.created",
        "occurred_at": "2026-10-06T12:00:00Z",
        "actor_id": "admin",
        "payload": {
            "category_id": str(uuid4()),
            "category": "Chaussures",
            "product_id": str(uuid4()),
            "name": "Rangers noirs",
            "variant_id": str(uuid4()),
            "sku": "R42",
            "label": "Pointure 42",
            "price": 12500,
            "initial_stock": 5,
            "published": False,
        },
    }


def sale_event(catalog: dict) -> dict:
    c = catalog["payload"]
    terminal = catalog["terminal_id"]
    operation = str(uuid4())
    return {
        "id": operation,
        "terminal_id": terminal,
        "sequence": 2,
        "version": 1,
        "kind": "sale.completed",
        "occurred_at": "2026-10-06T12:01:00Z",
        "actor_id": "seller",
        "payload": {
            "id": operation,
            "number": "FACT-2026-00001",
            "occurred_at": "2026-10-06T12:01:00Z",
            "seller_id": "seller",
            "seller": "Vendeur test",
            "customer": {"name": "CLIENT TEST", "phone": "TEST"},
            "lines": [
                {
                    "variant_id": c["variant_id"],
                    "category": c["category"],
                    "name": c["name"],
                    "sku": c["sku"],
                    "label": c["label"],
                    "quantity": 2,
                    "unit_price": 12500,
                    "line_total": 25000,
                    "unit_cost": None,
                }
            ],
            "total": 25000,
            "payment_mode": "cash",
            "tendered": 30000,
            "change": 5000,
            "collected": 25000,
        },
    }
