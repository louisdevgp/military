from sqlalchemy import func, select
from sqlalchemy.orm import Session

from mono.models import Movement, SaleReturn, Variant
from tests.conftest import catalog_event, sale_event
from tests.test_users_corrections import ROUTE, envelope


def test_returns_bounded_priced_and_cancellation_complete(system):
    client, engine, terminal, _ = system
    catalog = catalog_event(terminal)  # stock 5, price 12 500
    sale = sale_event(catalog)  # 2 sold -> stock 3
    for event in (catalog, sale):
        assert client.post(ROUTE, json=event).status_code == 200
    variant = catalog["payload"]["variant_id"]

    def returned(sequence, quantity, *, kind="RETURN", price=12500, resaleable=True):
        e = envelope(terminal, sequence, "sale.returned", "admin", {})
        e["payload"] = {
            "id": e["id"],
            "sale_id": sale["id"],
            "sale_number": "FACT-2026-00001",
            "kind": kind,
            "lines": [
                {
                    "variant_id": variant,
                    "quantity": quantity,
                    "unit_price": price,
                    "line_total": quantity * price,
                    "resaleable": resaleable,
                }
            ],
            "refund_total": quantity * price,
            "refund_mode": "cash",
            "reason": "Retour TEST",
        }
        return client.post(ROUTE, json=e)

    assert returned(3, 3).json()["detail"] == "RETURN_EXCEEDS_SALE"
    assert returned(3, 1, price=1).json()["detail"] == "RETURN_LINE_MISMATCH"
    assert returned(3, 1, resaleable=False).status_code == 200  # damaged: stock unchanged
    assert returned(4, 2).json()["detail"] == "RETURN_EXCEEDS_SALE"
    with Session(engine) as session:
        assert session.get(Variant, variant).stock == 3
    # A cancellation must cover exactly what is left (1).
    assert returned(4, 1, kind="CANCEL").status_code == 200
    assert returned(5, 1, kind="CANCEL").json()["detail"] == "RETURN_EXCEEDS_SALE"
    with Session(engine) as session:
        assert session.get(Variant, variant).stock == 4
        assert session.scalar(select(func.sum(SaleReturn.refund_total))) == 25000
        kinds = session.scalars(select(Movement.kind).order_by(Movement.occurred_at)).all()
        assert kinds.count("RETURN") == 1
