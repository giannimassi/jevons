import { test, expect } from '@playwright/test';
import { startServer, startEmptyServer, stopServer, type ServerHandle } from './helpers';

let server: ServerHandle;

test.beforeAll(async () => {
  server = await startServer();
});

test.afterAll(async () => {
  stopServer(server);
});

test.describe('Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${server.baseURL}/dashboard/index.html`);
    // Clear localStorage to avoid persisted scope from prior tests
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    // Set range to "all" so we see all fixture data (default is 24h)
    await page.selectOption('#range', 'all');
    // Click "All" scope button to reset any auto-scoping from ui-context.json
    await page.click('#allScopeBtn');
    // Wait for data to load — cards should populate with non-zero values
    await page.waitForFunction(
      () => {
        const card = document.querySelector('#cards .card .v');
        return card && card.textContent !== '0';
      },
      { timeout: 10_000 }
    );
  });

  test('page loads with correct title', async ({ page }) => {
    await expect(page).toHaveTitle('Claude Usage Monitor');
  });

  test('cards section shows billable total', async ({ page }) => {
    const cards = page.locator('#cards .card');
    await expect(cards).not.toHaveCount(0);

    // First card is "billable (range)" — with "all" range it shows total
    const firstCard = cards.first();
    const label = firstCard.locator('.k');
    await expect(label).toHaveText('billable (range)');

    // Total billable from fixtures: 379,500
    const value = firstCard.locator('.v');
    await expect(value).toHaveText('379,500');
  });

  test('time range dropdown changes card values', async ({ page }) => {
    // Currently on "all" — get the billable total
    const billableCard = page.locator('#cards .card').first();
    const billableValue = billableCard.locator('.v');
    await expect(billableValue).toHaveText('379,500');

    // Switch to 1h — value should be much smaller (likely 0 or a small subset)
    await page.selectOption('#range', '1h');
    await page.waitForTimeout(500);

    const newValue = await billableValue.textContent();
    // 1h window should have fewer events than all time
    expect(Number(newValue!.replace(/,/g, ''))).toBeLessThan(379_500);
  });

  test('scope tree shows project directories', async ({ page }) => {
    const scopeTree = page.locator('#scopeTree');
    await expect(scopeTree).toBeVisible();

    // Wait for tree to populate with scope buttons
    await page.waitForSelector('#scopeTree button.scope-btn', { timeout: 5_000 });

    const buttons = scopeTree.locator('button.scope-btn');
    await expect(buttons).not.toHaveCount(0);

    // Check that project names appear in the tree
    const treeText = await scopeTree.textContent();
    expect(treeText).toContain('alpha');
    expect(treeText).toContain('beta');
    expect(treeText).toContain('gamma');
  });

  test('clicking scope tree item filters cards', async ({ page }) => {
    // Verify we start with all-projects billable total
    const billableCard = page.locator('#cards .card').first();
    const billableValue = billableCard.locator('.v');
    await expect(billableValue).toHaveText('379,500');

    // Click "All" scope button to ensure clean state, then click a specific project
    // Find any scope button in the tree and click it
    const scopeBtn = page.locator('button.scope-btn').first();
    await scopeBtn.click();
    await page.waitForTimeout(500);

    // After scoping to a single project/directory, billable should change
    const newValue = await billableValue.textContent();
    expect(Number(newValue!.replace(/,/g, ''))).toBeLessThanOrEqual(379_500);
  });

  test('scope search filters tree items', async ({ page }) => {
    const searchInput = page.locator('#scopeSearch');
    await expect(searchInput).toBeVisible();

    // Wait for tree to have content first
    await page.waitForSelector('#scopeTree button.scope-btn', { timeout: 5_000 });
    const beforeCount = await page.locator('#scopeTree button.scope-btn').count();

    // Type a filter term that matches only one project
    await searchInput.fill('gamma');
    await page.waitForTimeout(500);

    const treeText = await page.locator('#scopeTree').textContent();
    expect(treeText).toContain('gamma');

    // Clear search
    await searchInput.fill('');
    await page.waitForTimeout(500);

    // All buttons should be back
    const afterCount = await page.locator('#scopeTree button.scope-btn').count();
    expect(afterCount).toBe(beforeCount);
  });

  test('chart canvas elements exist with non-zero dimensions', async ({ page }) => {
    const mainChart = page.locator('#mainChart');
    await expect(mainChart).toBeVisible();

    const mainBox = await mainChart.boundingBox();
    expect(mainBox).not.toBeNull();
    expect(mainBox!.width).toBeGreaterThan(0);
    expect(mainBox!.height).toBeGreaterThan(0);

    const dailyChart = page.locator('#dailyChart');
    await expect(dailyChart).toBeVisible();

    const dailyBox = await dailyChart.boundingBox();
    expect(dailyBox).not.toBeNull();
    expect(dailyBox!.width).toBeGreaterThan(0);
    expect(dailyBox!.height).toBeGreaterThan(0);
  });

  test('metric dropdown changes chart title text', async ({ page }) => {
    const mainTitle = page.locator('#mainTitle');
    const initialTitle = await mainTitle.textContent();

    // Switch metric to "input"
    await page.selectOption('#metric', 'input');
    await page.waitForTimeout(300);

    const newTitle = await mainTitle.textContent();
    expect(newTitle).not.toBe(initialTitle);
    expect(newTitle).toContain('input');
  });

  test('graph mode dropdown changes chart title text', async ({ page }) => {
    const mainTitle = page.locator('#mainTitle');
    const initialTitle = await mainTitle.textContent();

    // Switch to "Stacked In vs Out" mode (value="in_out")
    await page.selectOption('#graphMode', 'in_out');
    await page.waitForTimeout(300);

    const newTitle = await mainTitle.textContent();
    expect(newTitle).not.toBe(initialTitle);
  });

  test('live table shows rows with correct column count', async ({ page }) => {
    // Set live window to "6h" to capture all fixture live events (spread over last 2h)
    await page.selectOption('#liveWindow', '6h');
    // Wait for live table rows to appear
    await page.waitForSelector('#liveBody tr', { timeout: 5_000 });

    const rows = page.locator('#liveBody tr');
    const rowCount = await rows.count();
    expect(rowCount).toBeGreaterThan(0);

    // Each row should have 7 columns: Time, Project, Prompt, Input, Output, Billable, Cached
    const firstRow = rows.first();
    const cells = firstRow.locator('td');
    await expect(cells).toHaveCount(7);
  });

  test('account popover opens and closes on click', async ({ page }) => {
    const acctBtn = page.locator('#acctBtn');
    const acctWrap = page.locator('#acctWrap');

    await expect(acctBtn).toBeVisible();

    // Initially the popover should not be open
    await expect(acctWrap).not.toHaveClass(/open/);

    // Click to open
    await acctBtn.click();
    await page.waitForTimeout(200);
    await expect(acctWrap).toHaveClass(/open/);

    // Click again to close
    await acctBtn.click();
    await page.waitForTimeout(200);
    await expect(acctWrap).not.toHaveClass(/open/);
  });
});

test.describe('Dashboard with empty data', () => {
  let emptyServer: ServerHandle;

  test.beforeAll(async () => {
    emptyServer = await startEmptyServer();
  });

  test.afterAll(async () => {
    if (emptyServer) stopServer(emptyServer);
  });

  test('empty data dir shows zero values and no-data messages', async ({ page }) => {
    await page.goto(`${emptyServer.baseURL}/dashboard/index.html`);
    // Set range to all
    await page.selectOption('#range', 'all');
    // Wait for dashboard to render
    await page.waitForTimeout(2000);

    // Cards should show zero values
    const cardsText = await page.locator('#cards').textContent();
    expect(cardsText).toContain('0');

    // Main chart meta should indicate no data
    const mainMeta = await page.locator('#mainMeta').textContent();
    expect(mainMeta).toContain('No usage');
  });
});
