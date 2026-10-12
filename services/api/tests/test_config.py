from mono.config import Settings


def test_hosted_postgres_uris_use_psycopg_driver():
    for given in (
        "postgres://u:p@h:5432/db?sslmode=require",
        "postgresql://u:p@h:5432/db?sslmode=require",
    ):
        url = Settings(database_url=given).database_url
        assert url == "postgresql+psycopg://u:p@h:5432/db?sslmode=require"
    explicit = "postgresql+psycopg://u:p@h/db"
    assert Settings(database_url=explicit).database_url == explicit
    assert Settings(database_url="sqlite:///x.db").database_url == "sqlite:///x.db"


def test_unencoded_password_rejected_without_echo():
    import pytest
    from pydantic import ValidationError

    bad = "postgresql://postgres.ref:Secret2024@#@aws-1.pooler.supabase.com:5432/postgres"
    with pytest.raises(ValidationError) as error:
        Settings(database_url=bad)
    assert "Secret2024" not in str(error.value)
    assert "mal formée" in str(error.value)
    ok = "postgresql://postgres.ref:Secret2024%40%23@aws-1.pooler.supabase.com:5432/postgres"
    assert Settings(database_url=ok).database_url.startswith("postgresql+psycopg://")
