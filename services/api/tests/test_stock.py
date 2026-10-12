from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from mono.models import Movement, Variant
from tests.conftest import catalog_event
from tests.test_users_corrections import ROUTE, envelope


def test_stock_movements_counts_threshold_and_status(system):
    client, engine, terminal, _ = system
    catalog = catalog_event(terminal)  # stock 5
    assert client.post(ROUTE, json=catalog).status_code == 200
    variant = catalog["payload"]["variant_id"]

    def move(sequence, payload, actor="admin"):
        body = {"variant_id": variant, "reason": "Contrôle TEST"} | payload
        return client.post(ROUTE, json=envelope(terminal, sequence, "stock.moved", actor, body))

    assert move(2, {"kind": "RECEPTION", "quantity": 4}).status_code == 200  # 9
    assert move(3, {"kind": "LOSS", "quantity": 2}).json()["detail"] == "QUANTITY_SIGN_MISMATCH"
    assert move(3, {"kind": "LOSS", "quantity": -2}).status_code == 200  # 7
    assert move(4, {"kind": "LOSS", "quantity": -8}).json()["detail"] == "INSUFFICIENT_STOCK"
    assert move(4, {"kind": "ADJUSTMENT", "quantity": -1}, actor="seller").json()["detail"] == (
        "ADMIN_REQUIRED"
    )
    bad_count = {"kind": "ADJUSTMENT", "quantity": -1, "counted": 4}
    assert move(4, bad_count).json()["detail"] == "COUNT_MISMATCH"
    assert move(4, {"kind": "ADJUSTMENT", "quantity": -1, "counted": 6}).status_code == 200
    update = envelope(
        terminal, 5, "variant.updated", "admin", {"variant_id": variant, "threshold": 3}
    )
    assert client.post(ROUTE, json=update).status_code == 200
    off = envelope(
        terminal, 6, "variant.updated", "admin", {"variant_id": variant, "active": False}
    )
    assert client.post(ROUTE, json=off).status_code == 200
    empty = envelope(terminal, 7, "variant.updated", "admin", {"variant_id": variant})
    assert client.post(ROUTE, json=empty).status_code == 422
    missing = envelope(
        terminal, 7, "variant.updated", "admin", {"variant_id": str(uuid4()), "active": True}
    )
    assert client.post(ROUTE, json=missing).json()["detail"] == "VARIANT_MISSING"
    with Session(engine) as session:
        v = session.get(Variant, variant)
        assert (v.stock, v.threshold, v.active) == (6, 3, False)
        movements = session.scalars(select(Movement).order_by(Movement.occurred_at)).all()
        assert [(m.kind, m.quantity) for m in movements] == [
            ("INITIAL", 5),
            ("RECEPTION", 4),
            ("LOSS", -2),
            ("ADJUSTMENT", -1),
        ]
        assert movements[-1].counted == 6
