from datetime import datetime
from urllib.parse import urlsplit

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # hide_input_in_errors: a rejected value (database URL, token) must never be
    # echoed in logs.
    model_config = SettingsConfigDict(
        env_prefix="MONO_", env_file=".env", extra="ignore", hide_input_in_errors=True
    )
    database_url: str = "sqlite:///./recette.db"
    recette_mode: bool = False
    sync_token: SecretStr = SecretStr("")
    terminal_id: str = ""
    token_expires_at: datetime | None = None
    # Signs short access tokens; at least 32 characters.
    token_secret: SecretStr = SecretStr("")
    # Lets the shop administrator request activation codes; at least 32 characters.
    admin_token: SecretStr = SecretStr("")

    @field_validator("database_url")
    @classmethod
    def psycopg_driver(cls, url: str) -> str:
        # Hosted providers (Supabase, Render) give postgres:// or postgresql://
        # URIs; SQLAlchemy would then look for psycopg2, which is not installed.
        for prefix in ("postgres://", "postgresql://"):
            if url.startswith(prefix):
                url = "postgresql+psycopg://" + url[len(prefix) :]
        if url.startswith("postgresql"):
            authority = url.split("://", 1)[1].split("/", 1)[0]
            # Unencoded @ # / : in the password split the URL wrongly and leak
            # part of it in driver errors (observed on Render).
            if authority.count("@") != 1 or "#" in authority or urlsplit(url).hostname is None:
                raise ValueError(
                    "URL de base mal formée : encoder les caractères spéciaux du mot "
                    "de passe (@ %40, # %23, / %2F, : %3A) ou utiliser lettres et chiffres."
                )
        return url
