from copy import deepcopy
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from mono.models import Event, Movement, Product, Sale, Terminal, Variant
from tests.conftest import catalog_event, sale_event

ROUTE = "/api/private/sync/events"


def test_replay_and_lost_response(system):
    client, engine, terminal, _ = system
    catalog = catalog_event(terminal)
    sale = sale_event(catalog)
    assert client.post(ROUTE, json=catalog).status_code == 200
    first = client.post(ROUTE, json=sale)
    assert first.status_code == 200, first.text
    # Simulate a lost network response: client resends an already committed request.
    second = client.post(ROUTE, json=sale)
    assert second.json() == first.json()
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(Sale)) == 1
        assert session.scalar(select(Variant.stock)) == 3
        assert session.scalar(select(func.sum(Movement.quantity))) == 3
        assert session.get(Terminal, 1).last_sequence == 2


def test_same_uuid_different_content(system):
    client, _, terminal, _ = system
    e = catalog_event(terminal)
    assert client.post(ROUTE, json=e).status_code == 200
    e["payload"]["price"] += 1
    result = client.post(ROUTE, json=e)
    assert result.status_code == 409
    assert result.json()["detail"] == "IDEMPOTENCY_CONFLICT"


def test_out_of_order_and_sequence_reuse(system):
    client, engine, terminal, _ = system
    e = catalog_event(terminal)
    sale = sale_event(e)
    assert client.post(ROUTE, json=sale).status_code == 409
    assert client.post(ROUTE, json=e).status_code == 200
    reused = deepcopy(e)
    reused["id"] = str(uuid4())
    assert client.post(ROUTE, json=reused).status_code == 409
    assert client.post(ROUTE, json=sale).status_code == 200
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(Event)) == 2


@pytest.mark.parametrize("change", ["stock", "total", "price", "cash", "number", "duplicate"])
def test_invalid_sale_rolls_back_everything(system, change):
    client, engine, terminal, _ = system
    e = catalog_event(terminal)
    assert client.post(ROUTE, json=e).status_code == 200
    sale = sale_event(e)
    p = sale["payload"]
    if change == "stock":
        p["lines"][0].update(quantity=6, line_total=75000)
    elif change == "total":
        p["total"] = 1
    elif change == "price":
        p["lines"][0]["unit_price"] = 1
    elif change == "cash":
        p["change"] = 0
    elif change == "number":
        p["number"] = "wrong"
    else:
        p["lines"].append(deepcopy(p["lines"][0]))
    assert client.post(ROUTE, json=sale).status_code == 409
    with Session(engine) as session:
        assert session.scalar(select(Variant.stock)) == 5
        assert session.scalar(select(func.count()).select_from(Sale)) == 0
        assert session.scalar(select(func.count()).select_from(Movement)) == 1
        assert session.get(Terminal, 1).last_sequence == 1


def test_sizes_share_one_product(system):
    client, engine, terminal, _ = system
    first = catalog_event(terminal)
    assert client.post(ROUTE, json=first).status_code == 200
    second = deepcopy(first)
    second.update(id=str(uuid4()), sequence=2)
    second["payload"].update(variant_id=str(uuid4()), sku="R43", label="Pointure 43")
    assert client.post(ROUTE, json=second).status_code == 200
    third = deepcopy(second)
    third.update(id=str(uuid4()), sequence=3)
    third["payload"].update(variant_id=str(uuid4()), sku="R44", name="Autre nom")
    assert client.post(ROUTE, json=third).json()["detail"] == "PRODUCT_CONFLICT"
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(Variant)) == 2


def test_variant_colour_and_size_are_stored(system):
    client, engine, terminal, _ = system
    event = catalog_event(terminal)
    event["payload"].update(sku="RAN-NOIR-42", label="Noir · Pointure 42", color="Noir", size="42")
    assert client.post(ROUTE, json=event).status_code == 200
    with Session(engine) as session:
        variant = session.scalar(select(Variant))
        assert (variant.color, variant.size) == ("Noir", "42")
    bad = catalog_event(terminal)
    bad.update(sequence=2)
    bad["payload"].update(sku="X", color="")
    assert client.post(ROUTE, json=bad).status_code == 422


def test_sale_number_formats(system):
    client, engine, terminal, _ = system
    assert client.post(ROUTE, json=(e := catalog_event(terminal))).status_code == 200
    sale = sale_event(e)
    sale["payload"]["number"] = "FACT-2026-00002"  # skips the persistent sequence
    assert client.post(ROUTE, json=sale).json()["detail"] == "SALE_NUMBER_MISMATCH"
    # Unsynchronized recette 0.2 outboxes still carry the terminal-prefix format.
    sale["payload"]["number"] = f"T{terminal.replace('-', '')[:8].upper()}-2026-000001"
    assert client.post(ROUTE, json=sale).status_code == 200
    with Session(engine) as session:
        assert session.get(Terminal, 1).sale_sequence == 1


def test_permissions_terminal_and_expiry(system):
    client, _, terminal, settings = system
    e = catalog_event(terminal)
    assert client.post(ROUTE, json=e, headers={"Authorization": "Bearer wrong"}).status_code == 401
    e["actor_id"] = "seller"
    assert client.post(ROUTE, json=e).status_code == 403
    e["actor_id"] = "unknown"
    assert client.post(ROUTE, json=e).status_code == 403
    e["actor_id"] = "admin"
    e["terminal_id"] = str(uuid4())
    assert client.post(ROUTE, json=e).status_code == 403
    settings.token_expires_at = datetime.now(UTC) - timedelta(seconds=1)
    assert client.post(ROUTE, json=e).status_code == 401


def test_strict_validation_and_no_sensitive_error_echo(system):
    client, _, terminal, _ = system
    e = catalog_event(terminal)
    e["payload"]["price"] = 1.5
    assert client.post(ROUTE, json=e).status_code == 422
    e["customer_secret"] = "PRIVATE INPUT"
    result = client.post(ROUTE, json=e)
    assert result.status_code == 422
    assert "PRIVATE INPUT" not in result.text
    result = client.post(ROUTE, content=b"x" * 262145)
    assert result.status_code == 413


def test_public_catalog_whitelist_and_no_default_publication(system):
    client, engine, terminal, _ = system
    e = catalog_event(terminal)
    assert client.post(ROUTE, json=e).status_code == 200
    assert client.post(ROUTE, json=sale_event(e)).status_code == 200
    client.headers.pop("Authorization")
    assert client.get("/api/public/catalog").json()["items"] == []
    # Test fixture simulates a later admin publication event; no public mutation route exists.
    with Session(engine) as session, session.begin():
        session.get(Product, e["payload"]["product_id"]).published = True
    result = client.get("/api/public/catalog").json()
    assert set(result["items"][0]) == {"id", "name", "category", "variants"}
    assert set(result["items"][0]["variants"][0]) == {"sku", "label"}
    for secret in ["CLIENT TEST", "unit_cost", "stock", "collected", "seller"]:
        assert secret not in str(result)
    assert client.get("/api/public/catalog?limit=101").status_code == 422
    assert client.post("/api/public/catalog", json={}).status_code == 405
    assert client.post(ROUTE, json=e).status_code == 401


def test_database_constraints_and_migration_preservation(system):
    client, engine, terminal, _ = system
    e = catalog_event(terminal)
    assert client.post(ROUTE, json=e).status_code == 200
    command.upgrade(Config("alembic.ini"), "head")
    with Session(engine) as session:
        assert session.scalar(select(Variant.stock)) == 5
        original = session.get(Event, e["id"])
        duplicate = Event(
            id=str(uuid4()),
            terminal_id=terminal,
            sequence=1,
            fingerprint=original.fingerprint,
            version=1,
            kind=original.kind,
            occurred_at=original.occurred_at,
            received_at=original.received_at,
            actor_id="admin",
            envelope={},
        )
        session.add(duplicate)
        with pytest.raises(IntegrityError):
            session.commit()
    with engine.begin() as connection, pytest.raises(IntegrityError):
        connection.execute(text("UPDATE variants SET stock=-1"))
    assert client.get("/health/ready").status_code == 200
