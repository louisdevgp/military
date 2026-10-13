"""Terminal activation and short access tokens.

An administrator obtains a one-time activation code (15 minutes). The terminal
exchanges it for a device credential kept in the Android Keystore; the
credential only buys access tokens valid a few minutes. The server keeps
SHA-256 digests of codes and credentials, never the values.
"""

import base64
import hashlib
import hmac
import json
import secrets
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from mono.models import ActivationCode, Terminal, TerminalCredential

ACTIVATION_TTL = timedelta(minutes=15)
ACTIVATION_MAX_FAILURES = 5
ACCESS_TTL = timedelta(minutes=15)
CREDENTIAL_IDLE = timedelta(days=90)
CREDENTIAL_PREFIX = "mtc1"
ACCESS_PREFIX = "mta1"
# No 0/O, 1/I/L: the code is typed by hand on the terminal.
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


class AuthError(Exception):
    def __init__(self, code: str, status: int = 401):
        super().__init__(code)
        self.code = code
        self.status = status


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def normalize_code(value: str) -> str:
    return "".join(c for c in value.upper() if c not in " -")


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _terminal(session: Session) -> Terminal:
    terminal = session.scalar(select(Terminal).where(Terminal.slot == 1))
    if terminal is None:
        raise AuthError("TERMINAL_NOT_PROVISIONED", 503)
    return terminal


def issue_activation_code(session: Session, now: datetime) -> tuple[str, datetime]:
    """New code (12 characters, about 59 bits); earlier unused codes stop working."""
    _terminal(session)
    session.execute(
        update(ActivationCode).where(ActivationCode.used_at.is_(None)).values(used_at=now)
    )
    raw = "".join(secrets.choice(ALPHABET) for _ in range(12))
    expires = now + ACTIVATION_TTL
    session.add(
        ActivationCode(
            id=str(uuid4()),
            code_hash=digest(raw),
            created_at=now,
            expires_at=expires,
            failures=0,
        )
    )
    return f"{raw[:4]}-{raw[4:8]}-{raw[8:]}", expires


def _aware(value: datetime) -> datetime:
    # SQLite's test driver strips offsets; all stored instants are UTC.
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def activate(session: Session, terminal_id: str, code: str, now: datetime) -> str | None:
    """Consumes the code; revokes earlier credentials (single active terminal).

    Returns the credential to hand to the terminal, or None after recording a
    failed attempt (the caller commits it, then refuses).
    """
    terminal = _terminal(session)
    pending = session.scalars(
        select(ActivationCode).where(ActivationCode.used_at.is_(None)).with_for_update()
    ).all()
    live = [c for c in pending if _aware(c.expires_at) > now]
    match = next(
        (c for c in live if hmac.compare_digest(c.code_hash, digest(normalize_code(code)))), None
    )
    if match is None or terminal.id != terminal_id:
        # Each wrong attempt counts against every live code: guessing is capped.
        for candidate in live:
            candidate.failures += 1
            if candidate.failures >= ACTIVATION_MAX_FAILURES:
                candidate.used_at = now
        return None
    match.used_at = now
    session.execute(
        update(TerminalCredential)
        .where(TerminalCredential.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    credential_id = str(uuid4())
    secret = _b64(secrets.token_bytes(32))
    session.add(
        TerminalCredential(
            id=credential_id,
            terminal_id=terminal.id,
            secret_hash=digest(secret),
            created_at=now,
            last_used_at=now,
        )
    )
    return f"{CREDENTIAL_PREFIX}.{credential_id}.{secret}"


def _live_credential(session: Session, credential_id: str, now: datetime) -> TerminalCredential:
    credential = session.get(TerminalCredential, credential_id)
    if credential is None or credential.revoked_at is not None:
        raise AuthError("CREDENTIAL_REVOKED")
    if _aware(credential.last_used_at) + CREDENTIAL_IDLE < now:
        raise AuthError("CREDENTIAL_EXPIRED")
    return credential


def exchange(
    session: Session, credential: str, secret_key: str, now: datetime
) -> tuple[str, datetime]:
    """Access token for a valid device credential."""
    parts = credential.split(".")
    if len(parts) != 3 or parts[0] != CREDENTIAL_PREFIX:
        raise AuthError("UNAUTHORIZED")
    row = _live_credential(session, parts[1], now)
    if not hmac.compare_digest(row.secret_hash, digest(parts[2])):
        raise AuthError("UNAUTHORIZED")
    row.last_used_at = now
    expires = now + ACCESS_TTL
    body = _b64(
        json.dumps(
            {"c": row.id, "t": row.terminal_id, "e": int(expires.timestamp())},
            separators=(",", ":"),
        ).encode()
    )
    signature = _b64(
        hmac.new(secret_key.encode(), f"{ACCESS_PREFIX}.{body}".encode(), "sha256").digest()
    )
    return f"{ACCESS_PREFIX}.{body}.{signature}", expires


def verify_access(session: Session, token: str, secret_key: str, now: datetime) -> str:
    """Terminal id of a valid access token; revocation applies immediately."""
    parts = token.split(".")
    if len(parts) != 3 or parts[0] != ACCESS_PREFIX:
        raise AuthError("UNAUTHORIZED")
    expected = _b64(
        hmac.new(secret_key.encode(), f"{ACCESS_PREFIX}.{parts[1]}".encode(), "sha256").digest()
    )
    if not hmac.compare_digest(expected, parts[2]):
        raise AuthError("UNAUTHORIZED")
    try:
        claims = json.loads(_unb64(parts[1]))
        credential_id, terminal_id, expiry = claims["c"], claims["t"], int(claims["e"])
    except (ValueError, KeyError, TypeError) as exc:
        raise AuthError("UNAUTHORIZED") from exc
    if now.timestamp() >= expiry:
        raise AuthError("TOKEN_EXPIRED")
    credential = _live_credential(session, credential_id, now)
    if credential.terminal_id != terminal_id:
        raise AuthError("UNAUTHORIZED")
    return terminal_id


def revoke_all(session: Session, now: datetime) -> int:
    result = session.execute(
        update(TerminalCredential)
        .where(TerminalCredential.revoked_at.is_(None))
        .values(revoked_at=now)
    )
    return result.rowcount or 0
