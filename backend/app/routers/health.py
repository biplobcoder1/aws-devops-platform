"""Health endpoints.

- /api/health        -> liveness: "is the process up?" (used by the ALB target group)
- /api/health/ready  -> readiness: "can I reach the database?" (used by smoke tests)

Keeping the ALB check on liveness only means a short database blip does not
make the load balancer kill every healthy container at once.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db import get_db

router = APIRouter(prefix="/api/health", tags=["health"])


@router.get("")
def liveness():
    s = get_settings()
    return {"status": "ok", "environment": s.environment, "version": s.app_version}


@router.get("/ready")
def readiness(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ready"}
