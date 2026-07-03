## Game Profile

This is a FastAPI + Phaser web game monorepo.

* Backend: `backend/`
* Frontend: `frontend/`
* Game scene code: `frontend/src/game/`
* Root scripts coordinate both sides.

## Commands

```__COMMAND_FENCE__
__CHECK_COMMAND__
__FIX_COMMAND__
```

Keep Phaser scene, input, and rendering code in the frontend. Keep backend code focused on API/state. Do not add persistence, auth, multiplayer, or WebSockets unless the task explicitly asks for them.
