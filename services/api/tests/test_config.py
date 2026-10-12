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
