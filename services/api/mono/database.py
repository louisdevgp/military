from sqlalchemy import Engine, create_engine, event


def open_engine(url: str) -> Engine:
    engine = create_engine(url, pool_pre_ping=True, hide_parameters=True)
    if engine.dialect.name == "sqlite":

        @event.listens_for(engine, "connect")
        def sqlite_foreign_keys(connection, _record):
            connection.execute("PRAGMA foreign_keys=ON")

    return engine
