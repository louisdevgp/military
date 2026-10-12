from tests.conftest import catalog_event, sale_event
from tests.test_users_corrections import ROUTE


def test_state_and_events_for_reconciliation(system):
    client, _, terminal, settings = system
    catalog = catalog_event(terminal)
    sale = sale_event(catalog)
    for event in (catalog, sale):
        assert client.post(ROUTE, json=event).status_code == 200
    state = client.get("/api/private/sync/state").json()
    assert state == {"terminal_id": terminal, "last_sequence": 2, "sale_sequence": 1}
    page = client.get("/api/private/sync/events", params={"after": 0}).json()
    assert page["last_sequence"] == 2
    assert [e["id"] for e in page["events"]] == [catalog["id"], sale["id"]]
    # Envelopes come back exactly as sent: the terminal replays them as is.
    assert page["events"][1]["payload"]["number"] == sale["payload"]["number"]
    assert page["events"][1]["payload"]["lines"] == sale["payload"]["lines"]
    after_one = client.get("/api/private/sync/events", params={"after": 1, "limit": 1}).json()
    assert [e["sequence"] for e in after_one["events"]] == [2]
    assert client.get("/api/private/sync/events", params={"limit": 500}).status_code == 422
    for path in ("/api/private/sync/state", "/api/private/sync/events"):
        response = client.get(path, headers={"Authorization": "Bearer wrong"})
        assert response.status_code == 401
    settings.terminal_id = "00000000-0000-4000-8000-000000000000"
    assert client.get("/api/private/sync/state").status_code == 403
