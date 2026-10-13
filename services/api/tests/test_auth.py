from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr
from sqlalchemy import select
from sqlalchemy.orm import Session

from mono import auth
from mono.main import create_app
from mono.models import ActivationCode, TerminalCredential

ADMIN = "a" * 40
STATE = "/api/private/sync/state"


@pytest.fixture
def secured(system):
    _, engine, terminal, settings = system
    configured = settings.model_copy(
        update={"token_secret": SecretStr("s" * 40), "admin_token": SecretStr(ADMIN)}
    )
    with TestClient(create_app(configured, engine)) as client:
        yield client, engine, terminal


def new_code(client):
    response = client.post(
        "/api/admin/activation-code", headers={"Authorization": f"Bearer {ADMIN}"}
    )
    assert response.status_code == 200
    return response.json()["code"]


def activate(client, terminal, code):
    return client.post("/api/private/auth/activate", json={"terminal_id": terminal, "code": code})


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def test_admin_endpoint_requires_configured_token(system, secured):
    unconfigured = system[0]
    assert unconfigured.post("/api/admin/activation-code").status_code == 503
    client, _, _ = secured
    assert client.post("/api/admin/activation-code").status_code == 401
    wrong = client.post("/api/admin/activation-code", headers=bearer("b" * 40))
    assert wrong.status_code == 401
    assert len(new_code(client)) == 14


def test_activation_then_short_tokens(secured):
    client, engine, terminal = secured
    code = new_code(client)
    assert activate(client, "00000000-0000-4000-8000-000000000000", code).status_code == 401
    activated = activate(client, terminal, code.lower().replace("-", " "))
    assert activated.status_code == 200
    body = activated.json()
    assert body["credential"].startswith("mtc1.")
    assert client.get(STATE, headers=bearer(body["access_token"])).status_code == 200
    # Single use.
    assert activate(client, terminal, code).json()["detail"] == "ACTIVATION_INVALID"
    renewed = client.post("/api/private/auth/token", headers=bearer(body["credential"]))
    assert renewed.status_code == 200
    assert client.get(STATE, headers=bearer(renewed.json()["access_token"])).status_code == 200
    assert client.post("/api/private/auth/token", headers=bearer("mtc1.x.y")).status_code == 401
    tampered = body["access_token"][:-2] + (
        "AA" if not body["access_token"].endswith("AA") else "BB"
    )
    assert client.get(STATE, headers=bearer(tampered)).status_code == 401
    # Only digests are stored.
    with Session(engine) as session:
        stored = [
            *session.scalars(select(ActivationCode.code_hash)),
            *session.scalars(select(TerminalCredential.secret_hash)),
        ]
    secret = body["credential"].split(".")[2]
    assert all(code.replace("-", "") not in h and secret not in h for h in stored)


def test_wrong_codes_burn_the_live_code(secured):
    client, _, terminal = secured
    code = new_code(client)
    for _ in range(auth.ACTIVATION_MAX_FAILURES):
        assert activate(client, terminal, "ABCD-EFGH-JKMN").status_code == 401
    assert activate(client, terminal, code).status_code == 401


def test_new_code_replaces_previous(secured):
    client, _, terminal = secured
    first = new_code(client)
    second = new_code(client)
    assert activate(client, terminal, first).status_code == 401
    assert activate(client, terminal, second).status_code == 200


def test_revocation_and_reactivation(secured):
    client, _, terminal = secured
    first = activate(client, terminal, new_code(client)).json()
    second = activate(client, terminal, new_code(client)).json()
    # A new activation revokes the previous device at once.
    assert client.get(STATE, headers=bearer(first["access_token"])).json()["detail"] == (
        "CREDENTIAL_REVOKED"
    )
    assert client.get(STATE, headers=bearer(second["access_token"])).status_code == 200
    revoked = client.post("/api/admin/revoke-terminal", headers=bearer(ADMIN))
    assert revoked.json() == {"revoked": 1}
    assert client.get(STATE, headers=bearer(second["access_token"])).status_code == 401
    assert (
        client.post("/api/private/auth/token", headers=bearer(second["credential"])).status_code
        == 401
    )


def test_expired_access_token(secured, monkeypatch):
    client, _, terminal = secured
    monkeypatch.setattr(auth, "ACCESS_TTL", timedelta(seconds=-1))
    body = activate(client, terminal, new_code(client)).json()
    assert client.get(STATE, headers=bearer(body["access_token"])).json()["detail"] == (
        "TOKEN_EXPIRED"
    )


def test_tokens_refused_without_signing_key(system):
    client, _, terminal, _ = system
    assert activate(client, terminal, "ABCD-EFGH-JKMN").json()["detail"] == "AUTH_NOT_CONFIGURED"
