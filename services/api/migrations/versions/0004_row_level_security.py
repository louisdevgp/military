"""Deny hosted REST access (e.g. Supabase Data API) to every table.

Row level security without policies blocks other roles; the API connects as
the tables' owner, which RLS does not restrict. PostgreSQL only; no data change.
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None

TABLES = (
    "alembic_version",
    "actors",
    "categories",
    "events",
    "products",
    "sale_corrections",
    "sales",
    "stock_movements",
    "terminals",
    "variants",
)


def upgrade():
    if op.get_bind().dialect.name != "postgresql":
        return
    for table in TABLES:
        op.execute(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY')


def downgrade():
    raise RuntimeError("Security downgrade blocked; restore an approved backup.")
