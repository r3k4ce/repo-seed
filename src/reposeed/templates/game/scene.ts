import Phaser from "phaser";

export class GameScene extends Phaser.Scene {
  constructor() {
    super("game");
  }

  create() {
    const { width, height } = this.scale;

    this.add
      .text(width / 2, height / 2, "__PROJECT_NAME__", {
        color: "#f8fafc",
        fontFamily: "Arial, sans-serif",
        fontSize: "32px",
      })
      .setOrigin(0.5);
  }
}
