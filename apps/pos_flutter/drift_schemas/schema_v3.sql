-- SQLite / Drift schema version 3. Exported from the tested database.
CREATE TABLE "categories" ("id" TEXT NOT NULL, "name" TEXT NOT NULL UNIQUE, PRIMARY KEY ("id"));
CREATE TABLE local_product_photos (
      product_id TEXT NOT NULL REFERENCES products(id),
      position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 2),
      path TEXT NOT NULL UNIQUE,
      PRIMARY KEY(product_id, position)
    );
CREATE TABLE "outbox_entries" ("id" TEXT NOT NULL, "sequence" INTEGER NOT NULL UNIQUE, "envelope" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'pending', "attempts" INTEGER NOT NULL DEFAULT 0, "next_attempt_at" TEXT NULL, "error_code" TEXT NULL, "received_at" TEXT NULL, PRIMARY KEY ("id"));
CREATE TABLE "products" ("id" TEXT NOT NULL, "category_id" TEXT NOT NULL REFERENCES categories (id), "name" TEXT NOT NULL, "published" INTEGER NOT NULL DEFAULT 0 CHECK ("published" IN (0, 1)), PRIMARY KEY ("id"));
CREATE TABLE "sale_corrections" ("id" TEXT NOT NULL, "sale_id" TEXT NOT NULL REFERENCES sales (id), "payment_mode" TEXT NOT NULL, "tendered" INTEGER NULL, "change_given" INTEGER NOT NULL CHECK(change_given >= 0), "reason" TEXT NOT NULL, "actor_id" TEXT NOT NULL, "actor_name" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "sales" ("id" TEXT NOT NULL, "number" TEXT NOT NULL UNIQUE, "request_hash" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, "snapshot" TEXT NOT NULL, "total" INTEGER NOT NULL CHECK(total >= 0), PRIMARY KEY ("id"));
CREATE TABLE "stock_movements" ("id" TEXT NOT NULL, "variant_id" TEXT NOT NULL REFERENCES variants (id), "kind" TEXT NOT NULL, "quantity" INTEGER NOT NULL, "actor_id" TEXT NOT NULL, "reason" TEXT NOT NULL, "origin_id" TEXT NOT NULL, "occurred_at" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "terminal_states" ("singleton" INTEGER NOT NULL DEFAULT 1, "terminal_id" TEXT NOT NULL, "prefix" TEXT NOT NULL UNIQUE, "event_sequence" INTEGER NOT NULL DEFAULT 0, "sale_sequence" INTEGER NOT NULL DEFAULT 0, "last_sync_at" TEXT NULL, PRIMARY KEY ("singleton"));
CREATE TABLE "users" ("id" TEXT NOT NULL, "name" TEXT NOT NULL UNIQUE, "role" TEXT NOT NULL CHECK(role IN ('admin', 'seller')), "pin_hash" TEXT NOT NULL, "pin_salt" TEXT NOT NULL, "pin_iterations" INTEGER NOT NULL, "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), "failed_attempts" INTEGER NOT NULL DEFAULT 0, "locked_until" TEXT NULL, "created_at" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "variants" ("id" TEXT NOT NULL, "product_id" TEXT NOT NULL REFERENCES products (id), "sku" TEXT NOT NULL UNIQUE, "label" TEXT NOT NULL, "price" INTEGER NOT NULL CHECK(price >= 0), "stock" INTEGER NOT NULL CHECK(stock >= 0), "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), PRIMARY KEY ("id"));
CREATE INDEX movement_variant_idx ON stock_movements(variant_id);
CREATE INDEX outbox_status_sequence_idx ON outbox_entries(status, sequence);
CREATE INDEX sale_corrections_sale_idx ON sale_corrections(sale_id, occurred_at);
CREATE INDEX sales_date_idx ON sales(occurred_at);
PRAGMA user_version = 3;
