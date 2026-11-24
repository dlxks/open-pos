import { expect, test } from '@playwright/test';

const hubPort = process.env.POS_E2E_HUB_PORT ?? '8789';

const enableFlutterAccessibility = async (page: import('@playwright/test').Page) => {
  await page.locator('flt-semantics-placeholder').evaluate((element) => {
    (element as HTMLElement).click();
  });
};

const enterText = async (
  field: import('@playwright/test').Locator,
  value: string,
) => {
  await field.click();
  await field.press('Control+A');
  await field.pressSequentially(value);
  await expect(field).toHaveValue(value);
};

test('sets up a store, manages catalog and staff, then syncs an offline sale', async ({ page }) => {
  let connectionAvailable = false;
  let hubReachable = true;
  let syncedSaleId: string | undefined;
  let syncedShiftId: string | undefined;
  let syncedAuthorization: string | undefined;
  let productAuthorization: string | undefined;
  let syncedDiscountCents = 0;
  let stockMovementSyncAvailable = false;

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/inventory/movements`, async (route) => {
    if (route.request().method() === 'POST' && !stockMovementSyncAvailable) {
      await route.abort();
      return;
    }
    await route.continue();
  });

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/products`, async (route) => {
    if (route.request().method() === 'GET' && !hubReachable) {
      await route.abort();
      return;
    }
    if (route.request().method() === 'POST') {
      productAuthorization = route.request().headers().authorization;
    }
    await route.continue();
  });

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/catalog/operations`, async (route) => {
    productAuthorization = route.request().headers().authorization;
    await route.continue();
  });

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/auth/me`, async (route) => {
    if (!hubReachable) {
      await route.abort();
      return;
    }
    productAuthorization = route.request().headers().authorization;
    await route.continue();
  });

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/auth/login`, async (route) => {
    const response = await route.fetch();
    if (response.ok()) {
      const body = await response.json();
      if (typeof body.token === 'string') {
        productAuthorization = `Bearer ${body.token}`;
      }
    }
    await route.fulfill({ response });
  });

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/shifts/current*`, async (route) => {
    if (!hubReachable) {
      await route.abort();
      return;
    }
    await route.continue();
  });

  await page.route(`http://127.0.0.1:${hubPort}/api/v1/sales`, async (route) => {
    if (route.request().method() !== 'POST') {
      syncedAuthorization = route.request().headers().authorization;
      await route.continue();
      return;
    }
    if (!connectionAvailable) {
      await route.abort();
      return;
    }
    syncedSaleId = route.request().postDataJSON().id;
    syncedShiftId = route.request().postDataJSON().shiftId;
    syncedAuthorization = route.request().headers().authorization;
    syncedDiscountCents = route.request().postDataJSON().discountCents;
    await route.continue();
  });

  await page.goto('/');
  await enableFlutterAccessibility(page);
  await expect(page.getByText('Set up your store')).toBeVisible();
  const storeName = page.getByLabel('Store name');
  const adminName = page.getByLabel('Administrator name');
  const adminEmail = page.getByLabel('Email address');
  const adminPassword = page.getByLabel('Password');
  await enterText(storeName, 'Mabini Market');
  await enterText(adminName, 'Maria Santos');
  await enterText(adminEmail, 'maria@example.test');
  await enterText(adminPassword, 'maria-password-123');
  await page.getByRole('button', { name: 'Create store' }).click();
  await expect(page.getByText('Good morning, Maria')).toBeVisible();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Product catalog' }).click();
  await page.getByRole('button', { name: 'Add product' }).click();
  await enterText(page.getByLabel('Product name'), 'E2E Special');
  await enterText(page.getByLabel('Category'), 'Specials');
  await enterText(page.getByLabel('Price'), '3.25');
  await enterText(page.getByLabel('SKU (optional)'), 'E2E-001');
  await enterText(page.getByLabel('Barcode (optional)'), '4800000000099');
  await page.getByRole('button', { name: 'Modifiers (0 groups)' }).click();
  await page.getByRole('button', { name: 'Add modifier group' }).click();
  await enterText(page.getByLabel('Group name'), 'Size');
  await enterText(page.getByLabel('Minimum'), '1');
  await enterText(page.getByLabel('Options: Name | price adjustment'), 'Regular | 0.00\nLarge | 1.00');
  await page.getByRole('button', { name: 'Save group' }).click();
  const modifierDialog = page.getByRole('alertdialog');
  await modifierDialog.getByRole('button', { name: 'Done', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Save product' })).toBeVisible();
  await page.getByRole('button', { name: 'Save product' }).click();
  await expect.poll(async () => {
    if (!productAuthorization) return false;
    const response = await page.request.get(
      `http://127.0.0.1:${hubPort}/api/v1/products`,
      { headers: { authorization: productAuthorization } },
    );
    const body = await response.json();
    return body.products.some((product: { name: string }) => product.name === 'E2E Special');
  }).toBe(true);
  await page.setViewportSize({ width: 375, height: 812 });
  await page.getByRole('button', { name: 'Categories (1)' }).click();
  const categoriesDialog = page.getByRole('alertdialog').last();
  await expect(categoriesDialog.getByText('Specials')).toBeVisible();
  await categoriesDialog.getByRole('button', { name: 'Add category' }).click();
  const newCategoryDialog = page.getByRole('alertdialog').last();
  await enterText(newCategoryDialog.getByLabel('Category name'), 'Seasonal');
  await newCategoryDialog.getByRole('button', { name: 'Add category' }).click();
  await expect(categoriesDialog.getByText('Seasonal')).toBeVisible();
  await categoriesDialog.getByRole('button', { name: 'Done', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.getByRole('button', { name: 'Done' }).click();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Inventory and stock' }).click();
  const inventoryDialog = page.getByRole('dialog');
  const inventoryItem = inventoryDialog.getByRole('group', { name: /E2E Special/ });
  await expect(inventoryItem).toBeVisible();
  await inventoryItem.getByRole('button', { name: 'Receive' }).click();
  const receiveDialog = page.getByRole('alertdialog');
  await enterText(receiveDialog.getByLabel('Quantity received'), '4');
  await receiveDialog.getByRole('button', { name: 'Save movement' }).click();
  await expect(inventoryItem).toHaveAttribute('aria-label', /4 on hand/);
  await inventoryDialog.getByRole('tab', { name: 'Offline queue' }).click();
  await expect(inventoryDialog.getByText(/receive.*4/)).toBeVisible();
  stockMovementSyncAvailable = true;
  await inventoryDialog.getByRole('button', { name: 'Refresh inventory' }).click();
  await expect(inventoryDialog.getByRole('tabpanel', { name: 'No offline stock changes are waiting.' })).toBeVisible();
  await inventoryDialog.getByRole('tab', { name: 'Stock levels' }).click();
  await inventoryItem.getByRole('button', { name: 'Set low-stock threshold' }).click();
  const thresholdDialog = page.getByRole('alertdialog');
  await enterText(thresholdDialog.getByLabel('Alert when stock is at or below'), '5');
  await thresholdDialog.getByRole('button', { name: 'Save' }).click();
  await expect(inventoryItem).toHaveAttribute('aria-label', /Low stock/);
  await inventoryDialog.getByRole('button', { name: 'Close' }).click();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Tax settings' }).click();
  const taxDialog = page.getByRole('alertdialog');
  await enterText(taxDialog.getByLabel('Tax label'), 'VAT');
  await enterText(taxDialog.getByLabel('Tax rate'), '10');
  await taxDialog.getByRole('button', { name: 'Save tax' }).click();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Team accounts' }).click();
  await page.getByRole('button', { name: 'Add staff' }).click();
  await enterText(page.getByLabel('Full name'), 'Taylor Cashier');
  await enterText(page.getByLabel('Email address'), 'taylor@example.test');
  await enterText(page.getByLabel('Temporary password'), 'taylor-password-123');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByText('Taylor Cashier')).toBeVisible();
  await page.getByRole('button', { name: 'Done' }).click();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await enterText(page.getByLabel('Email address'), 'taylor@example.test');
  await enterText(page.getByLabel('Password'), 'taylor-password-123');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText('Good morning, Taylor')).toBeVisible();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: /Cash drawer.*Closed/ }).click();
  const drawerDialog = page.getByRole('alertdialog');
  await enterText(drawerDialog.getByLabel('Opening float'), '100.00');
  await drawerDialog.getByRole('button', { name: 'Open cash drawer' }).click();
  await expect(drawerDialog.getByText('Shift is open')).toBeVisible();
  await drawerDialog.getByRole('button', { name: 'Close', exact: true }).click();

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await expect(page.getByText('Product catalog')).toHaveCount(0);
  await expect(page.getByText('Team accounts')).toHaveCount(0);
  await page.getByRole('menuitem', { name: /Cash drawer.*Open/ }).click();
  const verifyDrawerDialog = page.getByRole('alertdialog');
  await expect(verifyDrawerDialog.getByText('Shift is open')).toBeVisible();
  await verifyDrawerDialog.getByRole('button', { name: 'Close', exact: true }).click();

  await page.getByRole('button', { name: /E2E Special/ }).click();
  const largeOption = page.getByRole('checkbox', { name: /Large/ });
  await largeOption.focus();
  await largeOption.press('Space');
  await expect(largeOption).toHaveAttribute('aria-checked', 'true');
  await page.getByRole('button', { name: 'Add to sale' }).click();
  await page.getByRole('button', { name: 'Complete cash sale' }).click();
  await expect(page.getByText('Sale complete')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Print receipt' })).toBeVisible();
  await page.getByRole('button', { name: 'Done' }).click();
  await expect(page.getByRole('button', { name: '2 waiting to sync' })).toBeVisible();

  hubReachable = false;
  await page.reload();
  await enableFlutterAccessibility(page);
  await expect(page.getByText('Good morning, Taylor')).toBeVisible();
  await expect(page.getByRole('button', { name: '2 waiting to sync' })).toBeVisible();
  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await expect(page.getByRole('menuitem', { name: /Cash drawer.*Open/ })).toBeVisible();
  await page.getByRole('menuitem', { name: /Cash drawer.*Open/ }).click();
  const offlineDrawerDialog = page.getByRole('alertdialog');
  await expect(offlineDrawerDialog.getByText('Shift is open')).toBeVisible();
  await offlineDrawerDialog.getByRole('button', { name: 'Close', exact: true }).click();

  hubReachable = true;
  connectionAvailable = true;
  await page.getByRole('button', { name: '2 waiting to sync' }).click();
  await expect(page.getByText('Ready to sync')).toBeVisible();
  await expect.poll(async () => {
    if (!syncedSaleId) return 0;
    const response = await page.request.get(
      `http://127.0.0.1:${hubPort}/api/v1/sales/${syncedSaleId}`,
      { headers: { authorization: syncedAuthorization ?? '' } },
    );
    return response.status();
  }).toBe(200);
  expect(syncedShiftId).toBeTruthy();
  const shiftResponse = await page.request.get(
    `http://127.0.0.1:${hubPort}/api/v1/shifts/${syncedShiftId}`,
    { headers: { authorization: syncedAuthorization ?? '' } },
  );
  expect(shiftResponse.status()).toBe(200);
  expect((await shiftResponse.json()).shift.expectedCashCents).toBe(10468);
  const paymentResponse = await page.request.get(
    `http://127.0.0.1:${hubPort}/api/v1/sales/${syncedSaleId}/payment`,
    { headers: { authorization: syncedAuthorization ?? '' } },
  );
  expect(paymentResponse.status()).toBe(200);
  expect((await paymentResponse.json()).status).toBe('captured');

  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await enterText(page.getByLabel('Email address'), 'maria@example.test');
  await enterText(page.getByLabel('Password'), 'maria-password-123');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByText('Good morning, Maria')).toBeVisible();
  await page.setViewportSize({ width: 375, height: 812 });
  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Sales and returns' }).click();
  const salesDialog = page.getByRole('dialog');
  await salesDialog.getByText(syncedSaleId!).click();
  await salesDialog.getByRole('button', { name: 'Return items' }).click();
  const returnDialog = page.getByRole('alertdialog');
  await enterText(returnDialog.getByLabel('Qty'), '1');
  await enterText(returnDialog.getByLabel('Return reason'), 'Customer refund');
  await returnDialog.getByRole('button', { name: 'Save return' }).click();
  await expect(salesDialog.getByText(/1 RETURN/)).toBeVisible();
  await salesDialog.getByRole('button', { name: 'Reports' }).click();
  await expect(salesDialog.getByText('Sales report')).toBeVisible();
  await expect(salesDialog.getByText(/\(UTC\)/)).toBeVisible();
  await expect(salesDialog.getByText('PHP 4.68').first()).toBeVisible();
  const reconciledAfterRefund = await page.request.get(
    `http://127.0.0.1:${hubPort}/api/v1/shifts/${syncedShiftId}`,
    { headers: { authorization: syncedAuthorization ?? '' } },
  );
  expect((await reconciledAfterRefund.json()).shift.expectedCashCents).toBe(10000);

  await salesDialog.getByRole('button', { name: 'Close' }).click();
  await page.getByRole('button', { name: 'Account and store settings' }).click();
  await page.getByRole('menuitem', { name: 'Suppliers and purchasing' }).click();
  const purchasingDialog = page.getByRole('dialog');
  await expect(
    purchasingDialog.getByRole('tabpanel', { name: /No suppliers yet/ }),
  ).toBeVisible();
  await purchasingDialog.getByRole('button', { name: 'Add supplier' }).click();
  const supplierDialog = page.getByRole('alertdialog').last();
  const supplierBounds = await supplierDialog.boundingBox();
  expect(supplierBounds).not.toBeNull();
  expect(supplierBounds!.x).toBeGreaterThanOrEqual(0);
  expect(supplierBounds!.x + supplierBounds!.width).toBeLessThanOrEqual(375);
  await enterText(supplierDialog.getByLabel('Supplier name'), 'Coastline Wholesale');
  await supplierDialog.getByRole('button', { name: 'Save supplier' }).click();
  await expect(
    purchasingDialog.getByRole('group', { name: /Coastline Wholesale/ }),
  ).toBeVisible();
  await purchasingDialog.getByRole('tab', { name: 'Purchase orders' }).click();
  await purchasingDialog.getByRole('button', { name: 'New order' }).click();
  const orderDialog = page.getByRole('alertdialog').last();
  const orderBounds = await orderDialog.boundingBox();
  expect(orderBounds).not.toBeNull();
  expect(orderBounds!.x + orderBounds!.width).toBeLessThanOrEqual(375);
  await enterText(orderDialog.getByLabel('Quantity'), '3');
  await enterText(orderDialog.getByLabel('Unit cost (PHP)'), '0.50');
  await orderDialog.getByRole('button', { name: 'Save draft' }).click();
  await expect(purchasingDialog.getByText('No purchase orders')).toHaveCount(0);
  await purchasingDialog.getByRole('button', { name: /Coastline Wholesale Draft/ }).click();
  await purchasingDialog.getByRole('button', { name: 'Place order' }).click();
  await purchasingDialog.getByRole('button', { name: 'Receive items' }).click();
  const receiptDialog = page.getByRole('alertdialog').last();
  const receiptBounds = await receiptDialog.boundingBox();
  expect(receiptBounds).not.toBeNull();
  expect(receiptBounds!.x + receiptBounds!.width).toBeLessThanOrEqual(375);
  await enterText(receiptDialog.getByLabel('Received'), '2');
  await enterText(receiptDialog.getByLabel('Stock location'), 'Back room');
  await receiptDialog.getByRole('button', { name: 'Receive items' }).click();
  await expect(purchasingDialog.getByText('Partial')).toBeVisible();
  const receivedInventory = await page.request.get(
    `http://127.0.0.1:${hubPort}/api/v1/inventory`,
    { headers: { authorization: productAuthorization ?? '' } },
  );
  expect(receivedInventory.status()).toBe(200);
  const receivedItem = (await receivedInventory.json()).items.find(
    (item: { name: string }) => item.name === 'E2E Special',
  );
  expect(receivedItem).toBeDefined();
  expect(receivedItem!.locations).toContainEqual({ location: 'Back room', quantity: 2 });
  await purchasingDialog.getByRole('button', { name: 'Close' }).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.getByRole('button', { name: /E2E Special/ }).click();
  const discountedLargeOption = page.getByRole('checkbox', { name: /Large/ });
  await discountedLargeOption.focus();
  await discountedLargeOption.press('Space');
  await expect(discountedLargeOption).toHaveAttribute('aria-checked', 'true');
  await page.getByRole('button', { name: 'Add to sale' }).click();
  await page.getByRole('button', { name: 'Discount' }).click();
  const discountDialog = page.getByRole('alertdialog');
  await enterText(discountDialog.getByLabel('Amount'), '0.25');
  await enterText(discountDialog.getByLabel('Reason'), 'Promotion');
  await discountDialog.getByRole('button', { name: 'Apply discount' }).click();
  await expect(page.getByText('VAT (10.00%)')).toBeVisible();
  await expect(page.getByText('PHP 4.40')).toBeVisible();
  await page.getByRole('button', { name: 'Complete cash sale' }).click();
  await expect(page.getByText('Sale complete')).toBeVisible();
  expect(syncedDiscountCents).toBe(25);
  await page.getByRole('button', { name: 'Done' }).click();
});
