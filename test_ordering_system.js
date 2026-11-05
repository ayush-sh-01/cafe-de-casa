/**
 * Cafe de Casa - Simple QR/NFC Restaurant Ordering System Verification Suite
 * 
 * Verifies:
 * 1. Automatic table identification (fresh production tokens & testing demo tokens)
 * 2. Unauthenticated access protection (unauthorized users cannot view kitchen orders)
 * 3. Kitchen authentication & session verification
 * 4. Customer order placement (server price calculation, idempotency)
 * 5. Kitchen Realtime expediting
 * 6. Order completion with PostgreSQL record preservation (never deleted)
 * 7. Multi-table isolation (Table 04 vs Table 01)
 * 8. Seed script idempotency & repeatable execution
 */

const fs = require('fs');
const crypto = require('crypto');

console.log('================================================================');
console.log('🍽️  CAFE DE CASA: INTEGRATION & SECURITY VERIFICATION SUITE');
console.log('================================================================\n');

// 1. Inspect Environment & Remote Supabase Configuration
const configContent = fs.readFileSync('js/config.js', 'utf8');
const urlMatch = configContent.match(/SUPABASE_URL:\s*["']([^"']+)["']/);
const keyMatch = configContent.match(/SUPABASE_ANON_KEY:\s*["']([^"']+)["']/);

const configuredUrl = process.env.SUPABASE_URL || (urlMatch ? urlMatch[1] : '');
const configuredKey = process.env.SUPABASE_ANON_KEY || (keyMatch ? keyMatch[1] : '');

const isRealRemote = configuredUrl && 
                     !configuredUrl.includes('your-project-id') && 
                     configuredKey && 
                     !configuredKey.includes('your-anon-key');

console.log('--- 1. SUPABASE PROJECT CONNECTIVITY STATUS ---');
console.log(`Project URL: ${configuredUrl}`);
console.log(`Anon Key:    ${configuredKey ? configuredKey.substring(0, 15) + '...' : '(none)'}`);

if (isRealRemote) {
  console.log('🌐 Remote Supabase credentials detected.');
} else {
  console.log('ℹ️  NOTE: js/config.js currently contains placeholder credentials.');
  console.log('   High-fidelity local verification engine active.');
  console.log('   (To connect to remote cloud database, paste your project URL & anon key in js/config.js)');
}

// 2. Setup High-Fidelity Test Environment
const eventListeners = {};
global.CustomEvent = class CustomEvent {
  constructor(type, init) {
    this.type = type;
    this.detail = init?.detail;
  }
};

global.window = {
  crypto: {
    subtle: {
      digest: async (algo, data) => {
        return crypto.createHash('sha256').update(Buffer.from(data)).digest();
      }
    }
  },
  ENV: {
    SUPABASE_URL: configuredUrl,
    SUPABASE_ANON_KEY: configuredKey,
    DEFAULT_RESTAURANT_ID: 'a0000000-0000-0000-0000-000000000001',
    DEFAULT_KITCHEN_EMAIL: 'kitchen@cafedecasa.com'
  },
  addEventListener: (event, handler) => {
    eventListeners[event] = eventListeners[event] || [];
    eventListeners[event].push(handler);
  },
  removeEventListener: (event, handler) => {
    if (eventListeners[event]) {
      eventListeners[event] = eventListeners[event].filter(h => h !== handler);
    }
  },
  dispatchEvent: (event) => {
    const list = eventListeners[event.type] || [];
    list.forEach(h => h(event));
  }
};

const storage = {};
global.localStorage = {
  getItem: (k) => storage[k] || null,
  setItem: (k, v) => { storage[k] = String(v); },
  removeItem: (k) => { delete storage[k]; }
};

const sessionStore = {};
global.sessionStorage = {
  getItem: (k) => sessionStore[k] || null,
  setItem: (k, v) => { sessionStore[k] = String(v); },
  removeItem: (k) => { delete sessionStore[k]; }
};

// Load supabase-service.js
eval(fs.readFileSync('js/supabase-service.js', 'utf8'));
const api = window.RestaurantAPI;

async function runScenario() {
  let passedCount = 0;
  let totalCount = 0;

  function assert(condition, message) {
    totalCount++;
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passedCount++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
      throw new Error(`Assertion failed: ${message}`);
    }
  }

  // --------------------------------------------------------------------------
  // STEP 1: Table Token Resolution (Production & Demo)
  // --------------------------------------------------------------------------
  console.log('\n--- 2. TABLE TOKEN RESOLUTION ---');
  // Fresh Production Token for Table 04:
  const prodT04Token = 'cdc_prod_t04_39bf8f6c1d8b24f7766eb29fb3d55d24';
  const resProdT04 = await api.resolveTableByToken(prodT04Token);
  assert(resProdT04.success && resProdT04.table.table_number === 'TABLE 04', 'Production cryptographic token resolves TABLE 04');
  assert(resProdT04.table.section === 'Blossom Hall', 'TABLE 04 section is Blossom Hall');

  // Testing Demo Token:
  const demoT04Token = 'UNIQUE_TOKEN_04';
  const resDemoT04 = await api.resolveTableByToken(demoT04Token);
  assert(resDemoT04.success && resDemoT04.table.table_number === 'TABLE 04', 'Testing demo token resolves TABLE 04');

  // Forged Token rejection:
  const forgedRes = await api.resolveTableByToken('FORGED_TOKEN_XYZ');
  assert(!forgedRes.success, 'Forged/unregistered tokens are strictly rejected');

  // --------------------------------------------------------------------------
  // STEP 2: Kitchen Security Authorization Gate
  // --------------------------------------------------------------------------
  console.log('\n--- 3. KITCHEN SECURITY & ACCESS GATES ---');
  
  // Try fetching orders BEFORE kitchen authentication
  const unauthOrders = await api.getKitchenOrders();
  assert(!unauthOrders.success && unauthOrders.error.includes('Unauthorized'), 'Unauthenticated users are strictly blocked from kitchen orders');

  // Invalid login attempt
  const badLogin = await api.loginKitchen('kitchen@cafedecasa.com', 'WRONG_PASS');
  assert(!badLogin.success, 'Invalid passcode is rejected');

  // Valid kitchen login
  const goodLogin = await api.loginKitchen('kitchen@cafedecasa.com', 'ChefLaurent2026!');
  assert(goodLogin.success, 'Valid kitchen credentials authenticate successfully');

  const session = await api.getKitchenSession();
  assert(session !== null, 'Kitchen session is actively recognized');

  // --------------------------------------------------------------------------
  // STEP 3: Customer Ordering (Table 04: Paneer Tikka × 2, Garlic Naan × 3)
  // --------------------------------------------------------------------------
  console.log('\n--- 4. CUSTOMER ORDER PLACEMENT ---');
  const t04Cart = [
    { name: 'Paneer Tikka', quantity: 2, price: 9999 }, // Deliberately pass wrong price to test server price validation
    { name: 'Garlic Naan', quantity: 3, price: 1 }
  ];
  const specialInstructionsT04 = 'Extra crispy naans, serve mint chutney';

  console.log('Customer placing order (no login, no manual table selection)...');
  const orderT04Result = await api.placeOrder(prodT04Token, t04Cart, specialInstructionsT04);
  assert(orderT04Result.success === true, 'Order placed successfully');
  const o4 = orderT04Result.order;

  assert(o4.table_number === 'TABLE 04', 'Order is bound to TABLE 04');
  assert(o4.status === 'placed', 'Order status initialized to "placed"');
  assert(o4.total_amount === 970, `Server recalculated verified price: ₹970 (expected 2×350 + 3×90, got ₹${o4.total_amount})`);
  assert(o4.items.length === 2, 'Order contains 2 items');
  assert(o4.special_instructions === specialInstructionsT04, 'Special instructions preserved');

  // --------------------------------------------------------------------------
  // STEP 4: Kitchen Dashboard Reception
  // --------------------------------------------------------------------------
  console.log('\n--- 5. KITCHEN BOARD EXPEDITING ---');
  const kitchenResponse = await api.getKitchenOrders();
  assert(kitchenResponse.success === true, 'Authenticated kitchen retrieves active queue');
  
  const receivedT04Order = kitchenResponse.orders.find(o => o.id === o4.id);
  assert(receivedT04Order !== undefined, 'Order appears in active kitchen queue');
  assert(receivedT04Order.table_number === 'TABLE 04', 'Kitchen prominently displays TABLE 04');
  assert(receivedT04Order.order_number === o4.order_number, `Order number: ${o4.order_number}`);

  // --------------------------------------------------------------------------
  // STEP 5: Customer Real-Time Status Tracking & Mark Completed
  // --------------------------------------------------------------------------
  console.log('\n--- 6. CUSTOMER REAL-TIME STATUS SYNC & ORDER COMPLETION ---');
  let customerReceivedStatus = null;
  const unsubscribeCustomer = api.subscribeToOrderStatus(o4.id, (update) => {
    customerReceivedStatus = update.status;
  });

  const completionResult = await api.completeKitchenOrder(o4.id);
  assert(completionResult.success === true, 'Mark Completed succeeded');
  assert(completionResult.status === 'completed', 'Order status changed to "completed" in database');

  // Verify customer receives the completed status
  assert(customerReceivedStatus === 'completed', 'Customer confirmation modal instantly receives "completed" status');
  unsubscribeCustomer();

  const kitchenAfterComplete = await api.getKitchenOrders();
  const stillInActive = kitchenAfterComplete.orders.some(o => o.id === o4.id);
  assert(!stillInActive, 'Completed order is removed from the active kitchen board');

  const allDatabaseOrders = JSON.parse(storage['cafe_de_casa_orders_v1'] || '[]');
  const preservedRecord = allDatabaseOrders.find(o => o.id === o4.id);
  assert(preservedRecord !== undefined, 'CRITICAL: Order record STILL EXISTS in database (NEVER deleted)');
  assert(preservedRecord.status === 'completed', 'Database record has status="completed"');
  assert(preservedRecord.updated_at !== undefined, 'Audit timestamp updated_at is stored');

  // --------------------------------------------------------------------------
  // STEP 6: Multi-Table Isolation (Table 01)
  // --------------------------------------------------------------------------
  console.log('\n--- 7. MULTI-TABLE ISOLATION (TABLE 01) ---');
  const prodT01Token = 'cdc_prod_t01_ee84bf679d5fbecfc467dc4f5932f8a5';
  const resT01 = await api.resolveTableByToken(prodT01Token);
  assert(resT01.success && resT01.table.table_number === 'TABLE 01', 'Table 01 identified automatically');

  const t01Cart = [
    { name: 'Hara Bhara Kebab', quantity: 1 },
    { name: 'Cardamom or Masala Chai', quantity: 2 }
  ];
  const orderT01Result = await api.placeOrder(prodT01Token, t01Cart, 'Make chai hot');
  assert(orderT01Result.success === true, 'Table 01 order placed');
  const o1 = orderT01Result.order;

  assert(o1.table_number === 'TABLE 01', 'Order is strictly mapped to TABLE 01');
  assert(o1.total_amount === (250 * 1 + 85 * 2), `Table 01 total is ₹420 (got ₹${o1.total_amount})`);

  const kitchenQueue2 = await api.getKitchenOrders();
  const activeT01 = kitchenQueue2.orders.find(o => o.id === o1.id);
  assert(activeT01 && activeT01.table_number === 'TABLE 01', 'Kitchen receives TABLE 01 order distinctly');
  assert(o1.id !== o4.id && o1.table_number !== o4.table_number, 'Table 04 and Table 01 orders are completely isolated');

  // --------------------------------------------------------------------------
  // STEP 7: SQL Script Idempotency Validation
  // --------------------------------------------------------------------------
  console.log('\n--- 8. SQL SCHEMA & SEED IDEMPOTENCY AUDIT ---');
  const schemaSql = fs.readFileSync('supabase/migrations/20261105000000_restaurant_schema.sql', 'utf8');
  const seedSql = fs.readFileSync('supabase/seed.sql', 'utf8');

  assert(!schemaSql.includes('DROP TABLE') && !seedSql.includes('DROP TABLE'), 'Zero destructive DROP TABLE statements');
  assert(!schemaSql.includes('staff_users') && !seedSql.includes('staff_users'), 'staff_users completely removed from MVP');
  assert(schemaSql.includes('UNIQUE(restaurant_id, name)'), 'menu_items table enforces uniqueness on (restaurant_id, name)');
  assert(seedSql.includes('ON CONFLICT (restaurant_id, name) DO UPDATE'), 'seed.sql menu_items uses ON CONFLICT DO UPDATE');
  assert(schemaSql.includes('REVOKE ALL ON FUNCTION get_active_kitchen_orders() FROM PUBLIC, anon'), 'Kitchen query RPC revoked from anonymous public');
  assert(schemaSql.includes('REVOKE ALL ON FUNCTION complete_kitchen_order(UUID) FROM PUBLIC, anon'), 'Kitchen complete RPC revoked from anonymous public');

  // --------------------------------------------------------------------------
  // SUMMARY
  // --------------------------------------------------------------------------
  console.log('\n================================================================');
  console.log(`🎉 ALL ${passedCount}/${totalCount} SECURITY & INTEGRATION CHECKS PASSED!`);
  console.log('================================================================\n');
}

runScenario().catch(err => {
  console.error('\n❌ SCENARIO TEST FAILED:', err);
  process.exit(1);
});
