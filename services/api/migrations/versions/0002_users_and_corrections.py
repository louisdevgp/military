"""Operator names and payment corrections. Additive only."""

import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("actors", sa.Column("name", sa.String(length=60), nullable=True))
    op.create_table(
        "sale_corrections",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("sale_id", sa.String(length=36), nullable=False),
        sa.Column("payment_mode", sa.String(length=16), nullable=False),
        sa.Column("tendered", sa.BigInteger(), nullable=True),
        sa.Column("change", sa.BigInteger(), nullable=False),
        sa.Column("reason", sa.String(length=200), nullable=False),
        sa.Column("actor_id", sa.String(length=120), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("change >= 0", name="nonnegative_change"),
        sa.CheckConstraint("tendered IS NULL OR tendered >= 0", name="nonnegative_tendered"),
        sa.ForeignKeyConstraint(["actor_id"], ["actors.id"]),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_sale_corrections_sale_id"), "sale_corrections", ["sale_id"], unique=False
    )


def downgrade():
    raise RuntimeError("Destructive downgrade blocked; restore an approved backup.")
