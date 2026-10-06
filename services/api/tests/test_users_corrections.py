from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from mono.models import Actor, Sale, SaleCorrection
from tests.conftest import catalog_event, sale_event

ROUTE = "/api/private/sync/events"


def envelope(terminal: str, sequence: int, kind: str, actor: str, payload: dict) -> dict:
    return {
        "id": str(uuid4()),
        "terminal_id": terminal,
        "sequence": sequence,
        "version": 1,
        "kind": kind,
        "occurred_at": "2026-10-06T13:00:00Z",
        "actor_id": actor,
        "payload": payload,
    }


def test_first_admin_bootstraps_once_then_admins_create_users(system):
    client, engine, terminal, _ = system
    boss = str(uuid4())
    first = envelope(
        terminal, 1, "user.created", boss, {"user_id": boss, "name": "Awa", "role": "admin"}
    )
    assert client.post(ROUTE, json=first).status_code == 200
    assert client.post(ROUTE, json=first).status_code == 200  # replay is idempotent
    intruder = str(uuid4())
    second = envelope(
        terminal,
        2,
        "user.created",
        intruder,
        {"user_id": intruder, "name": "Intrus", "role": "admin"},
    )
    assert client.post(ROUTE, json=second).json()["detail"] == "ACTOR_NOT_AUTHORIZED"
    clerk = str(uuid4())
    hire = envelope(
        terminal, 2, "user.created", boss, {"user_id": clerk, "name": "Koffi", "role": "seller"}
    )
    assert client.post(ROUTE, json=hire).status_code == 200
    by_seller = envelope(
        terminal, 3, "user.created", clerk, {"user_id": str(uuid4()), "name": "X", "role": "admin"}
    )
    assert client.post(ROUTE, json=by_seller).status_code in {403, 422}
    reset = envelope(terminal, 3, "user.pin_reset", boss, {"user_id": clerk})
    assert client.post(ROUTE, json=reset).status_code == 200
    leave = envelope(terminal, 4, "user.updated", boss, {"user_id": clerk, "active": False})
    assert client.post(ROUTE, json=leave).status_code == 200
    with Session(engine) as session:
        assert session.get(Actor, boss).name == "Awa"
        assert session.get(Actor, clerk).active is False
    # A deactivated seller can no longer submit operations.
    stale = envelope(terminal, 5, "user.pin_reset", clerk, {"user_id": clerk})
    assert client.post(ROUTE, json=stale).json()["detail"] == "ACTOR_NOT_AUTHORIZED"


def test_pin_material_is_rejected_from_events(system):
    client, _, terminal, _ = system
    leak = envelope(terminal, 1, "user.pin_reset", "admin", {"user_id": "seller", "pin": "123"})
    assert client.post(ROUTE, json=leak).status_code == 422


def test_payment_correction_validated_and_sale_untouched(system):
    client, engine, terminal, _ = system
    catalog = catalog_event(terminal)
    sale = sale_event(catalog)
    for event in (catalog, sale):
        assert client.post(ROUTE, json=event).status_code == 200
    base = {
        "sale_id": sale["id"],
        "sale_number": "FACT-2026-00001",
        "payment_mode": "cash",
        "tendered": 25000,
        "change": 0,
        "reason": "Somme remise corrigée",
    }
    for change, detail in [
        ({"tendered": 20000, "change": 0}, "CASH_MISMATCH"),
        ({"change": 5000}, "CASH_MISMATCH"),
        ({"payment_mode": "mobileMoney"}, "PAYMENT_MISMATCH"),
        ({"sale_number": "FACT-2026-00009"}, "SALE_IDENTITY_MISMATCH"),
        ({"sale_id": str(uuid4())}, "SALE_MISSING"),
    ]:
        bad = envelope(terminal, 3, "sale.payment_corrected", "admin", base | change)
        assert client.post(ROUTE, json=bad).json()["detail"] == detail
    by_seller = envelope(terminal, 3, "sale.payment_corrected", "seller", base)
    assert client.post(ROUTE, json=by_seller).json()["detail"] == "ADMIN_REQUIRED"
    good = envelope(terminal, 3, "sale.payment_corrected", "admin", base)
    assert client.post(ROUTE, json=good).status_code == 200
    mobile = envelope(
        terminal,
        4,
        "sale.payment_corrected",
        "admin",
        base | {"payment_mode": "mobileMoney", "tendered": None, "change": 0},
    )
    assert client.post(ROUTE, json=mobile).status_code == 200
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(SaleCorrection)) == 2
        snapshot = session.get(Sale, sale["id"]).snapshot
        assert snapshot["tendered"] == 30000 and snapshot["change"] == 5000


def test_receipt_settings_event_admin_only_and_validated(system):
    client, _, terminal, _ = system
    payload = {"shop_name": "UNIVERS DU MONO", "contacts": "0700", "footer": "", "logo": "custom"}
    by_seller = envelope(terminal, 1, "settings.receipt_updated", "seller", payload)
    assert client.post(ROUTE, json=by_seller).json()["detail"] == "ADMIN_REQUIRED"
    too_long = envelope(
        terminal, 1, "settings.receipt_updated", "admin", payload | {"shop_name": "x" * 41}
    )
    assert client.post(ROUTE, json=too_long).status_code == 422
    with_image = envelope(
        terminal, 1, "settings.receipt_updated", "admin", payload | {"logo_png": "AAAA"}
    )
    assert client.post(ROUTE, json=with_image).status_code == 422
    good = envelope(terminal, 1, "settings.receipt_updated", "admin", payload)
    assert client.post(ROUTE, json=good).status_code == 200
