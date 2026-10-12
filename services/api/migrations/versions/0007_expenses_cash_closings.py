"""Expenses and cash closings. Additive only."""

import sqlalchemy as sa
from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "expenses",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("category", sa.String(length=60), nullable=False),
        sa.Column("amount", sa.BigInteger(), nullable=False),
        sa.Column("payment_mode", sa.String(length=16), nullable=False),
        sa.Column("reason", sa.String(length=200), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actor_id", sa.String(length=120), nullable=False),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancel_reason", sa.String(length=200), nullable=True),
        sa.CheckConstraint("kind IN ('CHARGE','STOCK','TREASURY')", name="valid_expense_kind"),
        sa.CheckConstraint("amount > 0", name="positive_expense"),
        sa.ForeignKeyConstraint(["actor_id"], ["actors.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_expenses_occurred_at"), "expenses", ["occurred_at"], unique=False)
    op.create_table(
        "cash_closings",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("period_start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("opening_float", sa.BigInteger(), nullable=False),
        sa.Column("cash_sales", sa.BigInteger(), nullable=False),
        sa.Column("cash_refunds", sa.BigInteger(), nullable=False),
        sa.Column("cash_expenses", sa.BigInteger(), nullable=False),
        sa.Column("expected", sa.BigInteger(), nullable=False),
        sa.Column("counted", sa.BigInteger(), nullable=False),
        sa.Column("difference", sa.BigInteger(), nullable=False),
        sa.Column("kept_float", sa.BigInteger(), nullable=False),
        sa.Column("comment", sa.String(length=200), nullable=False),
        sa.Column("actor_id", sa.String(length=120), nullable=False),
        sa.CheckConstraint("counted >= 0", name="nonnegative_counted"),
        sa.CheckConstraint("kept_float >= 0 AND kept_float <= counted", name="valid_kept_float"),
        sa.ForeignKeyConstraint(["actor_id"], ["actors.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_cash_closings_closed_at"), "cash_closings", ["closed_at"], unique=False
    )
    if op.get_bind().dialect.name == "postgresql":
        for table in ("expenses", "cash_closings"):
            op.execute(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY')


def downgrade():
    raise RuntimeError("Destructive downgrade blocked; restore an approved backup.")
