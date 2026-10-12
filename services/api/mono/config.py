from datetime import datetime

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MONO_", env_file=".env", extra="ignore")
    database_url: str = "sqlite:///./recette.db"
    recette_mode: bool = False
    sync_token: SecretStr = SecretStr("")
    terminal_id: str = ""
    token_expires_at: datetime | None = None

    @field_validator("database_url")
    @classmethod
    def psycopg_driver(cls, url: str) -> str:
        # Hosted providers (Supabase, Render) give postgres:// or postgresql://
        # URIs; SQLAlchemy would then look for psycopg2, which is not installed.
        for prefix in ("postgres://", "postgresql://"):
            if url.startswith(prefix):
                return "postgresql+psycopg://" + url[len(prefix) :]
        return url
