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

# ch9.4 테스트용 가짜 시크릿 [run-28]
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYzzzRUN28KEY"
AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7RUN28ZZ"
