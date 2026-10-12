-- SQLite / Drift schema version 8. Exported from the tested database.
CREATE TABLE "cash_closings" ("id" TEXT NOT NULL, "period_start" TEXT NOT NULL, "closed_at" TEXT NOT NULL, "opening_float" INTEGER NOT NULL, "cash_sales" INTEGER NOT NULL, "cash_refunds" INTEGER NOT NULL, "cash_expenses" INTEGER NOT NULL, "expected" INTEGER NOT NULL, "counted" INTEGER NOT NULL CHECK(counted >= 0), "difference" INTEGER NOT NULL, "kept_float" INTEGER NOT NULL CHECK(kept_float >= 0), "comment" TEXT NOT NULL, "actor_id" TEXT NOT NULL, "actor_name" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "categories" ("id" TEXT NOT NULL, "name" TEXT NOT NULL UNIQUE, PRIMARY KEY ("id"));
CREATE TABLE "expenses" ("id" TEXT NOT NULL, "kind" TEXT NOT NULL CHECK(kind IN ('CHARGE', 'STOCK', 'TREASURY')), "category" TEXT NOT NULL, "amount" INTEGER NOT NULL CHECK(amount > 0), "payment_mode" TEXT NOT NULL, "reason" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, "actor_id" TEXT NOT NULL, "actor_name" TEXT NOT NULL, "recorded_at" TEXT NOT NULL, "cancelled_at" TEXT NULL, "cancel_reason" TEXT NULL, "cancelled_by" TEXT NULL, PRIMARY KEY ("id"));
CREATE TABLE local_product_photos (
      product_id TEXT NOT NULL REFERENCES products(id),
      position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 2),
      path TEXT NOT NULL UNIQUE,
      PRIMARY KEY(product_id, position)
    );
CREATE TABLE "outbox_entries" ("id" TEXT NOT NULL, "sequence" INTEGER NOT NULL UNIQUE, "envelope" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'pending', "attempts" INTEGER NOT NULL DEFAULT 0, "next_attempt_at" TEXT NULL, "error_code" TEXT NULL, "received_at" TEXT NULL, PRIMARY KEY ("id"));
CREATE TABLE "products" ("id" TEXT NOT NULL, "category_id" TEXT NOT NULL REFERENCES categories (id), "name" TEXT NOT NULL, "published" INTEGER NOT NULL DEFAULT 0 CHECK ("published" IN (0, 1)), PRIMARY KEY ("id"));
CREATE TABLE "sale_corrections" ("id" TEXT NOT NULL, "sale_id" TEXT NOT NULL REFERENCES sales (id), "payment_mode" TEXT NOT NULL, "tendered" INTEGER NULL, "change_given" INTEGER NOT NULL CHECK(change_given >= 0), "reason" TEXT NOT NULL, "actor_id" TEXT NOT NULL, "actor_name" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "sale_return_lines" ("return_id" TEXT NOT NULL REFERENCES sale_returns (id), "variant_id" TEXT NOT NULL, "quantity" INTEGER NOT NULL CHECK(quantity > 0), "unit_price" INTEGER NOT NULL, "line_total" INTEGER NOT NULL, "resaleable" INTEGER NOT NULL CHECK ("resaleable" IN (0, 1)), PRIMARY KEY ("return_id", "variant_id"));
CREATE TABLE "sale_returns" ("id" TEXT NOT NULL, "sale_id" TEXT NOT NULL REFERENCES sales (id), "kind" TEXT NOT NULL CHECK(kind IN ('RETURN', 'CANCEL')), "refund_total" INTEGER NOT NULL CHECK(refund_total >= 0), "refund_mode" TEXT NOT NULL, "reason" TEXT NOT NULL, "request_hash" TEXT NOT NULL, "actor_id" TEXT NOT NULL, "actor_name" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "sales" ("id" TEXT NOT NULL, "number" TEXT NOT NULL UNIQUE, "request_hash" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, "snapshot" TEXT NOT NULL, "total" INTEGER NOT NULL CHECK(total >= 0), PRIMARY KEY ("id"));
CREATE TABLE "shop_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));
CREATE TABLE "stock_movements" ("id" TEXT NOT NULL, "variant_id" TEXT NOT NULL REFERENCES variants (id), "kind" TEXT NOT NULL, "quantity" INTEGER NOT NULL, "actor_id" TEXT NOT NULL, "reason" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, "counted" INTEGER NULL, PRIMARY KEY ("id"));
CREATE TABLE "terminal_states" ("singleton" INTEGER NOT NULL DEFAULT 1, "terminal_id" TEXT NOT NULL, "prefix" TEXT NOT NULL UNIQUE, "event_sequence" INTEGER NOT NULL DEFAULT 0, "sale_sequence" INTEGER NOT NULL DEFAULT 0, "last_sync_at" TEXT NULL, PRIMARY KEY ("singleton"));
CREATE TABLE "users" ("id" TEXT NOT NULL, "name" TEXT NOT NULL UNIQUE, "role" TEXT NOT NULL CHECK(role IN ('admin', 'seller')), "pin_hash" TEXT NOT NULL, "pin_salt" TEXT NOT NULL, "pin_iterations" INTEGER NOT NULL, "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), "failed_attempts" INTEGER NOT NULL DEFAULT 0, "locked_until" TEXT NULL, "created_at" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "variants" ("id" TEXT NOT NULL, "product_id" TEXT NOT NULL REFERENCES products (id), "sku" TEXT NOT NULL UNIQUE, "label" TEXT NOT NULL, "price" INTEGER NOT NULL CHECK(price >= 0), "stock" INTEGER NOT NULL CHECK(stock >= 0), "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), "color" TEXT NULL, "size" TEXT NULL, "threshold" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));
CREATE INDEX cash_closings_date_idx ON cash_closings(closed_at);
CREATE INDEX expenses_date_idx ON expenses(occurred_at);
CREATE INDEX movement_variant_idx ON stock_movements(variant_id);
CREATE INDEX outbox_status_sequence_idx ON outbox_entries(status, sequence);
CREATE INDEX sale_corrections_sale_idx ON sale_corrections(sale_id, occurred_at);
CREATE INDEX sale_returns_sale_idx ON sale_returns(sale_id, occurred_at);
CREATE INDEX sales_date_idx ON sales(occurred_at);
PRAGMA user_version = 8;
