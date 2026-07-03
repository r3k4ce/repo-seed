## Web App Profile

This is a FastAPI + React TypeScript monorepo.

* Backend: `backend/`
* Frontend: `frontend/`
* Root scripts coordinate both sides.

## Commands

```__COMMAND_FENCE__
__CHECK_COMMAND__
__FIX_COMMAND__
```

Backend commands run from `backend/` with `uv`. Frontend commands run from `frontend/` with `npm`.

Keep API behavior in the backend and browser behavior in the frontend. Do not make backend tests depend on the frontend dev server, and do not commit generated build output.
