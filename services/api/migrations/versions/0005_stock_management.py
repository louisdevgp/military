"""Low-stock threshold and inventory counts. Additive only."""

import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "variants",
        sa.Column("threshold", sa.BigInteger(), nullable=False, server_default="0"),
    )
    op.add_column("stock_movements", sa.Column("counted", sa.BigInteger(), nullable=True))


def downgrade():
    raise RuntimeError("Destructive downgrade blocked; restore an approved backup.")
