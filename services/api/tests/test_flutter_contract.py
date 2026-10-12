import json
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from mono.main import create_app
from mono.models import Actor, Sale, SaleCorrection, SaleReturn, Terminal, Variant


def test_actual_flutter_outbox_matches_server(system):
    _, engine, _, settings = system
    fixture = json.loads(
        (Path(__file__).parents[3] / "contracts/vertical_v1.json").read_text("utf-8")
    )
    terminal_id = fixture["terminal_id"]
    settings.terminal_id = terminal_id
    with Session(engine) as session, session.begin():
        terminal = session.get(Terminal, 1)
        terminal.id = terminal_id
        terminal.prefix = f"T{terminal_id.replace('-', '')[:8].upper()}"
        # Only the conftest fixtures exist: the terminal's admin bootstraps itself.
        session.query(Actor).delete()
    with TestClient(create_app(settings, engine)) as client:
        client.headers["Authorization"] = f"Bearer {settings.sync_token.get_secret_value()}"
        for event in fixture["events"]:
            response = client.post("/api/private/sync/events", json=event)
            assert response.status_code == 200, response.text
            assert client.post("/api/private/sync/events", json=event).json() == response.json()
    with Session(engine) as session:
        expected = fixture["expected"]
        sold = select(Variant).where(Variant.sku == "TEST-42")
        assert session.scalar(sold).stock == expected["stock"]
        assert session.scalar(sold).price == expected["current_price"]
        assert session.scalar(select(func.count()).select_from(Variant)) == expected["variants"]
        assert session.scalar(select(func.sum(Sale.total))) == expected["total"]
        assert session.scalar(select(func.count()).select_from(Sale)) == expected["sale_count"]
        assert (
            session.scalar(select(func.count()).select_from(SaleCorrection))
            == expected["corrections"]
        )
        assert session.scalar(select(func.count()).select_from(Actor)) == expected["actors"]
        assert session.scalar(select(SaleCorrection.tendered)) == 25000
        assert session.scalar(select(func.sum(SaleReturn.refund_total))) == expected["refunded"]
