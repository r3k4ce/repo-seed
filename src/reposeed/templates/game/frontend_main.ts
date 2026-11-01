import Phaser from "phaser";
import { GameScene } from "./game/GameScene";
import "./style.css";

type GameState = {
  status: string;
  project: string;
};

const root = document.querySelector<HTMLDivElement>("#root");

if (!root) {
  throw new Error("Missing #root element");
}

root.innerHTML = `
  <main>
    <header>
      <h1>__PROJECT_NAME__</h1>
      <p id="backend-status">Backend: checking...</p>
    </header>
    <div id="game" class="game-shell"></div>
  </main>
`;

const status = document.querySelector<HTMLParagraphElement>("#backend-status");

fetch("/api/game/state")
  .then((response) => response.json() as Promise<GameState>)
  .then((state) => {
    if (status) {
      status.textContent = `Backend: ${state.status}`;
    }
  })
  .catch(() => {
    if (status) {
      status.textContent = "Backend: offline";
    }
  });

new Phaser.Game({
  type: Phaser.AUTO,
  parent: "game",
  width: 800,
  height: 450,
  backgroundColor: "#101827",
  scene: [GameScene],
});
