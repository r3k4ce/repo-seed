import { expect, test } from "@playwright/test";

test("starts the Phaser scene and shows backend state", async ({ page }) => {
  await page.route("/api/game/state", async (route) => {
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({ status: "ready", project: "demo" }),
    });
  });

  await page.goto("/");

  await expect(page.getByRole("heading", { name: "__PROJECT_NAME__" })).toBeVisible();
  await expect(page.locator("#backend-status")).toHaveText("Backend: ready");
  await expect(page.locator("canvas")).toBeVisible();
});
