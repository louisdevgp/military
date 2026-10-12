from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Terminal(Base):
    __tablename__ = "terminals"
    __table_args__ = (CheckConstraint("slot = 1", name="one_terminal_only"),)
    slot: Mapped[int] = mapped_column(primary_key=True, default=1)
    id: Mapped[str] = mapped_column(String(36), unique=True)
    prefix: Mapped[str] = mapped_column(String(32), unique=True)
    last_sequence: Mapped[int] = mapped_column(BigInteger, default=0)
    sale_sequence: Mapped[int] = mapped_column(BigInteger, default=0)


class Actor(Base):
    __tablename__ = "actors"
    __table_args__ = (CheckConstraint("role IN ('admin','seller')", name="valid_role"),)
    id: Mapped[str] = mapped_column(String(120), primary_key=True)
    role: Mapped[str] = mapped_column(String(16))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Display name from the terminal; no credential is ever stored server-side.
    name: Mapped[str | None] = mapped_column(String(60))


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (UniqueConstraint("terminal_id", "sequence", name="uq_terminal_sequence"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    terminal_id: Mapped[str] = mapped_column(ForeignKey("terminals.id"))
    sequence: Mapped[int] = mapped_column(BigInteger)
    fingerprint: Mapped[str] = mapped_column(String(64))
    version: Mapped[int]
    kind: Mapped[str] = mapped_column(String(40))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    actor_id: Mapped[str] = mapped_column(ForeignKey("actors.id"))
    envelope: Mapped[dict[str, Any]] = mapped_column(JSON)


class Category(Base):
    __tablename__ = "categories"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)


class Product(Base):
    __tablename__ = "products"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    category_id: Mapped[str] = mapped_column(ForeignKey("categories.id"))
    name: Mapped[str] = mapped_column(String(120))
    published: Mapped[bool] = mapped_column(Boolean, default=False, index=True)


class Variant(Base):
    __tablename__ = "variants"
    __table_args__ = (
        CheckConstraint("price >= 0", name="nonnegative_price"),
        CheckConstraint("stock >= 0", name="nonnegative_stock"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id"), index=True)
    sku: Mapped[str] = mapped_column(String(120), unique=True)
    label: Mapped[str] = mapped_column(String(120))
    price: Mapped[int] = mapped_column(BigInteger)
    stock: Mapped[int] = mapped_column(BigInteger)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    color: Mapped[str | None] = mapped_column(String(40))
    size: Mapped[str | None] = mapped_column(String(20))
    threshold: Mapped[int] = mapped_column(BigInteger, default=0, server_default="0")


class Sale(Base):
    __tablename__ = "sales"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    number: Mapped[str] = mapped_column(String(80), unique=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    total: Mapped[int] = mapped_column(BigInteger)
    snapshot: Mapped[dict[str, Any]] = mapped_column(JSON)


class Movement(Base):
    __tablename__ = "stock_movements"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    variant_id: Mapped[str] = mapped_column(ForeignKey("variants.id"), index=True)
    kind: Mapped[str] = mapped_column(String(16))
    quantity: Mapped[int] = mapped_column(BigInteger)
    actor_id: Mapped[str] = mapped_column(ForeignKey("actors.id"))
    reason: Mapped[str] = mapped_column(String(200))
    origin_id: Mapped[str] = mapped_column(String(36), index=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    counted: Mapped[int | None] = mapped_column(BigInteger)


class SaleCorrection(Base):
    """Administrator correction of a sale's declared payment; sales stay immutable."""

    __tablename__ = "sale_corrections"
    __table_args__ = (
        CheckConstraint("change >= 0", name="nonnegative_change"),
        CheckConstraint("tendered IS NULL OR tendered >= 0", name="nonnegative_tendered"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sale_id: Mapped[str] = mapped_column(ForeignKey("sales.id"), index=True)
    payment_mode: Mapped[str] = mapped_column(String(16))
    tendered: Mapped[int | None] = mapped_column(BigInteger)
    change: Mapped[int] = mapped_column(BigInteger)
    reason: Mapped[str] = mapped_column(String(200))
    actor_id: Mapped[str] = mapped_column(ForeignKey("actors.id"))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SaleReturn(Base):
    """Return or cancellation linked to an immutable sale."""

    __tablename__ = "sale_returns"
    __table_args__ = (
        CheckConstraint("kind IN ('RETURN','CANCEL')", name="valid_return_kind"),
        CheckConstraint("refund_total >= 0", name="nonnegative_refund"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sale_id: Mapped[str] = mapped_column(ForeignKey("sales.id"), index=True)
    kind: Mapped[str] = mapped_column(String(16))
    refund_total: Mapped[int] = mapped_column(BigInteger)
    refund_mode: Mapped[str] = mapped_column(String(16))
    reason: Mapped[str] = mapped_column(String(200))
    actor_id: Mapped[str] = mapped_column(ForeignKey("actors.id"))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SaleReturnLine(Base):
    __tablename__ = "sale_return_lines"
    __table_args__ = (CheckConstraint("quantity > 0", name="positive_return_quantity"),)
    return_id: Mapped[str] = mapped_column(ForeignKey("sale_returns.id"), primary_key=True)
    variant_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    quantity: Mapped[int] = mapped_column(BigInteger)
    unit_price: Mapped[int] = mapped_column(BigInteger)
    line_total: Mapped[int] = mapped_column(BigInteger)
    resaleable: Mapped[bool] = mapped_column(Boolean)
