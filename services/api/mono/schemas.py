from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    field_validator,
)

Money = Annotated[StrictInt, Field(ge=0, le=1_000_000_000_000)]
Quantity = Annotated[StrictInt, Field(ge=1, le=1_000_000)]
Label = Annotated[str, Field(min_length=1, max_length=120)]
OptionalText = Annotated[str, Field(max_length=120)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CatalogCreated(StrictModel):
    category_id: UUID
    category: Label
    product_id: UUID
    name: Label
    variant_id: UUID
    sku: Label
    label: Label
    price: Money
    initial_stock: Annotated[StrictInt, Field(ge=0, le=1_000_000)]
    published: Literal[False]
    # Structured attributes since terminal 0.7; absent from older events.
    color: Annotated[str, Field(min_length=1, max_length=40)] | None = None
    size: Annotated[str, Field(min_length=1, max_length=20)] | None = None


class PriceChanged(StrictModel):
    variant_id: UUID
    price: Money


PaymentMode = Literal["cash", "mobileMoney", "transfer", "other"]


class UserCreated(StrictModel):
    user_id: Label
    name: Annotated[str, Field(min_length=2, max_length=60)]
    role: Literal["admin", "seller"]


class UserUpdated(StrictModel):
    user_id: Label
    active: StrictBool


class UserPinReset(StrictModel):
    """Audit only: PIN material never leaves the terminal."""

    user_id: Label


class PaymentCorrected(StrictModel):
    sale_id: UUID
    sale_number: Annotated[str, Field(min_length=1, max_length=80)]
    payment_mode: PaymentMode
    tendered: Money | None
    change: Money
    reason: Annotated[str, Field(min_length=3, max_length=200)]


class ReceiptSettingsUpdated(StrictModel):
    """Audit of the receipt identity; the logo image stays on the terminal."""

    shop_name: Annotated[str, Field(min_length=1, max_length=40)]
    contacts: Annotated[str, Field(max_length=64)]
    footer: Annotated[str, Field(max_length=80)]
    logo: Literal["original", "custom", "none"]


class Customer(StrictModel):
    name: OptionalText = ""
    first_name: OptionalText = ""
    unit: OptionalText = ""
    phone: OptionalText = ""


class SaleLine(StrictModel):
    variant_id: UUID
    category: Label
    name: Label
    sku: Label
    label: Label
    quantity: Quantity
    unit_price: Money
    line_total: Money
    unit_cost: None


class SaleCompleted(StrictModel):
    id: UUID
    number: Annotated[str, Field(min_length=1, max_length=80)]
    occurred_at: AwareDatetime
    seller_id: Label
    seller: Label
    customer: Customer
    lines: Annotated[list[SaleLine], Field(min_length=1, max_length=100)]
    total: Money
    payment_mode: PaymentMode
    tendered: Money | None
    change: Money
    collected: Money


class Envelope(StrictModel):
    id: UUID
    terminal_id: UUID
    sequence: Annotated[StrictInt, Field(ge=1, le=9_000_000_000_000_000)]
    version: Literal[1]
    kind: Literal[
        "catalog.created",
        "variant.price_changed",
        "sale.completed",
        "sale.payment_corrected",
        "user.created",
        "user.updated",
        "user.pin_reset",
        "settings.receipt_updated",
    ]
    occurred_at: AwareDatetime
    actor_id: Label
    payload: dict

    @field_validator("version", mode="before")
    @classmethod
    def strict_version(cls, value: object) -> object:
        if type(value) is not int:
            raise ValueError("integer version required")
        return value


class Acknowledgement(StrictModel):
    id: UUID
    terminal_id: UUID
    sequence: int
    status: Literal["committed"] = "committed"
    received_at: AwareDatetime


class PublicVariant(StrictModel):
    sku: str
    label: str


class PublicProduct(StrictModel):
    id: UUID
    name: str
    category: str
    variants: list[PublicVariant]


class PublicCatalog(StrictModel):
    items: list[PublicProduct]
    offset: int
    limit: int
    availability_notice: str = (
        "Catalogue synchronisé. Disponibilité à confirmer auprès de la boutique."
    )
