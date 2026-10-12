from uuid import uuid4

from tests.test_users_corrections import ROUTE, envelope


def test_expenses_closings_and_report_endpoint(system):
    client, _, terminal, _ = system
    expense = envelope(
        terminal,
        1,
        "expense.recorded",
        "admin",
        {
            "kind": "CHARGE",
            "category": "Transport",
            "amount": 2000,
            "payment_mode": "cash",
            "reason": "Livraison",
            "occurred_at": "2026-10-06T10:00:00Z",
        },
    )
    by_seller = expense | {"actor_id": "seller"}
    assert client.post(ROUTE, json=by_seller).json()["detail"] == "ADMIN_REQUIRED"
    assert client.post(ROUTE, json=expense).status_code == 200
    cancel = {"expense_id": expense["id"], "reason": "Doublon"}
    assert (
        client.post(
            ROUTE, json=envelope(terminal, 2, "expense.cancelled", "admin", cancel)
        ).status_code
        == 200
    )
    again = envelope(terminal, 3, "expense.cancelled", "admin", cancel)
    assert client.post(ROUTE, json=again).json()["detail"] == "EXPENSE_ALREADY_CANCELLED"
    missing = envelope(
        terminal, 3, "expense.cancelled", "admin", cancel | {"expense_id": str(uuid4())}
    )
    assert client.post(ROUTE, json=missing).json()["detail"] == "EXPENSE_MISSING"
    closing = {
        "period_start": "2020-01-01T00:00:00Z",
        "opening_float": 10000,
        "cash_sales": 15000,
        "cash_refunds": 0,
        "cash_expenses": 2000,
        "expected": 23000,
        "counted": 22500,
        "difference": -500,
        "kept_float": 10000,
        "comment": "Monnaie",
    }
    wrong = envelope(terminal, 3, "cash.closed", "admin", closing | {"expected": 1})
    assert client.post(ROUTE, json=wrong).json()["detail"] == "CASH_CLOSING_MISMATCH"
    kept = envelope(terminal, 3, "cash.closed", "admin", closing | {"kept_float": 30000})
    assert client.post(ROUTE, json=kept).json()["detail"] == "CASH_CLOSING_MISMATCH"
    assert (
        client.post(ROUTE, json=envelope(terminal, 3, "cash.closed", "admin", closing)).status_code
        == 200
    )
    params = {"start": "2026-10-06T00:00:00Z", "end": "2026-10-07T00:00:00Z"}
    report = client.get("/api/private/reports/summary", params=params).json()
    assert report["expenses_by_kind"] == {}, "dépense annulée exclue"
    assert (report["closings"], report["closing_gap"]) == (1, -500)
    swapped = {"start": params["end"], "end": params["start"]}
    assert client.get("/api/private/reports/summary", params=swapped).status_code == 422
    anonymous = client.get(
        "/api/private/reports/summary", params=params, headers={"Authorization": "Bearer x"}
    )
    assert anonymous.status_code == 401


def test_customer_fields_setting_is_admin_only_and_validated(system):
    client, _, terminal, _ = system
    payload = {"required": ["name", "phone"]}
    kind = "settings.customer_fields_updated"
    assert (
        client.post(ROUTE, json=envelope(terminal, 1, kind, "seller", payload)).json()["detail"]
        == "ADMIN_REQUIRED"
    )
    for bad in ({"required": ["email"]}, {"required": ["name", "name"]}):
        assert client.post(ROUTE, json=envelope(terminal, 1, kind, "admin", bad)).status_code == 422
    assert client.post(ROUTE, json=envelope(terminal, 1, kind, "admin", payload)).status_code == 200


def test_admin_recovery_events(system):
    client, _, terminal, _ = system
    recovered = {"user_id": "admin"}
    assert (
        client.post(
            ROUTE,
            json=envelope(terminal, 1, "user.admin_recovered", "seller", {"user_id": "seller"}),
        ).json()["detail"]
        == "ADMIN_REQUIRED"
    )
    assert (
        client.post(
            ROUTE,
            json=envelope(terminal, 1, "user.admin_recovered", "admin", {"user_id": "seller"}),
        ).json()["detail"]
        == "RECOVERY_ACTOR_MISMATCH"
    )
    assert (
        client.post(
            ROUTE,
            json=envelope(terminal, 1, "security.recovery_code_created", "admin", {"code": "x"}),
        ).status_code
        == 422
    )
    assert (
        client.post(
            ROUTE, json=envelope(terminal, 1, "user.admin_recovered", "admin", recovered)
        ).status_code
        == 200
    )
    assert (
        client.post(
            ROUTE, json=envelope(terminal, 2, "security.recovery_code_created", "admin", {})
        ).status_code
        == 200
    )
