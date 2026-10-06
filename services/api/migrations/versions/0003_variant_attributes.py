"""Variant colour and size attributes. Additive only."""

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("variants", sa.Column("color", sa.String(length=40), nullable=True))
    op.add_column("variants", sa.Column("size", sa.String(length=20), nullable=True))


def downgrade():
    raise RuntimeError("Destructive downgrade blocked; restore an approved backup.")
