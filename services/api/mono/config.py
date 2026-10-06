from datetime import datetime

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MONO_", env_file=".env", extra="ignore")
    database_url: str = "sqlite:///./recette.db"
    recette_mode: bool = False
    sync_token: SecretStr = SecretStr("")
    terminal_id: str = ""
    token_expires_at: datetime | None = None
