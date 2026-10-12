import hashlib
import json
from datetime import UTC, datetime
from uuid import uuid4

from pydantic import ValidationError
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from mono.models import (
    Actor,
    Category,
    Event,
    Movement,
    Product,
    Sale,
    SaleCorrection,
    Terminal,
    Variant,
)
from mono.schemas import (
    Acknowledgement,
    CatalogCreated,
    Envelope,
    PaymentCorrected,
    PriceChanged,
    ReceiptSettingsUpdated,
    SaleCompleted,
    StockMoved,
    UserCreated,
    UserPinReset,
    UserUpdated,
    VariantUpdated,
)


class SyncError(Exception):
    def __init__(self, code: str, status: int = 409):
        self.code = code
        self.status = status


def fingerprint(event: Envelope) -> str:
    content = json.dumps(event.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(content.encode()).hexdigest()


def ack(event: Event) -> Acknowledgement:
    received = event.received_at
    if received.tzinfo is None:  # SQLite's test driver strips offsets; all stored instants are UTC.
        received = received.replace(tzinfo=UTC)
    return Acknowledgement(
        id=event.id, terminal_id=event.terminal_id, sequence=event.sequence, received_at=received
    )


def apply_event(session: Session, incoming: Envelope) -> Acknowledgement:
    # A single provisioned terminal row serializes concurrent requests in PostgreSQL.
    terminal = session.scalar(select(Terminal).where(Terminal.slot == 1).with_for_update())
    if terminal is None or terminal.id != str(incoming.terminal_id):
        raise SyncError("TERMINAL_NOT_AUTHORIZED", 403)
    content_hash = fingerprint(incoming)
    previous = session.get(Event, str(incoming.id))
    if previous:
        if previous.fingerprint != content_hash:
            raise SyncError("IDEMPOTENCY_CONFLICT")
        return ack(previous)
    if incoming.sequence != terminal.last_sequence + 1:
        raise SyncError("SEQUENCE_MISMATCH")
    try:
        actor = session.get(Actor, incoming.actor_id)
        bootstrapped = actor is None and bootstrap_admin(session, incoming)
        if bootstrapped:
            actor = session.get(Actor, incoming.actor_id)
        if actor is None or not actor.active:
            raise SyncError("ACTOR_NOT_AUTHORIZED", 403)
        if incoming.kind != "sale.completed" and actor.role != "admin":
            raise SyncError("ADMIN_REQUIRED", 403)
        if incoming.kind == "catalog.created":
            create_catalog(session, incoming, CatalogCreated.model_validate(incoming.payload))
        elif incoming.kind == "variant.price_changed":
            payload = PriceChanged.model_validate(incoming.payload)
            variant = session.get(Variant, str(payload.variant_id))
            if variant is None:
                raise SyncError("VARIANT_MISSING")
            variant.price = payload.price
        elif incoming.kind == "sale.completed":
            create_sale(session, terminal, incoming, SaleCompleted.model_validate(incoming.payload))
        elif incoming.kind == "sale.payment_corrected":
            correct_payment(session, incoming, PaymentCorrected.model_validate(incoming.payload))
        elif incoming.kind == "user.created":
            if not bootstrapped:
                create_user(session, UserCreated.model_validate(incoming.payload))
        elif incoming.kind == "user.updated":
            payload = UserUpdated.model_validate(incoming.payload)
            target_user(session, payload.user_id).active = payload.active
        elif incoming.kind == "user.pin_reset":
            target_user(session, UserPinReset.model_validate(incoming.payload).user_id)
        elif incoming.kind == "stock.moved":
            move_stock(session, incoming, StockMoved.model_validate(incoming.payload))
        elif incoming.kind == "variant.updated":
            update_variant(session, VariantUpdated.model_validate(incoming.payload))
        else:
            # Recorded in the event log only; no server projection yet.
            ReceiptSettingsUpdated.model_validate(incoming.payload)
    except ValidationError as exc:
        raise SyncError("INVALID_PAYLOAD", 422) from exc
    event = Event(
        id=str(incoming.id),
        terminal_id=terminal.id,
        sequence=incoming.sequence,
        fingerprint=content_hash,
        version=incoming.version,
        kind=incoming.kind,
        occurred_at=incoming.occurred_at.astimezone(UTC),
        received_at=datetime.now(UTC),
        actor_id=actor.id,
        envelope=incoming.model_dump(mode="json"),
    )
    session.add(event)
    terminal.last_sequence = incoming.sequence
    session.flush()
    return ack(event)  # Caller must commit before sending this to the client.


def bootstrap_admin(session: Session, event: Envelope) -> bool:
    """The terminal's first administrator registers itself, exactly once.

    Accepted only for a self-created admin while no user.created event was ever
    applied; afterwards every account is created by an existing admin.
    """
    if event.kind != "user.created":
        return False
    data = UserCreated.model_validate(event.payload)
    if data.user_id != event.actor_id or data.role != "admin":
        return False
    if session.scalar(select(Event.id).where(Event.kind == "user.created").limit(1)):
        return False
    session.add(Actor(id=data.user_id, role="admin", active=True, name=data.name))
    session.flush()
    return True


def create_user(session: Session, data: UserCreated) -> None:
    if session.get(Actor, data.user_id) is not None:
        raise SyncError("USER_EXISTS")
    session.add(Actor(id=data.user_id, role=data.role, active=True, name=data.name))
    session.flush()


def target_user(session: Session, user_id: str) -> Actor:
    user = session.get(Actor, user_id)
    if user is None:
        raise SyncError("USER_MISSING")
    return user


def move_stock(session: Session, event: Envelope, data: StockMoved) -> None:
    sign_ok = {
        "RECEPTION": data.quantity > 0,
        "LOSS": data.quantity < 0,
        "ADJUSTMENT": data.quantity != 0,
    }[data.kind]
    if not sign_ok:
        raise SyncError("QUANTITY_SIGN_MISMATCH")
    variant = session.get(Variant, str(data.variant_id))
    if variant is None:
        raise SyncError("VARIANT_MISSING")
    if data.counted is not None and data.counted != variant.stock + data.quantity:
        raise SyncError("COUNT_MISMATCH")
    result = session.execute(
        update(Variant)
        .where(Variant.id == variant.id, Variant.stock + data.quantity >= 0)
        .values(stock=Variant.stock + data.quantity)
    )
    if result.rowcount != 1:
        raise SyncError("INSUFFICIENT_STOCK")
    session.add(
        Movement(
            id=str(event.id),
            variant_id=variant.id,
            kind=data.kind,
            quantity=data.quantity,
            actor_id=event.actor_id,
            reason=data.reason,
            origin_id=str(event.id),
            occurred_at=event.occurred_at.astimezone(UTC),
            counted=data.counted,
        )
    )


def update_variant(session: Session, data: VariantUpdated) -> None:
    if data.threshold is None and data.active is None:
        raise SyncError("EMPTY_UPDATE", 422)
    variant = session.get(Variant, str(data.variant_id))
    if variant is None:
        raise SyncError("VARIANT_MISSING")
    if data.threshold is not None:
        variant.threshold = data.threshold
    if data.active is not None:
        variant.active = data.active


def correct_payment(session: Session, event: Envelope, data: PaymentCorrected) -> None:
    sale = session.get(Sale, str(data.sale_id))
    if sale is None:
        raise SyncError("SALE_MISSING")
    if sale.number != data.sale_number:
        raise SyncError("SALE_IDENTITY_MISMATCH")
    if data.payment_mode == "cash":
        if (
            data.tendered is None
            or data.tendered < sale.total
            or data.change != data.tendered - sale.total
        ):
            raise SyncError("CASH_MISMATCH")
    elif data.tendered is not None or data.change != 0:
        raise SyncError("PAYMENT_MISMATCH")
    session.add(
        SaleCorrection(
            id=str(event.id),
            sale_id=sale.id,
            payment_mode=data.payment_mode,
            tendered=data.tendered,
            change=data.change,
            reason=data.reason,
            actor_id=event.actor_id,
            occurred_at=event.occurred_at.astimezone(UTC),
        )
    )


def movement(
    session: Session, event: Envelope, variant_id: str, kind: str, quantity: int, reason: str
) -> None:
    session.add(
        Movement(
            id=str(uuid4()),
            variant_id=variant_id,
            kind=kind,
            quantity=quantity,
            actor_id=event.actor_id,
            reason=reason,
            origin_id=str(event.id),
            occurred_at=event.occurred_at.astimezone(UTC),
        )
    )


def create_catalog(session: Session, event: Envelope, data: CatalogCreated) -> None:
    category = session.get(Category, str(data.category_id))
    if category and category.name != data.category:
        raise SyncError("CATEGORY_CONFLICT")
    if category is None:
        session.add(Category(id=str(data.category_id), name=data.category))
        session.flush()
    product = session.get(Product, str(data.product_id))
    if product is not None:
        # Further sizes of the same article: identity must match exactly.
        if product.category_id != str(data.category_id) or product.name != data.name:
            raise SyncError("PRODUCT_CONFLICT")
    else:
        session.add(
            Product(
                id=str(data.product_id),
                category_id=str(data.category_id),
                name=data.name,
                published=False,
            )
        )
        session.flush()
    session.add(
        Variant(
            id=str(data.variant_id),
            product_id=str(data.product_id),
            sku=data.sku,
            label=data.label,
            price=data.price,
            stock=data.initial_stock,
            active=True,
            color=data.color,
            size=data.size,
        )
    )
    session.flush()
    if data.initial_stock:
        movement(
            session, event, str(data.variant_id), "INITIAL", data.initial_stock, "Stock initial"
        )


def create_sale(session: Session, terminal: Terminal, event: Envelope, data: SaleCompleted) -> None:
    if (
        data.id != event.id
        or data.seller_id != event.actor_id
        or data.occurred_at != event.occurred_at
    ):
        raise SyncError("SALE_IDENTITY_MISMATCH")
    year = data.occurred_at.astimezone(UTC).year
    sequence = terminal.sale_sequence + 1
    accepted_numbers = {
        f"FACT-{year}-{sequence:05d}",
        # Recette 0.1/0.2 terminals numbered sales with their prefix; their
        # unsynchronized outbox must still be accepted unchanged.
        f"{terminal.prefix}-{year}-{sequence:06d}",
    }
    if data.number not in accepted_numbers:
        raise SyncError("SALE_NUMBER_MISMATCH")
    if len({line.variant_id for line in data.lines}) != len(data.lines):
        raise SyncError("DUPLICATE_LINE")
    total = 0
    for line in data.lines:
        variant = session.get(Variant, str(line.variant_id))
        if variant is None or not variant.active:
            raise SyncError("VARIANT_MISSING")
        product = session.get(Product, variant.product_id)
        category = session.get(Category, product.category_id)
        if (line.sku, line.label, line.unit_price, line.name, line.category) != (
            variant.sku,
            variant.label,
            variant.price,
            product.name,
            category.name,
        ):
            raise SyncError("SALE_SNAPSHOT_MISMATCH")
        if line.line_total != line.quantity * line.unit_price:
            raise SyncError("LINE_TOTAL_MISMATCH")
        total += line.line_total
        result = session.execute(
            update(Variant)
            .where(Variant.id == variant.id, Variant.stock >= line.quantity)
            .values(stock=Variant.stock - line.quantity)
        )
        if result.rowcount != 1:
            raise SyncError("INSUFFICIENT_STOCK")
        movement(session, event, variant.id, "SALE", -line.quantity, f"Vente {data.number}")
    if data.total != total or data.collected != total:
        raise SyncError("TOTAL_MISMATCH")
    if data.payment_mode == "cash":
        if data.tendered is None or data.tendered < total or data.change != data.tendered - total:
            raise SyncError("CASH_MISMATCH")
    elif data.tendered is not None or data.change != 0:
        raise SyncError("PAYMENT_MISMATCH")
    session.add(
        Sale(
            id=str(data.id),
            number=data.number,
            occurred_at=data.occurred_at.astimezone(UTC),
            total=data.total,
            snapshot=data.model_dump(mode="json"),
        )
    )
    terminal.sale_sequence += 1
