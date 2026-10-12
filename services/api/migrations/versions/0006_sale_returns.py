"""Returns and cancellations linked to sales. Additive only."""

import sqlalchemy as sa
from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "sale_returns",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("sale_id", sa.String(length=36), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("refund_total", sa.BigInteger(), nullable=False),
        sa.Column("refund_mode", sa.String(length=16), nullable=False),
        sa.Column("reason", sa.String(length=200), nullable=False),
        sa.Column("actor_id", sa.String(length=120), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("kind IN ('RETURN','CANCEL')", name="valid_return_kind"),
        sa.CheckConstraint("refund_total >= 0", name="nonnegative_refund"),
        sa.ForeignKeyConstraint(["actor_id"], ["actors.id"]),
        sa.ForeignKeyConstraint(["sale_id"], ["sales.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_sale_returns_sale_id"), "sale_returns", ["sale_id"], unique=False)
    op.create_table(
        "sale_return_lines",
        sa.Column("return_id", sa.String(length=36), nullable=False),
        sa.Column("variant_id", sa.String(length=36), nullable=False),
        sa.Column("quantity", sa.BigInteger(), nullable=False),
        sa.Column("unit_price", sa.BigInteger(), nullable=False),
        sa.Column("line_total", sa.BigInteger(), nullable=False),
        sa.Column("resaleable", sa.Boolean(), nullable=False),
        sa.CheckConstraint("quantity > 0", name="positive_return_quantity"),
        sa.ForeignKeyConstraint(["return_id"], ["sale_returns.id"]),
        sa.PrimaryKeyConstraint("return_id", "variant_id"),
    )
    if op.get_bind().dialect.name == "postgresql":
        # Same protection as migration 0004 for hosted REST access.
        for table in ("sale_returns", "sale_return_lines"):
            op.execute(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY')


def downgrade():
    raise RuntimeError("Destructive downgrade blocked; restore an approved backup.")
