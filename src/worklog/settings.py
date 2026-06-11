from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    mongo_host: str
    mongo_initdb_root_username: str
    mongo_initdb_root_password: str
    root_path: str = ""
    logging_level: str = "INFO"
    image_tag: str = "Unknown"
    testing: bool = False
    model_config = SettingsConfigDict(env_file=".env.local", env_file_encoding="utf-8")


settings = Settings()
