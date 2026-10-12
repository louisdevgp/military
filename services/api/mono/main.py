import secrets
from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import AwareDatetime
from sqlalchemy import Engine, select, text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from mono.config import Settings
from mono.database import open_engine
from mono.models import Category, Product, Variant
from mono.reports import summary
from mono.schemas import (
    Acknowledgement,
    Envelope,
    PublicCatalog,
    PublicProduct,
    PublicVariant,
    ReportSummary,
)
from mono.sync import SyncError, apply_event


def create_app(settings: Settings | None = None, engine: Engine | None = None) -> FastAPI:
    config = settings or Settings()
    database = engine or open_engine(config.database_url)
    app = FastAPI(
        title="UNIVERS DU MONO — API de recette",
        version="0.1.0",
        docs_url="/docs" if config.recette_mode else None,
        redoc_url=None,
        openapi_url="/openapi.json" if config.recette_mode else None,
    )
    app.state.engine = database

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request, _error):
        # FastAPI's default detail includes input values, possibly client data.
        return JSONResponse(status_code=422, content={"detail": "INVALID_REQUEST"})

    @app.middleware("http")
    async def size_limit(request, call_next):
        # Cap streamed requests as well as Content-Length. Do not log bodies.
        if request.method in {"POST", "PUT", "PATCH"}:
            size = 0
            chunks = []
            async for chunk in request.stream():
                size += len(chunk)
                if size > 262144:
                    return JSONResponse(status_code=413, content={"detail": "REQUEST_TOO_LARGE"})
                chunks.append(chunk)
            request._body = b"".join(chunks)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    def authorize(authorization: Annotated[str | None, Header()] = None) -> None:
        if not config.recette_mode:
            raise HTTPException(503, "RECETTE_DISABLED")
        expected = config.sync_token.get_secret_value()
        expiry = config.token_expires_at
        if len(expected) < 32 or expiry is None or expiry.tzinfo is None:
            raise HTTPException(503, "AUTH_NOT_CONFIGURED")
        if datetime.now(UTC) >= expiry:
            raise HTTPException(401, "TOKEN_EXPIRED")
        if not secrets.compare_digest(authorization or "", f"Bearer {expected}"):
            raise HTTPException(401, "UNAUTHORIZED", headers={"WWW-Authenticate": "Bearer"})

    @app.get("/health/live")
    def live() -> dict[str, str]:
        return {"status": "ok", "mode": "recette" if config.recette_mode else "disabled"}

    @app.get("/health/ready")
    def ready() -> dict[str, str]:
        try:
            with database.connect() as connection:
                connection.execute(text("SELECT version_num FROM alembic_version"))
        except SQLAlchemyError as exc:
            raise HTTPException(503, "DATABASE_NOT_READY") from exc
        return {"status": "ok"}

    @app.post(
        "/api/private/sync/events",
        response_model=Acknowledgement,
        dependencies=[Depends(authorize)],
    )
    def synchronize(event: Envelope) -> Acknowledgement:
        if str(event.terminal_id) != config.terminal_id:
            raise HTTPException(403, "TERMINAL_NOT_AUTHORIZED")
        try:
            with Session(database) as session, session.begin():
                result = apply_event(session, event)
            # This line is reached only after Session.begin has committed.
            return result
        except SyncError as exc:
            raise HTTPException(exc.status, exc.code) from exc
        except IntegrityError as exc:
            raise HTTPException(409, "DATABASE_CONFLICT") from exc
        except SQLAlchemyError as exc:
            raise HTTPException(503, "TRANSACTION_NOT_CONFIRMED") from exc

    @app.get(
        "/api/private/reports/summary",
        response_model=ReportSummary,
        dependencies=[Depends(authorize)],
    )
    def report_summary(start: AwareDatetime, end: AwareDatetime) -> ReportSummary:
        if end <= start:
            raise HTTPException(422, "INVALID_PERIOD")
        with Session(database) as session:
            return summary(session, start.astimezone(UTC), end.astimezone(UTC))

    @app.get("/api/public/catalog", response_model=PublicCatalog)
    def catalog(
        offset: Annotated[int, Query(ge=0)] = 0, limit: Annotated[int, Query(ge=1, le=100)] = 20
    ) -> PublicCatalog:
        with Session(database) as session:
            products = session.scalars(
                select(Product)
                .where(Product.published.is_(True))
                .order_by(Product.id)
                .offset(offset)
                .limit(limit)
            ).all()
            result = []
            for product in products:
                variants = session.scalars(
                    select(Variant)
                    .where(Variant.product_id == product.id, Variant.active.is_(True))
                    .order_by(Variant.sku)
                ).all()
                result.append(
                    PublicProduct(
                        id=product.id,
                        name=product.name,
                        category=session.get(Category, product.category_id).name,
                        variants=[PublicVariant(sku=v.sku, label=v.label) for v in variants],
                    )
                )
            return PublicCatalog(items=result, offset=offset, limit=limit)

    return app


app = create_app()
