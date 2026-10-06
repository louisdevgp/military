"""Provisionnement explicite d'un terminal de recette, jamais à partir du premier envoi."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from mono.config import Settings
from mono.database import open_engine
from mono.models import Actor, Terminal


def main() -> None:
    config = Settings()
    if not config.recette_mode:
        raise SystemExit("Provisionnement limité à la recette.")
    terminal_id = str(UUID(config.terminal_id))
    with Session(open_engine(config.database_url)) as session, session.begin():
        current = session.scalar(select(Terminal))
        if current and current.id != terminal_id:
            raise SystemExit("Un terminal existe déjà. Réconciliation requise avant remplacement.")
        if current is None:
            prefix = f"T{terminal_id.replace('-', '')[:8].upper()}"
            session.add(Terminal(slot=1, id=terminal_id, prefix=prefix))
        if session.get(Actor, "recette-admin") is None:
            session.add(Actor(id="recette-admin", role="admin", active=True))
    print("Terminal de recette provisionné. Aucun mot de passe utilisateur créé.")


if __name__ == "__main__":
    main()
