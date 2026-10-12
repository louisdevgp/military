"""Server-side report figures for [start, end), mirroring the terminal's report."""

from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from mono.models import CashClosing, Expense, Sale, SaleCorrection, SaleReturn
from mono.schemas import ReportSummary


def summary(session: Session, start: datetime, end: datetime) -> ReportSummary:
    sales = session.scalars(
        select(Sale).where(Sale.occurred_at >= start, Sale.occurred_at < end)
    ).all()
    modes: dict[str, str] = {}
    if sales:
        corrections = session.scalars(
            select(SaleCorrection)
            .where(SaleCorrection.sale_id.in_([s.id for s in sales]))
            .order_by(SaleCorrection.occurred_at)
        ).all()
        for correction in corrections:  # latest correction wins
            modes[correction.sale_id] = correction.payment_mode
    payments: dict[str, int] = {}
    for sale in sales:
        mode = modes.get(sale.id, sale.snapshot["payment_mode"])
        payments[mode] = payments.get(mode, 0) + sale.total
    gross = sum(s.total for s in sales)
    refunds = session.scalar(
        select(func.coalesce(func.sum(SaleReturn.refund_total), 0)).where(
            SaleReturn.occurred_at >= start, SaleReturn.occurred_at < end
        )
    )
    expenses = dict(
        session.execute(
            select(Expense.kind, func.sum(Expense.amount))
            .where(
                Expense.occurred_at >= start,
                Expense.occurred_at < end,
                Expense.cancelled_at.is_(None),
            )
            .group_by(Expense.kind)
        ).all()
    )
    closings = session.scalars(
        select(CashClosing).where(CashClosing.closed_at >= start, CashClosing.closed_at < end)
    ).all()
    return ReportSummary(
        sale_count=len(sales),
        gross=gross,
        refunds=int(refunds),
        net=gross - int(refunds),
        payments=payments,
        expenses_by_kind={k: int(v) for k, v in expenses.items()},
        closings=len(closings),
        closing_gap=sum(c.difference for c in closings),
    )
