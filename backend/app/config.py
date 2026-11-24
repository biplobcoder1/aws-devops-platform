"""Application settings, loaded from environment variables.

In AWS, DB_HOST / DB_NAME / DB_PORT come from the ECS task definition and
DB_USER / DB_PASSWORD are injected from AWS Secrets Manager (never baked
into the image). Locally they come from docker-compose / .env.
"""
from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "TaskFlow API"
    environment: str = "local"
    app_version: str = "dev"  # set to the git SHA by CI/CD

    # Either give a full DATABASE_URL, or the individual parts below.
    database_url: str | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "taskflow"
    db_user: str = "taskflow"
    db_password: str = "taskflow"

    log_level: str = "INFO"

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        password = quote_plus(self.db_password)
        return (
            f"postgresql+psycopg://{self.db_user}:{password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
